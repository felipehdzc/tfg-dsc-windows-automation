$dc   = "192.168.137.10"
$cred = Get-Credential "ADTFG\BG_DC_Domain"
$s    = New-PSSession -ComputerName $dc -Credential $cred

Invoke-Command -Session $s -ScriptBlock {
  $paths = @('Packages', 'Wrappers', 'State', 'Logs', '_work', 'Extract') | ForEach-Object { "C:\CCN\$_" }
  New-Item -ItemType Directory -Path $paths -Force | Out-Null
}

# Copia de recursos mediante pipelines
@('570A25', '573-25', '599AB23') | ForEach-Object {
  Copy-Item ".\CCN-STIC-$_-Scripts.zip" -Destination "C:\CCN\Packages\" -ToSession $s
  Copy-Item ".\Apply-CCN$_.ps1" -Destination "C:\CCN\Wrappers\" -ToSession $s
}
Remove-PSSession $s
