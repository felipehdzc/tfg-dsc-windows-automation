param(
  [Parameter(Mandatory=$true)][string]$Server                 # IP o nombre del WS2025
  #[Parameter(Mandatory=$true)][pscredential]$Credential,       # Credenciales admin del WS2019
  #[Parameter(Mandatory=$true)][pscredential]$AdminUserCred,    # Credenciales del usuario "admin" a crear
  #[Parameter(Mandatory=$true)][pscredential]$NormalUserCred    # Credenciales del usuario "normal" a crear
)

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

function Wait-RebootOccurred {
  param(
    [string]$ComputerName,
    [pscredential]$Credential,
    [datetime]$BootBefore,
    [int]$TimeoutSec = 900
  )
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $bootNow = Get-LastBoot -ComputerName $ComputerName -Credential $Credential
      if ($bootNow -gt $BootBefore) { return $bootNow }
    } catch {}
    Start-Sleep -Seconds 5
  }
  throw "Timeout esperando reinicio (LastBootUpTime no cambió) en $ComputerName"
}


function Wait-Reboots {
  param(
    [string]$ComputerName,
    [pscredential]$Credential,
    [int]$RebootCount = 1,
    [int]$TimeoutSec = 2000
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
  param(
    [string]$ComputerName,
    [pscredential]$Credential,
    [int]$TimeoutSec = 1800,
    [int]$PollSec = 5,
    [switch]$ShowProgress
  )

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $lastState = $null

  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $state = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
        $lcm = Get-DscLocalConfigurationManager

        if ($lcm.LCMState -ne 'Idle') {
          return 'BUSY'
        }

        try {
          $status = (Get-DscConfigurationStatus).Status
          if ([string]::IsNullOrWhiteSpace($status)) {
            return 'IDLE_NO_STATUS'
          }
          return [string]$status
        }
        catch {
          return 'IDLE_NO_STATUS'
        }
      }

      $state = [string]($state | Select-Object -Last 1)
      $state = $state.Trim()

      if ($ShowProgress -and $state -ne $lastState) {
        Write-Host "[$ComputerName] Estado DSC: $state"
      }

      $lastState = $state

      if ($state -in @('Success', 'Failure')) {
        return $state
      }
    }
    catch {
      if ($ShowProgress) {
        Write-Host "[$ComputerName] Error consultando DSC: $($_.Exception.Message)"
      }
    }

    Start-Sleep -Seconds $PollSec
  }

  return "Unknown/Timeout"
}


# ---- OPCIÓN RECOMENDADA PARA PRUEBAS INTERACTIVAS ----
# $Credential     = Get-Credential -Message "Credenciales admin del servidor ($Server)"

# ---- OPCIÓN PARA PRUEBAS RÁPIDAS EN LAB - NO PRODUCCIÓN----
$Credential = New-Object pscredential(
  "Administrador",
  (ConvertTo-SecureString "CLI_local!2026" -AsPlainText -Force)
)

$DomainName    = "ad.umtfg.com"
#$DomainNetbios = "ADTFG"
$JoinOU = "OU=EstacionesWS25,OU=Clientes,DC=ad,DC=umtfg,DC=com"

# Credencial de JOIN (dominio) - ENTRAMOS CON NUEVO ADMIN DE DOMNIO
$DomainJoinCredential = New-Object pscredential(
  "BG_DC_Domain@$DomainName",
  (ConvertTo-SecureString "BG_Admin!2026" -AsPlainText -Force)
)


# NEW LOCAL ADMIN
# Cuentas Break-Glass (BG) para emergencias: local 
$BGAdminLocalName = "BG_CLI_local"
# Password del BG local. Ideal: rotarla luego.
$BGAdminLocalPwd = "Admin_CLI!2026"


# WinRM + TrustedHosts 
# =========================
try { Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Stop } catch {}

$cur = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
if ([string]::IsNullOrWhiteSpace($cur)) {
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value $Server -Force
} elseif ($cur -notmatch [regex]::Escape($Server)) {
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$cur,$Server" -Force
}

if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) { throw "No hay ping a $Server" }
try { Test-WSMan $Server -ErrorAction Stop | Out-Null } catch { throw "WinRM no responde en $Server (5985/wsman)" }

# Detectar NIC Up
$Interface = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop -ScriptBlock {
  (Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object ifIndex | Select-Object -First 1 -ExpandProperty Name)
}
if (-not $Interface) { throw "No se encontró NIC Up en el remoto" }



# PARÁMETROS DE RED 
$CliIp      = "192.168.137.12/24"   # IP estática NUEVA del cliente
$Gateway    = "192.168.137.1"       # IP del router
$DnsServers = @("192.168.137.10")   # IP del ADDC


# Obtener nombre actual del servidor remoto
$CliName = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop -ScriptBlock {
  $env:COMPUTERNAME
}

Write-Host ">> Nombre actual de la VM: $CliName" -ForegroundColor Cyan

$Out = Join-Path $PSScriptRoot "CLI-Base-Out"


# ============================================================
# CONFIGURACIÓN DSC
# ============================================================
Write-Host ">> Definiendo configuración DSC (ClientBase)..." -ForegroundColor Cyan
Configuration ClientBase {
  param(
    [parameter(Mandatory)][string]        $NodeName,
    [parameter(Mandatory)][string]        $ComputerName,
    [parameter(Mandatory)][string]        $DomainName,
    [parameter(Mandatory)][string]        $JoinOU,
    [parameter(Mandatory)][pscredential]  $DomainJoinCredential, 
    [parameter(Mandatory)][string]        $InterfaceAlias,
    [parameter(Mandatory)][string]        $IpCidr,
    [parameter(Mandatory)][string]        $Gateway,
    [parameter(Mandatory)][string[]]      $DnsServers,
    [Parameter(Mandatory)][string]        $BGAdminLocalName,
    [Parameter(Mandatory)][string]        $BGAdminLocalPwd
  )

  Import-DscResource -ModuleName NetworkingDsc
  Import-DscResource -ModuleName ComputerManagementDsc
  Import-DscResource -ModuleName PSDesiredStateConfiguration
  
  Node $NodeName {

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

    
    # Asegura WinRM arrancado
    Service WinRMService {
      Name        = "WinRM"
      StartupType = "Automatic"
      State       = "Running"
      DependsOn      = "[Script]MgmtBaseline_WinRMFirewall"
    }

    NetAdapterBinding DisableIPv6 {
        InterfaceAlias = $InterfaceAlias
        ComponentId    = 'ms_tcpip6'
        State          = 'Disabled'
        DependsOn      = "[Service]WinRMService"
    }

    # Asegura que la NIC registra su IP en DNS
    Script EnsureDnsRegistrationEnabled {
        SetScript = {
            Set-DnsClient -InterfaceAlias $using:InterfaceAlias `
            -RegisterThisConnectionsAddress $true `
            -UseSuffixWhenRegistering $true `
            -ConnectionSpecificSuffix $using:DomainName -ErrorAction Stop
        }
        TestScript = {
            $c = Get-DnsClient -InterfaceAlias $using:InterfaceAlias -ErrorAction Stop
            ($c.RegisterThisConnectionsAddress -eq $true) -and
            ($c.UseSuffixWhenRegistering -eq $true) -and
            ($c.ConnectionSpecificSuffix -eq $using:DomainName)
        }
        GetScript = { @{ Result = "DNS registration flags OK" } }
        DependsOn = "[NetAdapterBinding]DisableIPv6"
    }

    # Espera a que el DC responda por SRV desde ESTE servidor
    Script WaitForDomainDns {
        SetScript  = {
            $name = "_ldap._tcp.dc._msdcs.$using:DomainName"
            $dns  = ($using:DnsServers | Select-Object -First 1)
            $deadline = (Get-Date).AddMinutes(5)

            while ((Get-Date) -lt $deadline) {
            try {
                $srv = Resolve-DnsName -Name $name -Type SRV -Server $dns -ErrorAction Stop
                if ($srv) { return }
            } catch {}
            Start-Sleep -Seconds 5
            }
            throw "Timeout esperando SRV: $name (DNS $dns)"
        }

        TestScript = {
            try {
            $name = "_ldap._tcp.dc._msdcs.$using:DomainName"
            $dns  = ($using:DnsServers | Select-Object -First 1)
            $srv  = Resolve-DnsName -Name $name -Type SRV -Server $dns -ErrorAction Stop
            return [bool]$srv
            } catch { return $false }
        }

        GetScript  = { @{ Result = "Domain SRV OK" } }
        DependsOn  = "[Script]EnsureDnsRegistrationEnabled"
    }


    # --- JoinDomain  ---
    Computer JoinDomain {
      Name       = $ComputerName
      DomainName = $DomainName
      Credential = $DomainJoinCredential
      JoinOU     = $JoinOU
      DependsOn  = @("[Script]WaitForDomainDns")
    }

    Script WaitForSecureChannel {
        TestScript = {
            cmd /c "nltest /sc_query:$using:DomainName >nul 2>&1"
            ($LASTEXITCODE -eq 0)
        }
        SetScript = {
            $deadline = (Get-Date).AddMinutes(5)
            while ((Get-Date) -lt $deadline) {
            cmd /c "nltest /sc_query:$using:DomainName >nul 2>&1"
            if ($LASTEXITCODE -eq 0) { return }
            Start-Sleep -Seconds 5
            }
            throw "Timeout esperando secure channel con $using:DomainName"
        }
        GetScript = {
            $out = cmd /c "nltest /sc_query:$using:DomainName 2>&1"
            @{ Result = ($out -join "`n") }
        }

        DependsOn = "[Computer]JoinDomain"
    }


    # Asegura que el grupo ADTFG\GG_WS25_LocalAdmins es miembro de los Administradores locales (para emergencias)
    Script GG_WS25_LocalAdmins_in_LocalAdministrators {
      GetScript = {
        @{ Result = "Ensure ADTFG\\GG_WS25_LocalAdmins in local Administradores" }
      }

      TestScript = {
        $member = Get-LocalGroupMember -Group "Administradores" -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -eq "ADTFG\GG_WS25_LocalAdmins" }
        return [bool]$member
      }

      SetScript = {
        Add-LocalGroupMember -Group "Administradores" -Member "ADTFG\GG_WS25_LocalAdmins" -ErrorAction Stop
      }

      DependsOn = @(
        "[Computer]JoinDomain"
      )
    }

    Script EnsureWinRMAfterJoin {
        GetScript = {
            @{ Result = "Ensure WinRM after network/join" }
        }

        TestScript = {
            try {
                $svcOk = (Get-Service WinRM -ErrorAction Stop).Status -eq 'Running'

                $listenerText = (winrm enumerate winrm/config/listener 2>$null | Out-String)
                $listenerOk = $listenerText -match 'Transport = HTTP'

                $rules = Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue
                $fwOk = $rules -and (($rules | Where-Object Enabled -eq 'False').Count -eq 0)

                return ($svcOk -and $listenerOk -and $fwOk)
            }
            catch {
                return $false
            }
        }

        SetScript = {
            Set-Service -Name WinRM -StartupType Automatic
            Start-Service -Name WinRM

            try {
                $profile = (Get-NetConnectionProfile -InterfaceAlias $using:InterfaceAlias -ErrorAction Stop).NetworkCategory
                if ($profile -eq 'Public') {
                    Set-NetConnectionProfile -InterfaceAlias $using:InterfaceAlias -NetworkCategory Private -ErrorAction Stop
                }
            } catch {}

            Enable-PSRemoting -SkipNetworkProfileCheck -Force

            Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue |
                Enable-NetFirewallRule
        }

        DependsOn = "[Computer]JoinDomain"
    }
  }
}


# Permitir contraseña en claro en el .mof (SOLO LABORATORIO)
$ConfigData = @{
  AllNodes = @(
    @{
      NodeName                    = $Server
      PSDscAllowPlainTextPassword = $true
      PSDscAllowDomainUser        = $true
    }
  )
}

# Compilar configuración
if (Test-Path $Out) {
  Remove-Item "$Out\*" -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $Out | Out-Null
}

Write-Host ">> Compilando configuración para nodo $Server..." -ForegroundColor Cyan

ClientBase -NodeName $Server `
  -InterfaceAlias $Interface `
  -IpCidr $CliIp `
  -Gateway $Gateway `
  -DnsServers $DnsServers `
  -ComputerName $CliName `
  -DomainName $DomainName `
  -JoinOU $JoinOU `
  -DomainJoinCredential $DomainJoinCredential `
  -BGAdminLocalName $BGAdminLocalName `
  -BGAdminLocalPwd $BGAdminLocalPwd `
  -OutputPath $Out `
  -ConfigurationData $ConfigData


# Aplicar al servidor remoto
Write-Host ">> Aplicando configuración a $Server..." -ForegroundColor Cyan

#$boot0 = Get-LastBoot -ComputerName $Server -Credential $Credential

Start-DscConfiguration -Path $Out -ComputerName $Server -Credential $Credential -Force -Verbose -Wait

#Write-Host ">> Esperando reinicio del nodo..." -ForegroundColor Cyan
#$boot1 = Wait-RebootOccurred -ComputerName $Server -Credential $Credential -BootBefore $boot0 -TimeoutSec 1200

#Write-Host ">> Esperando WinRM tras reinicio..." -ForegroundColor Cyan
#Wait-WinRM -ComputerName $Server -Credential $Credential -TimeoutSec 1200

# Incluye Wait-WinRM para asegurar que el nodo está operativo antes de intentar aplicar la siguiente configuración (AD-Objects)
Write-Host ">> Reiniciando el nodo..." -ForegroundColor Cyan
Wait-Reboots -ComputerName $Server -Credential $Credential -RebootCount 1 -TimeoutSec 1800 | Out-Null


Write-Host ">> Esperando fin de DSC..." -ForegroundColor Cyan
$dscFinal = Wait-DscFinal -ComputerName $Server -Credential $Credential -TimeoutSec 1800 -ShowProgress
Write-Host "   DSC final: $dscFinal" -ForegroundColor Cyan

Write-Host ">> Check final (nombre + dominio)..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $Credential -ScriptBlock {
  $cs = Get-CimInstance Win32_ComputerSystem
  [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    PartOfDomain = $cs.PartOfDomain
    Domain       = $cs.Domain
  }
} | Format-List


Write-Host ">> FIN DEL SCRIPT." -ForegroundColor Cyan