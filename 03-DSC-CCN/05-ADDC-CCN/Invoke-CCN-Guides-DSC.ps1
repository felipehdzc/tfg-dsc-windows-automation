<#
Invoke-CCN-Guides-DSC.ps1
- Staging (ZIPs + Apply scripts) al DC
- PUSH DSC al DC para ejecutar Apply-CCN570A25 / 573-25 / 599AB23

Requisitos:
- WinRM funcionando contra el DC
- Credencial con permisos de Domain Admin (para importar/linkar GPOs)
- LCM del DC permitiendo PsDscRunAsCredential (normal en WS2019/2022/2025)
#>

[CmdletBinding()]
param(
  # DC destino (IP o nombre)
  [Parameter(Mandatory)]
  [string]$DcComputerName,

  # Credencial Domain Admin
  [Parameter(Mandatory)]
  [pscredential]$DomainCred,

  # --- Paths locales (por defecto: mismos nombres en la carpeta del script) ---
  [string]$Zip570Local  = (Join-Path $PSScriptRoot 'CCN-STIC-570A25-Scripts.zip'),
  [string]$Zip573Local  = (Join-Path $PSScriptRoot 'CCN-STIC-573-25-Scripts.zip'),
  [string]$Zip599Local  = (Join-Path $PSScriptRoot 'CCN-STIC-599AB23-Scripts.zip'),

  [string]$Apply570Local = (Join-Path $PSScriptRoot 'Apply-CCN570A25.ps1'),
  [string]$Apply573Local = (Join-Path $PSScriptRoot 'Apply-CCN573-25.ps1'),
  [string]$Apply599Local = (Join-Path $PSScriptRoot 'Apply-CCN599AB23.ps1'),

  # --- Qué guías ejecutar ---
  [switch]$Run570 = $true,
  [switch]$Run573 = $true,
  [switch]$Run599 = $true,

  # --- Params guía 570A25 (DC) ---
  [ValidateSet('ENS','DIFUSION LIMITADA','INFORMACION CLASIFICADA')]
  [string]$Grade570 = 'ENS',
  [string[]]$Annexes570 = @('A','B','C','D','E','F'),
  [switch]$IncludeIncrementals570,
  [string[]]$Incrementals570 = @('RDP','NESSUS'),
  [switch]$CreateBaseOUs570,
  [switch]$ForceReinstall570,
  [string]$ClientsOuDn570 = 'OU=EstacionesWS25,OU=Clientes,DC=ad,DC=umtfg,DC=com',
  [string]$ServersOuDn570 = 'OU=Servidores,DC=ad,DC=umtfg,DC=com',
  [ValidateSet('Yes','No')]
  [string]$LinkEnabled570 = 'No',

  # --- Params guía 573-25 (FS) ---
  [ValidateSet('ESTANDAR','USO OFICIAL','MATERIAS CLASIFICADAS')]
  [string]$Nivel573 = 'ESTANDAR',
  [string[]]$TargetOuDns573 = @('OU=ServidoresDeFicheros,OU=Servidores,DC=ad,DC=umtfg,DC=com'),
  [ValidateSet('Yes','No')]
  [string]$LinkEnabled573 = 'No',
  [switch]$ForceReimport573,

  # --- Params guía 599AB23 (Win11) ---
  [ValidateSet('ESTANDAR','USO OFICIAL','MATERIAS CLASIFICADAS')]
  [string]$Nivel599 = 'ESTANDAR',
  [string[]]$TargetOuDns599 = @('OU=EstacionesDeTrabajo,OU=Clientes,DC=ad,DC=umtfg,DC=com'),
  [string[]]$OnlyGpoNames599,
  [ValidateSet('Yes','No')]
  [string]$LinkEnabled599 = 'No',
  [switch]$ForceReimport599,

  # --- Staging ---
  [switch]$SkipStaging,

  # --- Post-check ---
  [switch]$PostCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------
# Helpers
# -----------------------------
function Assert-FileExists([string]$p) {
  if (-not (Test-Path $p)) { throw "No existe el fichero: $p" }
}

function Get-Patched570ToTemp([string]$src) {
  # Parche mínimo: reemplaza el ternario no compatible con PS5.1
  $raw = Get-Content -LiteralPath $src -Raw
  if ($raw -match '\?\s*''Yes''\s*:\s*''No''') {
    $raw = $raw -replace '\(\$Enabled\s*\?\s*''Yes''\s*:\s*''No''\)', '$(if ($Enabled) { ''Yes'' } else { ''No'' })'
  }
  $tmp = Join-Path $env:TEMP ("Apply-CCN570A25.patched.{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
  Set-Content -LiteralPath $tmp -Value $raw -Encoding UTF8
  return $tmp
}

# -----------------------------
# Validaciones locales
# -----------------------------
if ($Run570) { Assert-FileExists $Zip570Local; Assert-FileExists $Apply570Local }
if ($Run573) { Assert-FileExists $Zip573Local; Assert-FileExists $Apply573Local }
if ($Run599) { Assert-FileExists $Zip599Local; Assert-FileExists $Apply599Local }

# -----------------------------
# Paths remotos en DC
# -----------------------------
$RemotePkgDir  = 'C:\CCN\Packages'
$RemoteWrapDir = 'C:\CCN\Wrappers'

$RemoteZip570  = Join-Path $RemotePkgDir 'CCN-STIC-570A25-Scripts.zip'
$RemoteZip573  = Join-Path $RemotePkgDir 'CCN-STIC-573-25-Scripts.zip'
$RemoteZip599  = Join-Path $RemotePkgDir 'CCN-STIC-599AB23-Scripts.zip'

$RemoteApply570 = Join-Path $RemoteWrapDir 'Apply-CCN570A25.ps1'
$RemoteApply573 = Join-Path $RemoteWrapDir 'Apply-CCN573-25.ps1'
$RemoteApply599 = Join-Path $RemoteWrapDir 'Apply-CCN599AB23.ps1'

# Markers (para TestScript DSC)
$AnnexKey = ($Annexes570 -join '')
$State570 = "C:\CCN\State\CCN570A25-$Grade570-$AnnexKey-INC$($IncludeIncrementals570.IsPresent).txt"
$State573 = "C:\CCN\State\CCN573-25-$Nivel573-Imported.txt"
$State599 = "C:\CCN\State\CCN599AB23-$Nivel599-Imported.txt"

# -----------------------------
# 1) STAGING al DC (ZIPs + scripts)
# -----------------------------
if (-not $SkipStaging) {
  Write-Host ">> [STAGE] Conectando a $DcComputerName para copiar ZIPs/scripts..." -ForegroundColor Cyan
  $sess = New-PSSession -ComputerName $DcComputerName -Credential $DomainCred

  try {
    Invoke-Command -Session $sess -ScriptBlock {
      New-Item -ItemType Directory -Path C:\CCN\Packages,C:\CCN\Wrappers,C:\CCN\State,C:\CCN\Logs,C:\CCN\_work,C:\CCN\Extract -Force | Out-Null
    }

    if ($Run570) {
      $patched570 = Get-Patched570ToTemp -src $Apply570Local
      Copy-Item -ToSession $sess -Path $Zip570Local -Destination $RemoteZip570 -Force
      Copy-Item -ToSession $sess -Path $patched570 -Destination $RemoteApply570 -Force
      Remove-Item $patched570 -Force -ErrorAction SilentlyContinue
    }
    if ($Run573) {
      Copy-Item -ToSession $sess -Path $Zip573Local -Destination $RemoteZip573 -Force
      Copy-Item -ToSession $sess -Path $Apply573Local -Destination $RemoteApply573 -Force
    }
    if ($Run599) {
      Copy-Item -ToSession $sess -Path $Zip599Local -Destination $RemoteZip599 -Force
      Copy-Item -ToSession $sess -Path $Apply599Local -Destination $RemoteApply599 -Force
    }

    Write-Host ">> [STAGE] OK: paquetes y wrappers copiados al DC." -ForegroundColor Green
  }
  finally {
    Remove-PSSession $sess -ErrorAction SilentlyContinue
  }
} else {
  Write-Host ">> [STAGE] SkipStaging activado: asumo que ya existe C:\CCN\Packages y C:\CCN\Wrappers en el DC." -ForegroundColor Yellow
}

# -----------------------------
# 2) DSC config (en el DC) para ejecutar Apply scripts
# -----------------------------
$Out = Join-Path $PSScriptRoot "DSC-OUT-CCN-GPOs"
New-Item -ItemType Directory -Path $Out -Force | Out-Null
Remove-Item (Join-Path $Out '*') -Recurse -Force -ErrorAction SilentlyContinue

Configuration CCN_GPO_Apply_OnDC {
  param(
    [string]$NodeName,

    [pscredential]$RunAsCred,

    [bool]$Do570,
    [bool]$Do573,
    [bool]$Do599,

    [string]$Zip570,
    [string]$Zip573,
    [string]$Zip599,

    [string]$Apply570,
    [string]$Apply573,
    [string]$Apply599,

    # 570 params
    [string]$Grade570,
    [string[]]$Annexes570,
    [bool]$IncludeIncrementals570,
    [string[]]$Incrementals570,
    [bool]$CreateBaseOUs570,
    [bool]$ForceReinstall570,
    [string]$State570,
    [string]$ClientsOuDn570,
    [string]$ServersOuDn570,
    [string]$LinkEnabled570,


    # 573 params
    [string]$Nivel573,
    [string[]]$TargetOuDns573,
    [string]$LinkEnabled573,
    [bool]$ForceReimport573,
    [string]$State573,

    # 599 params
    [string]$Nivel599,
    [string[]]$TargetOuDns599,
    [string[]]$OnlyGpoNames599,
    [string]$LinkEnabled599,
    [bool]$ForceReimport599,
    [string]$State599
  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration

  Node $NodeName {

    WindowsFeature GPMC {
      Name   = 'GPMC'
      Ensure = 'Present'
    }

    Script AssertStaging {
      PsDscRunAsCredential = $RunAsCred
      TestScript = {
        $ok = $true
        foreach ($p in @('C:\CCN\Packages','C:\CCN\Wrappers')) {
          if (-not (Test-Path $p)) { $ok = $false }
        }
        return $ok
      }
      SetScript = {
        New-Item -ItemType Directory -Path C:\CCN\Packages,C:\CCN\Wrappers,C:\CCN\State,C:\CCN\Logs,C:\CCN\_work,C:\CCN\Extract -Force | Out-Null
      }
      GetScript = { @{ Result = 'Folders ensured' } }
      DependsOn = '[WindowsFeature]GPMC'
    }

    # -------------- 570A25 --------------
    Script Apply570 {
      PsDscRunAsCredential = $RunAsCred

      TestScript = {
        if (-not $using:Do570) { return $true }
        if ($using:ForceReinstall570) { return $false }
        return (Test-Path $using:State570)
      }

      SetScript = {
        if (-not $using:Do570) { return }

        if (-not (Test-Path $using:Zip570))   { throw "ZIP 570 no encontrado: $using:Zip570" }
        if (-not (Test-Path $using:Apply570)) { throw "Apply 570 no encontrado: $using:Apply570" }

        & $using:Apply570 `
          -ZipPath $using:Zip570 `
          -Grade $using:Grade570 `
          -Annexes $using:Annexes570 `
          -IncludeIncrementals:($using:IncludeIncrementals570) `
          -Incrementals $using:Incrementals570 `
          -CreateBaseOUs:($using:CreateBaseOUs570) `
          -ForceReinstall:($using:ForceReinstall570) `
          -ServersOuDn $using:ServersOuDn570 `
          -ClientsOuDn $using:ClientsOuDn570 `
          -LinkEnabled $using:LinkEnabled570
      }

      GetScript = { @{ Result = '570 executed' } }
      DependsOn = '[Script]AssertStaging'
    }

    # -------------- 573-25 --------------
    Script Apply573 {
      PsDscRunAsCredential = $RunAsCred

      TestScript = {
        if (-not $using:Do573) { return $true }
        if ($using:ForceReimport573) { return $false }
        return (Test-Path $using:State573)
      }

      SetScript = {
        if (-not $using:Do573) { return }

        if (-not (Test-Path $using:Zip573))   { throw "ZIP 573 no encontrado: $using:Zip573" }
        if (-not (Test-Path $using:Apply573)) { throw "Apply 573 no encontrado: $using:Apply573" }

        $args = @{
          ZipPath      = $using:Zip573
          Nivel        = $using:Nivel573
          TargetOuDns  = $using:TargetOuDns573
          LinkEnabled  = $using:LinkEnabled573
        }
        if ($using:ForceReimport573) { $args.ForceReimport = $true }

        & $using:Apply573 @args
      }

      GetScript = { @{ Result = '573 executed' } }
      DependsOn = @('[Script]AssertStaging','[WindowsFeature]GPMC','[Script]Apply570')
    }

    # -------------- 599AB23 --------------
    Script Apply599 {
      PsDscRunAsCredential = $RunAsCred

      TestScript = {
        if (-not $using:Do599) { return $true }
        if ($using:ForceReimport599) { return $false }
        return (Test-Path $using:State599)
      }

      SetScript = {
        if (-not $using:Do599) { return }

        if (-not (Test-Path $using:Zip599))   { throw "ZIP 599 no encontrado: $using:Zip599" }
        if (-not (Test-Path $using:Apply599)) { throw "Apply 599 no encontrado: $using:Apply599" }

        $args = @{
          ZipPath      = $using:Zip599
          Nivel        = $using:Nivel599
          TargetOuDns  = $using:TargetOuDns599
          LinkEnabled  = $using:LinkEnabled599
        }
        if ($using:OnlyGpoNames599) { $args.OnlyGpoNames = $using:OnlyGpoNames599 }
        if ($using:ForceReimport599) { $args.ForceReimport = $true }

        & $using:Apply599 @args
      }

      GetScript = { @{ Result = '599 executed' } }
      DependsOn = @('[Script]AssertStaging','[WindowsFeature]GPMC','[Script]Apply573')
    }
  }
}

# ConfigData para credenciales en MOF (lab)
$ConfigData = @{
  AllNodes = @(
    @{
      NodeName = $DcComputerName
      PSDscAllowPlainTextPassword = $true
      PSDscAllowDomainUser        = $true
    }
  )
}

Write-Host ">> [DSC] Compilando MOF para $DcComputerName..." -ForegroundColor Cyan

CCN_GPO_Apply_OnDC `
  -NodeName $DcComputerName `
  -RunAsCred $DomainCred `
  -Do570 $Run570.IsPresent `
  -Do573 $Run573.IsPresent `
  -Do599 $Run599.IsPresent `
  -Zip570 $RemoteZip570 -Zip573 $RemoteZip573 -Zip599 $RemoteZip599 `
  -Apply570 $RemoteApply570 -Apply573 $RemoteApply573 -Apply599 $RemoteApply599 `
  -Grade570 $Grade570 -Annexes570 $Annexes570 -IncludeIncrementals570 $IncludeIncrementals570.IsPresent `
  -Incrementals570 $Incrementals570 -CreateBaseOUs570 $CreateBaseOUs570.IsPresent -ForceReinstall570 $ForceReinstall570.IsPresent `
  -State570 $State570 `
  -ClientsOuDn570 $ClientsOuDn570 `
  -ServersOuDn570 $ServersOuDn570 `
  -LinkEnabled570 $LinkEnabled570 `
  -Nivel573 $Nivel573 -TargetOuDns573 $TargetOuDns573 -LinkEnabled573 $LinkEnabled573 -ForceReimport573 $ForceReimport573.IsPresent `
  -State573 $State573 `
  -Nivel599 $Nivel599 -TargetOuDns599 $TargetOuDns599 -OnlyGpoNames599 $OnlyGpoNames599 -LinkEnabled599 $LinkEnabled599 -ForceReimport599 $ForceReimport599.IsPresent `
  -State599 $State599 `
  -OutputPath $Out `
  -ConfigurationData $ConfigData

Write-Host ">> [DSC] PUSH a $DcComputerName..." -ForegroundColor Cyan
Start-DscConfiguration -Path $Out -ComputerName $DcComputerName -Credential $DomainCred -Wait -Force -Verbose

Write-Host ">> [DSC] OK." -ForegroundColor Green

# -----------------------------
# 3) Post-check opcional (listar GPOs + links)
# -----------------------------
if ($PostCheck) {
  Write-Host ">> [CHECK] Listando GPOs/links..." -ForegroundColor Cyan
  Invoke-Command -ComputerName $DcComputerName -Credential $DomainCred -ScriptBlock {
    Import-Module GroupPolicy

    "---- TOP: GPOs CCN (filtrado por 'CCN' en el nombre) ----"
    Get-GPO -All | Where-Object { $_.DisplayName -match 'CCN' } | Select-Object DisplayName | Sort-Object DisplayName

    "---- Links OU Domain Controllers ----"
    $d = (Get-ADDomain).DistinguishedName
    $dcOu = "OU=Domain Controllers,$d"
    (Get-GPInheritance -Target $dcOu).GpoLinks | Select-Object DisplayName,Enabled,Enforced

  } | Out-Host
}
