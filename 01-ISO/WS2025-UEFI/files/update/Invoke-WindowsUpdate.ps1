$ErrorActionPreference = 'Stop'

$provRoot = 'C:\Provisioning'
$logRoot  = 'C:\Provisioning\Logs'
$doneFile = 'C:\Provisioning\WindowsUpdate.done'
$failFile = 'C:\Provisioning\WindowsUpdate.failed'
$logFile  = Join-Path $logRoot 'Invoke-WindowsUpdate.log'

New-Item -Path $provRoot -ItemType Directory -Force | Out-Null
New-Item -Path $logRoot  -ItemType Directory -Force | Out-Null

Start-Transcript -Path $logFile -Append

try {
  Import-Module PSWindowsUpdate -Force

  sc.exe config wuauserv start= demand | Out-Null
  sc.exe config bits     start= demand | Out-Null
  sc.exe config dosvc    start= demand | Out-Null
  sc.exe config usosvc   start= demand | Out-Null

  foreach ($svc in 'wuauserv','usosvc') {
    try { Start-Service $svc -ErrorAction Stop } catch {}
  }
  try { Start-Service bits  -ErrorAction Stop } catch {}
  try { Start-Service dosvc -ErrorAction Stop } catch {}

  try {
    Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null
  } catch {}

  Install-WindowsUpdate `
    -MicrosoftUpdate `
    -AcceptAll `
    -AutoReboot `
    -RecurseCycle 3 `
    -Verbose

  $pending = @(Get-WindowsUpdate -MicrosoftUpdate).Count
  if ($pending -eq 0) {
    Set-Content -Path $doneFile -Value "OK $(Get-Date)"
    Remove-Item $failFile -Force -ErrorAction SilentlyContinue
  } else {
    throw "Siguen quedando $pending actualizaciones pendientes."
  }
}
catch {
  $_ | Out-String | Set-Content -Path $failFile
  throw
}
finally {
  Stop-Transcript
}