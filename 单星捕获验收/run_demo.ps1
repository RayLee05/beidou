param([switch]$NoGui)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$buildRoot=Join-Path $projectRoot 'reports\sim\single_sat_demo'
$sourceRoot=Join-Path $projectRoot '简化BDI信号模拟源及捕获成功判断标准'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$runRoot=Join-Path $buildRoot ('run_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultFile=Join-Path $buildRoot 'result.json'
# Invalidate any older result even if tool discovery or source copying fails.
@{passed=$false;status='pending'} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding utf8
Push-Location -LiteralPath $projectRoot
try {

$toolFolders=@()
if($env:MODELSIM_HOME){$toolFolders+=@($env:MODELSIM_HOME,(Join-Path $env:MODELSIM_HOME 'win64'),(Join-Path $env:MODELSIM_HOME 'bin'))}
$foundVsim=Get-Command vsim.exe -ErrorAction SilentlyContinue
if($foundVsim){$toolFolders+=(Split-Path -Parent $foundVsim.Source)}
$toolFolders+=@('D:\modeltech64_10.5\win64','D:\modeltech64_2020.4\win64','C:\modeltech64_2020.4\win64','C:\questasim64_2021.1\win64')
$toolDir=$toolFolders | Where-Object {(Test-Path -LiteralPath (Join-Path $_ 'vsim.exe')) -and (Test-Path -LiteralPath (Join-Path $_ 'vlog.exe'))} | Select-Object -First 1
if(!$toolDir){throw 'ModelSim/Questa not found. Set MODELSIM_HOME to its installation folder.'}

# The teacher files stay read only. ASCII filenames avoid old simulator path issues.
foreach($name in @('bdi_prn_code_pkg.sv','bdi_signal_source.sv')){
  Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $buildRoot $name) -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb_single_sat_capture.sv') -Destination (Join-Path $buildRoot 'tb_single_sat_capture.sv') -Force
$lib=(Join-Path $buildRoot 'work').Replace('\','/')
$waveFile=(Join-Path $runRoot 'capture.wlf').Replace('\','/')
$csvFile=(Join-Path $runRoot 'capture.csv').Replace('\','/')
$logFile=Join-Path $runRoot 'simulation.log'
  if(!(Test-Path -LiteralPath $lib)){
    & (Join-Path $toolDir 'vlib.exe') $lib
    if($LASTEXITCODE){throw 'vlib failed'}
  }
  $rtlFiles=@((Join-Path $buildRoot 'bdi_prn_code_pkg.sv'),(Join-Path $buildRoot 'bdi_signal_source.sv'),
    (Join-Path $projectRoot 'rtl\common\prn_code_gen.sv'),(Join-Path $projectRoot 'rtl\acq\bdi_sliding_correlator.sv'),
    (Join-Path $buildRoot 'tb_single_sat_capture.sv'))
  & (Join-Path $toolDir 'vlog.exe') -sv -work $lib ('+incdir+'+(Join-Path $projectRoot 'rtl\include')) @rtlFiles *> (Join-Path $buildRoot 'compile.log')
  if($LASTEXITCODE){throw 'Compile failed; see reports/sim/single_sat_demo/compile.log'}
  & (Join-Path $toolDir 'vsim.exe') -c -voptargs=+acc -wlf $waveFile -lib $lib tb_single_sat_capture ('+CSV='+$csvFile) -do 'onfinish exit; log -r /*; run -all; quit -f' *> $logFile
  if($LASTEXITCODE -or !(Select-String -LiteralPath $logFile -SimpleMatch 'TEST PASSED') -or (Select-String -LiteralPath $logFile -Pattern '\*\* (Fatal|Error)')){throw 'Simulation failed; see simulation.log'}
  $rows=@(Import-Csv -LiteralPath $csvFile)
  if($rows.Count -ne 13){throw 'Expected 13 complete windows'}
  $wrong=@($rows | Where-Object {[int]$_.window -le 10})
  $right=@($rows | Where-Object {[int]$_.window -ge 11})
  $maxWrong=($wrong | ForEach-Object {[long]$_.energy} | Measure-Object -Maximum).Maximum
  $minRight=($right | ForEach-Object {[long]$_.energy} | Measure-Object -Minimum).Minimum
  $ratio=$minRight/$maxWrong
  if($ratio -lt 100){throw 'Aligned energy is less than 100 times the worst unaligned result'}
  foreach($row in $rows){
    $expectedPhase=[Math]::Min([int]$row.window-1,10)
    $computedEnergy=[long]$row.sum_a*[long]$row.sum_a+[long]$row.sum_b*[long]$row.sum_b
    if([int]$row.phase -ne $expectedPhase -or [long]$row.accepted_samples -ne [int]$row.window*16368 -or [long]$row.energy -ne $computedEnergy){throw 'Phase/count/energy verification failed'}
    if(([int]$row.window -lt 11 -and [int]$row.capture -ne 0) -or ([int]$row.window -ge 11 -and ([int]$row.capture -ne 1 -or [int]$row.different_samples -ne 0))){throw 'Capture/code comparison failed'}
  }
  $sourceHashes=@{}
  foreach($sourceFile in $rtlFiles){$sourceHashes[(Split-Path -Leaf $sourceFile)]=(Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()}
  @{passed=$true;status='passed';generated_at=(Get-Date -Format o);source_sha256=$sourceHashes;
    first_capture_window=11;capture_phase=10;wrong_energy_max=[long]$maxWrong;
    aligned_energy_min=[long]$minRight;energy_ratio=$ratio;required_ratio=100;
    confirmation_windows=2;aligned_code_samples=49104;accepted_samples=212784;
    csv=$csvFile;waveform=$waveFile;simulator='ModelSim';scope='single satellite acquisition only'} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $resultFile -Encoding utf8
  Write-Output ('PASS: aligned energy / max unaligned energy = '+$ratio)
  Copy-Item -LiteralPath $csvFile -Destination (Join-Path $buildRoot 'capture.csv') -Force
  $runRoot | Set-Content -LiteralPath (Join-Path $buildRoot 'latest_run.txt') -Encoding utf8
  # Open the completed, real simulator recording with only the demonstration signals.
  $doFile=(Join-Path $runRoot 'open_wave.do').Replace('\','/')
  $template=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave.do') -Raw
  $template.Replace('@WAVEFILE@',$waveFile) | Set-Content -LiteralPath $doFile -Encoding ascii
  if(!$NoGui){
    $guiLog=(Join-Path $runRoot 'gui.log').Replace('\','/')
    $process=Start-Process -FilePath (Join-Path $toolDir 'vsim.exe') -ArgumentList ('-gui -l "'+$guiLog+'" -do "do {'+$doFile+'}"') -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    Write-Output ('ModelSim waveform window PID: '+$process.Id)
  }
} catch {
  @{passed=$false;status='failed';error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding utf8
  throw
} finally { Pop-Location }
