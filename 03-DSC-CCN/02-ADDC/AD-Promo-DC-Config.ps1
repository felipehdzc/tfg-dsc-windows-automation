param(
  [Parameter(Mandatory=$true)]
  [string]$Server
)

# Funciones de espera para reinicios y estado de DSC. 
# Se usan tras Start-DscConfiguration para esperar a que el nodo se reinicie 
# y quede operativo antes de aplicar la siguiente configuración (AD-Objects) o hacer comprobaciones finales.
function Get-LastBoot {
  param([string]$ComputerName, [pscredential]$Credential)
  Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
    (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  }
}

function Wait-WinRM {
  param([string]$ComputerName, [pscredential]$Credential, [int]$TimeoutSec = 900)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
      return $true
    } catch {}
    Start-Sleep -Seconds 5
  }
  throw "Timeout esperando WinRM en $ComputerName"
}

function Wait-Reboots {
  param(
    [string]$ComputerName,
    [pscredential]$Credential,
    [int]$RebootCount = 2,
    [int]$TimeoutSec = 2400
  )

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $boots = @()

  # boot inicial
  $last = Get-LastBoot -ComputerName $ComputerName -Credential $Credential
  $boots += $last

  $seen = 0
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec -and $seen -lt $RebootCount) {

    # Espera a que caiga (WinRM no responda) y vuelva
    try { Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock { 1 } -ErrorAction Stop | Out-Null }
    catch { } # si cae, bien

    # Espera a que vuelva WinRM
    Wait-WinRM -ComputerName $ComputerName -Credential $Credential -TimeoutSec 1200

    # Comprueba nuevo boot
    $now = Get-LastBoot -ComputerName $ComputerName -Credential $Credential
    if ($now -gt $last) {
      $seen++
      $last = $now
      $boots += $now
      Write-Host ">> Detectado reinicio #$seen (LastBootUpTime=$now)" -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 5
  }

  if ($seen -lt $RebootCount) {
    throw "Timeout: solo detecté $seen reinicios (esperaba $RebootCount)."
  }

  return $boots
}

function Wait-DscFinal {
  param([string]$ComputerName, [pscredential]$Credential, [int]$TimeoutSec = 1800)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $lcm = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        Get-DscLocalConfigurationManager | Select-Object LCMState
      } -ErrorAction Stop

      if ($lcm.LCMState -eq 'Idle') {
        $st = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
          (Get-DscConfigurationStatus -All | Select-Object -First 1).Status
        } -ErrorAction Stop

        if ($st -in @('Success','Failure')) { return $st }
      }
    } catch {}
    Start-Sleep -Seconds 10
  }
  return "Unknown/Timeout"
}

function Wait-ADReady {
  param(
    [string]$ComputerName,
    [pscredential]$Credential,
    [string]$DomainFqdn,
    [int]$TimeoutSec = 900,
    [int]$PollSec = 10
  )

  $sw = [Diagnostics.Stopwatch]::StartNew()

  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $ok = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        param($DomainFqdn)

        $adOk = $false
        $sharesOk = $false
        $dnsOk = $false

        try {
          Import-Module ActiveDirectory -ErrorAction Stop
          $null = Get-ADDomain -Identity $DomainFqdn -ErrorAction Stop
          $adOk = $true
        } catch {}

        try {
          $shares = Get-SmbShare -ErrorAction Stop
          $sharesOk = (($shares.Name -contains 'SYSVOL') -and ($shares.Name -contains 'NETLOGON'))
        } catch {}

        try {
          $null = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainFqdn" -Type SRV -ErrorAction Stop
          $dnsOk = $true
        } catch {}

        [pscustomobject]@{
          AD     = $adOk
          Shares = $sharesOk
          DNS    = $dnsOk
          Ready  = ($adOk -and $sharesOk -and $dnsOk)
        }
      } -ArgumentList $DomainFqdn -ErrorAction Stop

      if ($ok.Ready) {
        return $true
      }
    } catch {}

    Start-Sleep -Seconds $PollSec
  }

  return $false
}

# CREDENCIALES Y PARÁMETROS
#############################
$ComputerName = "DC1" # Nombre final esperado del DC (para comprobaciones finales)
# Parámetros de dominio
$DomainName      = "ad.umtfg.com"
$DomainNetbios   = "ADTFG"               
$DcIp            = "192.168.137.10"
$InterfaceAlias  = "Ethernet"
# Forwarders EXTERNOS
$Forwarders = @("8.8.8.8","1.1.1.1")

# TODO FINAL: NO HARDCODEAR, pedirlas por parámetro o usar vault. Solo para LAB.

# NEW LOCAL ADMIN
# Cuentas Break-Glass (BG) para emergencias: local 
$BGAdminLocalName = "BG_DC_local"
# Password del BG local. Ideal: rotarla luego.
$BGAdminLocalPwd = "Admin_DC!2026"

# LOCAL ADMIN (workgroup/predominio): Credenciales para ejecutar DSC remoto 
$LocalAdminCredential = New-Object pscredential(
  "Administrador",
  (ConvertTo-SecureString "DC_local!2026" -AsPlainText -Force)
)

# Credenciales para promoción del DC (se pasan a ADDomain como PSCredential).
# ADTFG\Administrador copia la contraseña local del admin que promociona el DC 
$BootstrapAdminCredential = $LocalAdminCredential

#Utiliza la contraseña de BootstrapAdminCredential
$DomainAdminCredential = New-Object pscredential(
  "$DomainNetbios\Administrador",
  $LocalAdminCredential.Password
)

# Credencial DSRM (Safe Mode). En DSC se pasa como PSCredential. 
$DsrmCredential = New-Object pscredential(
  "DSRM",
  (ConvertTo-SecureString "Dsrmtfg26!" -AsPlainText -Force)
)

# CONFIGURACIÓN DSC
Configuration FirstDomainController {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NodeName,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$DomainNetbios,
    [Parameter(Mandatory)][pscredential]$BootstrapAdminCredential,
    [Parameter(Mandatory)][pscredential]$DsrmCredential,
    [Parameter(Mandatory)][string]$DcIp,
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string[]]$Forwarders,
    [Parameter(Mandatory)][string]$BGAdminLocalName,
    [Parameter(Mandatory)][string]$BGAdminLocalPwd

  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration
  Import-DscResource -ModuleName ActiveDirectoryDsc
  Import-DscResource -ModuleName NetworkingDsc
  Import-DscResource -ModuleName DnsServerDsc

  Node $NodeName {

    Script SetHostname {
        GetScript  = { @{ Result = $env:COMPUTERNAME } }
        TestScript = { $env:COMPUTERNAME -eq $using:ComputerName }
        SetScript  = {
            Rename-Computer -NewName $using:ComputerName -Force
            $global:DSCMachineStatus = 1  # pide reboot a DSC
        }
    }

    # 0) BreakGlass LOCAL + canal de gestión (ANTES del hardening)
    Script BreakGlassLocal {
      GetScript  = { @{ Result = "BreakGlassLocal" } }
      TestScript = {
        try {
          # Para que get-localuser lance excepción si no existe el usuario, y así devolver false sale del test. 
          #Si existe, comprueba si es admin local.
          Get-LocalUser -Name $using:BGAdminLocalName -ErrorAction Stop | Out-Null
          $isAdmin = (Get-LocalGroupMember Administradores -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -match "\\$($using:BGAdminLocalName)$" }).Count -gt 0
          return $isAdmin
        } catch { return $false }
      }
      SetScript  = {
        $pw = ConvertTo-SecureString $using:BGAdminLocalPwd -AsPlainText -Force

        if (-not (Get-LocalUser -Name $using:BGAdminLocalName -ErrorAction SilentlyContinue)) {
          New-LocalUser -Name $using:BGAdminLocalName -Password $pw -PasswordNeverExpires:$true -AccountNeverExpires:$true
        }

        Add-LocalGroupMember -Group "Administradores" -Member $using:BGAdminLocalName -ErrorAction SilentlyContinue
      }
      DependsOn = "[Script]SetHostname"
    }

    Script MgmtBaseline_WinRMFirewall {
      GetScript  = { @{ Result = "WinRM firewall baseline" } }
      TestScript = {
        $r = Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP*" -ErrorAction SilentlyContinue
        if (-not $r) { return $false }
        return (($r | Where-Object Enabled -eq 'False' | Measure-Object).Count -eq 0)
      }
      SetScript  = {
        Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP*" -ErrorAction SilentlyContinue | Enable-NetFirewallRule
      }
      DependsOn = "[Script]BreakGlassLocal"
    }


    # 1) Roles necesarios
    # Active Directory Domain Services Role para el DC
    WindowsFeature ADDS {
      Name   = 'AD-Domain-Services'
      Ensure = 'Present'
    }

    # DNS Server Role para el DC
    WindowsFeature DNS {
      Name   = 'DNS'
      Ensure = 'Present'
    }

    # Remote Server Administration Tools (RSAT) para AD PowerShell
    WindowsFeature RSAT_AD_PS { 
      Name   = 'RSAT-AD-PowerShell'
      Ensure = 'Present'
    }

    # 2) El DC debe apuntar a sí mismo como DNS (cliente TCP/IP)
    # (recomendable antes/durante la promoción)
    DnsServerAddress DnsToSelf {
      Address        = $DcIp
      InterfaceAlias = $InterfaceAlias
      AddressFamily  = 'IPv4'
      DependsOn = @(
        '[Script]SetHostname',
        '[WindowsFeature]ADDS',
        '[WindowsFeature]DNS',
        '[WindowsFeature]RSAT_AD_PS'
      )
    }

    # 3) Crear el nuevo bosque/dominio (primer DC)
    # El primer DC del bosque debe ser GC y la opción viene activada por defecto.
    ADDomain CreateForestRoot {
      DomainName                    = $DomainName
      DomainNetBiosName             = $DomainNetbios
      Credential                    = $BootstrapAdminCredential
      SafemodeAdministratorPassword = $DsrmCredential

      # ActiveDirectoryDsc expone valores hasta WinThreshold (Server 2016) 
      # En Windows Server 2025 el mínimo nuevo es 2016 y luego puedes elevar niveles. 
      ForestMode = 'WinThreshold'
      DomainMode = 'WinThreshold'

      DependsOn = @('[DnsServerAddress]DnsToSelf',
                    '[Script]MgmtBaseline_WinRMFirewall'
      )    
    }

    # 4) Forwarders DNS (para resolución externa)
    DnsServerForwarder ForwardersConfig {
      IsSingleInstance  = 'Yes'
      IPAddresses       = $Forwarders
      UseRootHint       = $true
      EnableReordering  = $false
      DependsOn         = '[ADDomain]CreateForestRoot'
    }

    # GPMC (Group Policy Management) -> necesario para Import-GPO / GroupPolicy module
    WindowsFeature GPMC {
      Name   = 'GPMC'
      Ensure = 'Present'
      DependsOn = '[ADDomain]CreateForestRoot'
    }

  }
}


$ConfigData = @{
  AllNodes = @(
    @{
      NodeName                    = $Server
      # LAB ONLY: permite credenciales en MOF en claro.
      # En producción, cifra credenciales con certificado. (Microsoft desaconseja almacenar contraseñas en claro/obfuscadas).
      PSDscAllowPlainTextPassword = $true
      PSDscAllowDomainUser        = $true
    }
  )
}

# Precalcular reinicios esperados: si el nodo ya se llama DC1, solo habrá 1 reinicio (promoción), si no, habrá 2 (renombrado + promoción).
Write-Host ">> Comprobando nombre inicial del nodo..." -ForegroundColor Cyan
$initialName = Invoke-Command -ComputerName $Server -Credential $LocalAdminCredential -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
$expectedReboots = if ($initialName -eq $ComputerName) { 1 } else { 2 }
Write-Host "   Nombre inicial: $initialName -> reinicios esperados: $expectedReboots" -ForegroundColor Cyan



# --- Compilar y aplicar ---
$Out = "C:\Users\felipe\Desktop\TFG\proyecto\DSC-CCN\ADDC\ADDC-Config-Out"
if (Test-Path $Out) {
  Remove-Item "$Out\*" -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $Out | Out-Null
}

Write-Host ">> Compilando configuración para ADDC --> $Server..." -ForegroundColor Cyan

FirstDomainController -NodeName $Server `
  -ComputerName $ComputerName `
  -DomainName $DomainName `
  -DomainNetbios $DomainNetbios `
  -BootstrapAdminCredential $BootstrapAdminCredential `
  -DsrmCredential $DsrmCredential `
  -DcIp $DcIp `
  -InterfaceAlias $InterfaceAlias `
  -Forwarders $Forwarders `
  -BGAdminLocalName $BGAdminLocalName `
  -BGAdminLocalPwd $BGAdminLocalPwd `
  -ConfigurationData $ConfigData `
  -OutputPath $Out

Write-Host ">> Aplicando configuración al ADDC --> IP: $Server..." -ForegroundColor Cyan

Start-DscConfiguration -Path $Out -ComputerName $Server -Credential $LocalAdminCredential -Force -Verbose -Wait

Write-Host ">> Esperando $expectedReboots reinicios del nodo..." -ForegroundColor Cyan
Wait-Reboots -ComputerName $Server -Credential $LocalAdminCredential -RebootCount $expectedReboots -TimeoutSec 3600 | Out-Null

# Tras la promoción, mejor esperar WinRM usando cred de dominio (más estable)
Write-Host ">> Esperando WinRM con credencial de dominio..." -ForegroundColor Cyan
Wait-WinRM -ComputerName $Server -Credential $DomainAdminCredential -TimeoutSec 1200 | Out-Null

Write-Host ">> Esperando fin de DSC..." -ForegroundColor Cyan
$dscFinal = Wait-ADReady -ComputerName $Server -Credential $DomainAdminCredential -DomainFqdn $DomainName
Write-Host "   DSC final: $dscFinal" -ForegroundColor Cyan

# =========================
# Post-checks (más completo)
# =========================
Write-Host ">> Check final (nombre + dominio)..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $DomainAdminCredential -ScriptBlock {
  $cs = Get-CimInstance Win32_ComputerSystem
  [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    PartOfDomain = $cs.PartOfDomain
    Domain       = $cs.Domain
  }
} | Format-List

Write-Host ">> Check AD/Forest/DC..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $DomainAdminCredential -ScriptBlock {
  Import-Module ActiveDirectory
  $dom = Get-ADDomain
  $for = Get-ADForest
  $dc  = Get-ADDomainController -Identity $env:COMPUTERNAME

  [pscustomobject]@{
    DNSRoot      = $dom.DNSRoot
    DomainMode   = $dom.DomainMode
    ForestMode   = $for.ForestMode
    IsGC         = $dc.IsGlobalCatalog
    Site         = $dc.Site
    OS           = $dc.OperatingSystem
  }
} | Format-List

Write-Host ">> Check DNS Forwarders..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $DomainAdminCredential -ScriptBlock {
  try {
    (Get-DnsServerForwarder).IPAddress | ForEach-Object { $_.ToString() }
  } catch {
    "No se pudo leer forwarders: $($_.Exception.Message)"
  }
} | ForEach-Object { "   $_" }

Write-Host ">> Check shares SYSVOL/NETLOGON..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $DomainAdminCredential -ScriptBlock {
  Get-SmbShare -Name SYSVOL,NETLOGON | Select-Object Name,Path
} | Format-Table -AutoSize

Write-Host ">> FIN DEL SCRIPT." -ForegroundColor Cyan