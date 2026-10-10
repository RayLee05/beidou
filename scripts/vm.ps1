# 虚拟机 IC 命令/传文件，带重试（实验室有同 IP 克隆机时，连接会随机落到另一台被拒）。
# 用法:
#   .\scripts\vm.ps1 run  "cd beidou && make list"
#   .\scripts\vm.ps1 put  <本地文件> <远端路径>
#   .\scripts\vm.ps1 get  <远端路径> <本地路径>
param(
    [Parameter(Mandatory = $true)][ValidateSet('run', 'put', 'get')][string]$Op,
    [Parameter(Mandatory = $true)][string]$A,
    [string]$B = '',
    [int]$Tries = 20
)

$Target = '7902_13@10.156.34.6'
$Opts = @('-i', "$env:USERPROFILE\.ssh\id_rsa_vm_ic", '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
          '-o', 'ConnectTimeout=10', '-o', 'HostKeyAlgorithms=+ssh-rsa',
          '-o', 'PubkeyAcceptedAlgorithms=+ssh-rsa')

for ($i = 1; $i -le $Tries; $i++) {
    switch ($Op) {
        'run' { $out = & ssh @Opts $Target $A 2>&1 }
        'put' { $out = & scp @Opts -O -r $A "${Target}:$B" 2>&1 }
        'get' { $out = & scp @Opts -O -r "${Target}:$A" $B 2>&1 }
    }
    $code = $LASTEXITCODE
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    if ($code -eq 255 -and $text -match 'Permission denied|Connection (closed|reset)|timed out') {
        Start-Sleep -Seconds 3
        continue
    }
    if ($text) { Write-Output $text }
    exit $code
}
Write-Output "VM_UNREACHABLE after $Tries tries (同 IP 克隆机？)"
exit 255
