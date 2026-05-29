<# Apply-CCN573-25.ps1 (DC)
Requisitos: GPMC instalado (GroupPolicy module)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ZipPath,

  [ValidateSet('ESTANDAR','USO OFICIAL','MATERIAS CLASIFICADAS')]
  [string]$Nivel = 'ESTANDAR',

  [string[]]$TargetOuDns = @('OU=ServidoresDeFicheros,OU=Servidores,DC=ad,DC=umtfg,DC=com'),

  [ValidateSet('Yes','No')]
  [string]$LinkEnabled = 'No',

  [switch]$ForceReimport,

  [string]$WorkRoot  = 'C:\CCN\_work',
  [string]$StateRoot = 'C:\CCN\State',
  [string]$LogRoot   = 'C:\CCN\Logs'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-Folders {
  foreach ($p in @($WorkRoot,$StateRoot,$LogRoot)) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
  }
}

function Start-Log {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $log = Join-Path $LogRoot "Apply-CCN573-25-$Nivel-$ts.log"
  Start-Transcript -Path $log -Append | Out-Null
  Write-Host ">> Log: $log" -ForegroundColor Cyan
}

function Stop-Log { try { Stop-Transcript | Out-Null } catch {} }

function Expand-ZipCached {
  param([string]$Zip,[string]$Dest,[string]$CacheMarker,[switch]$Force)
  if (-not (Test-Path $Zip)) { throw "No existe ZipPath: $Zip" }
  Unblock-File -Path $Zip -ErrorAction SilentlyContinue

  $zipInfo = Get-Item $Zip
  $sig = "$($zipInfo.Length)|$($zipInfo.LastWriteTimeUtc.ToString('o'))"

  $need = $true
  if (-not $Force -and (Test-Path $CacheMarker)) {
    $old = (Get-Content $CacheMarker -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($old -eq $sig -and (Test-Path $Dest)) { $need = $false }
  }

  if ($need) {
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $Dest -Force
    Set-Content -Path $CacheMarker -Value $sig -Force
  }

  return $Dest
}

function Get-GpoMetaFromBackupXml {
  param([string]$BackupXmlPath)

  [xml]$doc = Get-Content -LiteralPath $BackupXmlPath -Raw -Encoding UTF8

  $displayNode = $doc.SelectSingleNode("//*[local-name()='GroupPolicyObject']//*[local-name()='DisplayName'][1]")
  
  if (-not $displayNode -or [string]::IsNullOrWhiteSpace($displayNode.InnerText)) {
    throw "No pude leer DisplayName en: $BackupXmlPath"
  }

  $backupIdFolder = Split-Path (Split-Path $BackupXmlPath -Parent) -Leaf   # {GUID}
  $backupRoot     = Split-Path (Split-Path $BackupXmlPath -Parent) -Parent # carpeta que contiene el {GUID}

  [pscustomobject]@{
    DisplayName = $displayNode.InnerText.Trim()
    BackupGuid  = [Guid]($backupIdFolder.Trim('{}'))
    BackupRoot  = $backupRoot
  }
}

function Set-GpoLink {
  param([string]$GpoName,[string]$TargetDn,[string]$Enabled)

  $links  = (Get-GPInheritance -Target $TargetDn).GpoLinks
  $exists = $links | Where-Object { $_.DisplayName -eq $GpoName }

  if (-not $exists) {
    New-GPLink -Name $GpoName -Target $TargetDn -LinkEnabled $Enabled | Out-Null
  } else {
    Set-GPLink -Name $GpoName -Target $TargetDn -LinkEnabled $Enabled | Out-Null
  }
}

Test-Folders
Start-Log
try {
  Import-Module GroupPolicy -ErrorAction Stop

  $state = Join-Path $StateRoot "CCN573-25-$Nivel-Imported.txt"
  if ((Test-Path $state) -and -not $ForceReimport) {
    Write-Host ">> Marker existe, no reimporto: $state" -ForegroundColor Yellow
    return
  }

  $work = Join-Path $WorkRoot "573-25"
  $cacheMarker = Join-Path $work ".zipcache.txt"
  $extract = Expand-ZipCached -Zip $ZipPath -Dest $work -CacheMarker $cacheMarker -Force:$ForceReimport

  $base = Join-Path $extract "Scripts-573-25\$Nivel"
  if (-not (Test-Path $base)) { throw "No existe nivel '$Nivel' en: $base" }

  $incFolder = Get-ChildItem -Path $base -Directory |
    Where-Object { $_.Name -like 'CCN-STIC-573 Incremental Servidor de Ficheros*' } |
    Select-Object -First 1
  if (-not $incFolder) { throw "No encuentro carpeta incremental 573 dentro de: $base" }

  $backupXml = Get-ChildItem -Path $incFolder.FullName -Recurse -Filter 'Backup.xml' -File | Select-Object -First 1
  if (-not $backupXml) { throw "No encuentro Backup.xml dentro de: $($incFolder.FullName)" }

  $meta = Get-GpoMetaFromBackupXml -BackupXmlPath $backupXml.FullName
  Write-Host ">> GPO (573) detectado: $($meta.DisplayName)" -ForegroundColor Cyan

  if ($ForceReimport -and (Get-GPO -Name $meta.DisplayName -ErrorAction SilentlyContinue)) {
    Remove-GPO -Name $meta.DisplayName -Confirm:$false
  }

  Import-GPO -BackupId $meta.BackupGuid -Path $meta.BackupRoot -TargetName $meta.DisplayName -CreateIfNeeded | Out-Null

  foreach ($ou in $TargetOuDns) {
    Set-GpoLink -GpoName $meta.DisplayName -TargetDn $ou -Enabled $LinkEnabled
    Write-Host ">> Link $LinkEnabled -> $ou" -ForegroundColor Green
  }

  New-Item -ItemType File -Path $state -Force | Out-Null
  Write-Host ">> OK 573-25 importada y linkada (LinkEnabled=$LinkEnabled)." -ForegroundColor Green
}
finally { Stop-Log }
