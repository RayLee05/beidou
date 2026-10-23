param([switch]$NoGui)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = 'E:\cdownload\作业\BDI_signal_source_student\rtl'
$buildRoot = Join-Path $projectRoot 'reports\sim\single_sat_track'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$runRoot = Join-Path $buildRoot ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultFile = Join-Path $buildRoot 'result.json'
@{passed = $false; status = 'pending'} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding utf8
Push-Location -LiteralPath $projectRoot
try {
  if (!(Test-Path -LiteralPath (Join-Path $sourceRoot 'bdi_signal_source_doppler.sv'))) {
    throw "Signal source not found: $sourceRoot"
  }

  $toolFolders = @()
  if ($env:MODELSIM_HOME) {
    $toolFolders += @($env:MODELSIM_HOME, (Join-Path $env:MODELSIM_HOME 'win64'), (Join-Path $env:MODELSIM_HOME 'bin'))
  }
  $foundVsim = Get-Command vsim.exe -ErrorAction SilentlyContinue
  if ($foundVsim) { $toolFolders += (Split-Path -Parent $foundVsim.Source) }
  $toolFolders += @('D:\modeltech64_10.5\win64', 'D:\modeltech64_2020.4\win64', 'C:\modeltech64_2020.4\win64', 'C:\questasim64_2021.1\win64')
  $toolDir = $toolFolders | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_ 'vsim.exe')) -and (Test-Path -LiteralPath (Join-Path $_ 'vlog.exe'))
  } | Select-Object -First 1
  if (!$toolDir) { throw 'ModelSim/Questa not found. Set MODELSIM_HOME to its installation folder.' }

  foreach ($name in @('bdi_prn_code_pkg.sv', 'bdi_signal_source_doppler.sv')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $buildRoot $name) -Force
  }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb_single_sat_track.sv') -Destination (Join-Path $buildRoot 'tb_single_sat_track.sv') -Force

  $lib = (Join-Path $buildRoot 'work').Replace('\', '/')
  $waveFile = (Join-Path $runRoot 'track.wlf').Replace('\', '/')
  $csvFile = (Join-Path $runRoot 'track.csv').Replace('\', '/')
  $logFile = Join-Path $runRoot 'simulation.log'
  if (!(Test-Path -LiteralPath $lib)) {
    & (Join-Path $toolDir 'vlib.exe') $lib
    if ($LASTEXITCODE) { throw 'vlib failed' }
  }

  $rtlFiles = @(
    (Join-Path $buildRoot 'bdi_prn_code_pkg.sv'),
    (Join-Path $buildRoot 'bdi_signal_source_doppler.sv'),
    (Join-Path $projectRoot 'rtl\common\prn_code_gen.sv'),
    (Join-Path $projectRoot 'rtl\common\carrier_lut.sv'),
    (Join-Path $projectRoot 'rtl\track\carrier_mixer_nco.sv'),
    (Join-Path $projectRoot 'rtl\track\code_nco.sv'),
    (Join-Path $projectRoot 'rtl\track\code_ram.sv'),
    (Join-Path $projectRoot 'rtl\track\correlator_epl.sv'),
    (Join-Path $projectRoot 'rtl\track\track_loop.sv'),
    (Join-Path $projectRoot 'rtl\track\tracking_channel.sv'),
    (Join-Path $buildRoot 'tb_single_sat_track.sv')
  )
  & (Join-Path $toolDir 'vlog.exe') -sv -work $lib ('+incdir+' + (Join-Path $projectRoot 'rtl\include')) @rtlFiles *> (Join-Path $buildRoot 'compile.log')
  if ($LASTEXITCODE) { throw 'Compile failed; see reports/sim/single_sat_track/compile.log' }

  $logSignals = @(
    '/tb_single_sat_track/if_valid',
    '/tb_single_sat_track/if_sample',
    '/tb_single_sat_track/dump_valid',
    '/tb_single_sat_track/mag_e',
    '/tb_single_sat_track/mag_p',
    '/tb_single_sat_track/mag_l',
    '/tb_single_sat_track/el_permille',
    '/tb_single_sat_track/d_dll',
    '/tb_single_sat_track/i_p',
    '/tb_single_sat_track/q_p',
    '/tb_single_sat_track/iq_permille',
    '/tb_single_sat_track/d_pll',
    '/tb_single_sat_track/dop_word',
    '/tb_single_sat_track/dop_hz',
    '/tb_single_sat_track/freq_word',
    '/tb_single_sat_track/locked',
    '/tb_single_sat_track/full_dumps',
    '/tb_single_sat_track/d_fll'
  ) -join ' '
  $batchDo = "onfinish exit; log $logSignals; run -all; quit -f"
  & (Join-Path $toolDir 'vsim.exe') -c -voptargs=+acc -wlf $waveFile -lib $lib tb_single_sat_track ('+CSV=' + $csvFile) -do $batchDo *> $logFile
  if ($LASTEXITCODE -or !(Select-String -LiteralPath $logFile -SimpleMatch 'PASS: single satellite tracking') -or (Select-String -LiteralPath $logFile -Pattern '\*\* (Fatal|Error)')) {
    throw 'Simulation failed; see simulation.log'
  }

  $rows = @(Import-Csv -LiteralPath $csvFile)
  if ($rows.Count -lt 100) { throw "Expected at least 100 full dumps, got $($rows.Count)" }
  $first = $rows[0]
  if ([int]$first.el_permille -le 100) { throw "Initial code error not visible: el_permille=$($first.el_permille)" }
  if ([int]$first.dop_word -ne 39360) { throw "Initial doppler word is $($first.dop_word), expected 39360" }
  $tail = @($rows | Select-Object -Last 100)
  foreach ($row in $tail) {
    $prompt = [int]$row.mag_p
    $early = [int]$row.mag_e
    $late = [int]$row.mag_l
    $el = [int]$row.el_permille
    $iq = [int]$row.iq_permille
    $dop = [int]$row.dop_word
    if ($prompt -le $early -or $prompt -le $late -or $el -ge 100 -or $iq -ge 100 -or [Math]::Abs($dop - 65600) -ge 3936) {
      throw "Steady window failed at dump $($row.dump): P=$prompt E=$early L=$late el=$el iq=$iq dop=$dop"
    }
  }

  $last = $tail[-1]
  @{
    passed = $true
    status = 'passed'
    generated_at = (Get-Date -Format o)
    simulator = 'ModelSim'
    valid_ms = 640
    full_dumps = $rows.Count
    initial_code_error_chip = 0.15
    initial_doppler_word = 39360
    initial_el_permille = [int]$first.el_permille
    steady_dumps = 100
    final_doppler_word = [int]$last.dop_word
    final_dop_hz = [int]$last.dop_hz
    final_el_permille = [int]$last.el_permille
    final_iq_permille = [int]$last.iq_permille
    final_mag_e = [int]$last.mag_e
    final_mag_p = [int]$last.mag_p
    final_mag_l = [int]$last.mag_l
    csv = $csvFile
    waveform = $waveFile
  } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $resultFile -Encoding utf8

  Copy-Item -LiteralPath $csvFile -Destination (Join-Path $buildRoot 'track.csv') -Force
  $runRoot | Set-Content -LiteralPath (Join-Path $buildRoot 'latest_run.txt') -Encoding utf8
  Write-Output ("PASS: last 100 ms locked, dop_word=$($last.dop_word) el=$($last.el_permille) iq=$($last.iq_permille)")

  $doFile = (Join-Path $runRoot 'open_wave.do').Replace('\', '/')
  $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave.do') -Raw
  $template.Replace('@WAVEFILE@', $waveFile) | Set-Content -LiteralPath $doFile -Encoding ascii
  if (!$NoGui) {
    $guiLog = (Join-Path $runRoot 'gui.log').Replace('\', '/')
    $process = Start-Process -FilePath (Join-Path $toolDir 'vsim.exe') -ArgumentList ('-gui -l "' + $guiLog + '" -do "do {' + $doFile + '}"') -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    Write-Output ('ModelSim waveform window PID: ' + $process.Id)
  }
} catch {
  @{passed = $false; status = 'failed'; error = $_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding utf8
  throw
} finally {
  Pop-Location
}
