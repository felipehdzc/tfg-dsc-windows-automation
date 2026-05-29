param(
  [Parameter(Mandatory)][string]$ZipPath,
  [ValidateSet('ENS','DIFUSION LIMITADA','INFORMACION CLASIFICADA')]
  [string]$Grade = 'ENS',

  # Por defecto A-F 
  [string[]]$Annexes = @('A','B','C','D','E','F'),

  # Incrementales opcionales (ENS tiene RDP y NESSUS)
  [switch]$IncludeIncrementals,
  [string[]]$Incrementals = @('RDP','NESSUS'),

  [switch]$CreateBaseOUs,     # crea Servidores/Clientes si no existen
  [switch]$ForceReinstall,

  [string]$ServersOuDn,
  [string]$ClientsOuDn,
  [ValidateSet('Yes','No')]
  [string]$LinkEnabled = 'No'
)

$ErrorActionPreference = 'Stop'

function Test-Folders {
  'C:\CCN\Logs','C:\CCN\State','C:\CCN\Extract' | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
  }
}

function Start-Log {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $log = "C:\CCN\Logs\Apply-CCN570A25-$ts.log"
  Start-Transcript -Path $log -Append | Out-Null
  Write-Host ">> Log: $log" -ForegroundColor Cyan
}

function Stop-Log { try { Stop-Transcript | Out-Null } catch {} }

function Expand-ZipIfNeeded {
  param([string]$Zip,[string]$Dest,[switch]$Force)

  if (-not (Test-Path $Zip)) { throw "No existe el ZIP: $Zip" }
  if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }

  $marker = Join-Path $Dest ".extracted"
  if ($Force -or -not (Test-Path $marker)) {
    Get-ChildItem $Dest -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $Zip -DestinationPath $Dest -Force
    New-Item -ItemType File -Path $marker -Force | Out-Null
  }

  # Si el ZIP trae un único directorio raíz, úsalo como root real
  $items = Get-ChildItem $Dest -Force | Where-Object { $_.Name -ne '.extracted' }
  $dirs  = $items | Where-Object { $_.PSIsContainer }
  $files = $items | Where-Object { -not $_.PSIsContainer }

  if ($dirs.Count -eq 1 -and $files.Count -eq 0) { return $dirs[0].FullName }
  return $Dest
}

function Get-GpoDisplayNamesFromBackupXml {
  param([string]$Folder)

  $names = New-Object System.Collections.Generic.HashSet[string]
  Get-ChildItem -Path $Folder -Recurse -Filter Backup.xml -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      [xml]$x = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
      $dn = $x.SelectSingleNode("//*[local-name()='DisplayName'][1]")
      if ($dn -and $dn.InnerText) { [void]$names.Add($dn.InnerText.Trim()) }

    } catch {}
  }
  return ($names | Sort-Object)
}

function Confirm-GpoImported {
  param([string]$GpoName,[string]$BackupFolder)

  if (-not (Get-GPO -Name $GpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $GpoName | Out-Null
  }

  # Import por nombre de backup (como hacen los anexos CCN)
  Import-GPO -BackupGPOName $GpoName -TargetName $GpoName -Path $BackupFolder | Out-Null
}

function Test-GpoLink {
  param(
    [string]$GpoName,
    [string]$TargetDn,
    [bool]$Enabled = $false
  )

  $links = (Get-GPInheritance -Target $TargetDn).GpoLinks
  $exists = $links | Where-Object { $_.DisplayName -eq $GpoName }

  if (-not $exists) {
    $en = if ($Enabled) { 'Yes' } else { 'No' }
    New-GPLink -Name $GpoName -Target $TargetDn -LinkEnabled $en
  } else {
    $en = if ($Enabled) { 'Yes' } else { 'No' }
    Set-GPLink -Name $GpoName -Target $TargetDn -LinkEnabled $en 
  }
}

function Get-TargetsFor570 {
  param(
    [string]$GpoName,
    [string]$DomainDn,
    [string]$ServersOuDn,
    [string]$ClientsOuDn,
    [string]$DcOuDn
  )

  if ($GpoName -match 'Incremental') { return @($ServersOuDn,$DcOuDn) }
  if ($GpoName -match '_Dominio_')   { return @($DomainDn) }
  if ($GpoName -match '_DC_')        { return @($DcOuDn) }
  if ($GpoName -match 'Servidor Miembro') {
    if ($ClientsOuDn) { return @($ServersOuDn, $ClientsOuDn) }
    return @($ServersOuDn)
  }
  if ($GpoName -match 'Cliente' -or $GpoName -match '_Cliente_') { return @($ClientsOuDn) }

  return @($ServersOuDn)
}

try {
  Test-Folders
  Start-Log

  Import-Module ActiveDirectory -ErrorAction Stop
  Import-Module GroupPolicy     -ErrorAction Stop

  $domainDn   = (Get-ADDomain).DistinguishedName
  $serversOuDn = if ($PSBoundParameters.ContainsKey('ServersOuDn') -and $ServersOuDn) { $ServersOuDn } else { "OU=Servidores,$domainDn" }
  $clientsOuDn = if ($PSBoundParameters.ContainsKey('ClientsOuDn') -and $ClientsOuDn) { $ClientsOuDn } else { "OU=Clientes,$domainDn" }
  $dcOuDn      = "OU=Domain Controllers,$domainDn"


  if ($CreateBaseOUs) {
    foreach ($ouName in @('Servidores','Clientes')) {
      $dn = "OU=$ouName,$domainDn"
      if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$dn)" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ouName -Path $domainDn | Out-Null
      }
    }
  }

  $state = "C:\CCN\State\CCN570A25-$Grade-$($Annexes -join '')-INC$($IncludeIncrementals.IsPresent).txt"
  if ((Test-Path $state) -and -not $ForceReinstall) {
    Write-Host ">> Marker existe, salto ejecución: $state" -ForegroundColor Yellow
    return
  }

  $extractBase = "C:\CCN\Extract\570A25"
  $root = Expand-ZipIfNeeded -Zip $ZipPath -Dest $extractBase -Force:$ForceReinstall

  $gradePath = Join-Path $root $Grade
  if (-not (Test-Path $gradePath)) { throw "No existe carpeta de grado '$Grade' dentro de: $root" }

  # --- ANEXOS ---
  $annexDirs = Get-ChildItem -Path $gradePath -Directory | Where-Object { $_.Name -like 'ANEXO *' }
  foreach ($dir in $annexDirs) {
    if ($dir.Name -match '^ANEXO\s+([A-Z])\b') {
      $letter = $Matches[1]
      if ($Annexes -notcontains $letter) { continue }
    } else { continue }

    Write-Host ">> Importando desde: $($dir.FullName)" -ForegroundColor Cyan
    $gpos = Get-GpoDisplayNamesFromBackupXml -Folder $dir.FullName

    foreach ($gpo in $gpos) {
      Confirm-GpoImported -GpoName $gpo -BackupFolder $dir.FullName
      $targets = Get-TargetsFor570 -GpoName $gpo -DomainDn $domainDn -ServersOuDn $serversOuDn -ClientsOuDn $clientsOuDn -DcOuDn $dcOuDn
      $enable = ($LinkEnabled -eq 'Yes')
      foreach ($t in $targets) { Test-GpoLink -GpoName $gpo -TargetDn $t -Enabled:$enable }
    }
  }

  # --- INCREMENTALES ---
  if ($IncludeIncrementals) {
    $incDirs = Get-ChildItem -Path $gradePath -Directory | Where-Object { $_.Name -like 'INCREMENTAL *' }
    foreach ($dir in $incDirs) {
      $nameUpper = $dir.Name.ToUpper()
      $wanted = $false
      foreach ($inc in $Incrementals) {
        if ($nameUpper -like "*$($inc.ToUpper())*") { $wanted = $true; break }
      }
      if (-not $wanted) { continue }

      Write-Host ">> Importando incremental desde: $($dir.FullName)" -ForegroundColor Cyan
      $gpos = Get-GpoDisplayNamesFromBackupXml -Folder $dir.FullName

      foreach ($gpo in $gpos) {
        Confirm-GpoImported -GpoName $gpo -BackupFolder $dir.FullName
        $enable = ($LinkEnabled -eq 'Yes')
        foreach ($t in @($serversOuDn,$dcOuDn)) { Test-GpoLink -GpoName $gpo -TargetDn $t -Enabled:$enable }
      }
    }
  }

  New-Item -ItemType File -Path $state -Force | Out-Null
  Write-Host ">> OK 570A25 importada (links deshabilitados). Marker: $state" -ForegroundColor Green
}
finally {
  Stop-Log
}
