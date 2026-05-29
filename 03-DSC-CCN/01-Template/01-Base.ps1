param(
  [Parameter(Mandatory=$true)][string]$Server
)

# =========================
# CREDENCIALES (por simplicidad, solo LAB :) ) 
# =========================
$Credential = New-Object pscredential(
  ".\Administrador",
  (ConvertTo-SecureString "Tfgprox25!" -AsPlainText -Force)
)

# =========================
# WINRM CLIENTE + TRUSTEDHOSTS
# =========================
Write-Host ">> Preparando WinRM del cliente y TrustedHosts..." -ForegroundColor Cyan
try { Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Stop } catch {}

$cur = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
if ([string]::IsNullOrWhiteSpace($cur)) {
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value $Server -Force
} elseif ($cur -notmatch [regex]::Escape($Server)) {
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$cur,$Server" -Force
}

if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) {
  throw "No hay ping a $Server. Revisa red/firewall."
}
try { Test-WSMan $Server | Out-Null } catch { throw "WinRM no responde en $Server (5985)." }


# DSC BASE + COPIA SCRIPT WU + TASK
Write-Host ">> Definiendo DSC base..." -ForegroundColor Cyan

Configuration ServidorBaseUpdate {
  param([string]$NodeName)

  Import-DscResource -ModuleName PSDesiredStateConfiguration

  Node $NodeName {

    File ProvisioningRoot {
      Ensure          = 'Present'
      Type            = 'Directory'
      DestinationPath = 'C:\Provisioning'
    }

    File ProvisioningLogs {
      Ensure          = 'Present'
      Type            = 'Directory'
      DestinationPath = 'C:\Provisioning\Logs'
      DependsOn       = '[File]ProvisioningRoot'
    }

    # Aseguramos que WinRM está activo:
    Service WinRMService {
      Name        = "WinRM"
      StartupType = "Automatic"
      State       = "Running"
    }

    # Aseguramos que el firewall permite RDP y WinRM:
    Script EnableRDPFirewall {
      SetScript = {
        Get-NetFirewallRule -Name "RemoteDesktop-*" -ErrorAction SilentlyContinue |
          Enable-NetFirewallRule
      }
      TestScript = {
        $r = Get-NetFirewallRule -Name "RemoteDesktop-*" -ErrorAction SilentlyContinue
        if (-not $r) { return $false }
        return (($r | Where-Object { $_.Enabled -eq 'False' } | Measure-Object).Count -eq 0)
      }
      GetScript = { @{ Result = "RDP rules state" } }
      DependsOn = "[Service]WinRMService"
    }

    Script EnableWinRMFirewall {
      SetScript = {
        Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP*" -ErrorAction SilentlyContinue |
          Enable-NetFirewallRule
      }
      TestScript = {
        $r = Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP*" -ErrorAction SilentlyContinue
        if (-not $r) { return $false }
        return (($r | Where-Object { $_.Enabled -eq 'False' } | Measure-Object).Count -eq 0)
      }
      GetScript = { @{ Result = "WinRM rules state" } }
      DependsOn = "[Service]WinRMService"
    }

    # Copiamos el script de Windows Update desde la ISO montada a la VM, para luego lanzarlo desde una Scheduled Task. 
    #Esto lo hacemos fuera de DSC porque el proceso de Windows Update es un poco "especial" y puede requerir reinicios, lo que complica su manejo directo desde DSC.
    Script CopyWindowsUpdateScript {
      GetScript = { @{ Result = 'CopyWindowsUpdateScript' } }

      TestScript = {
        Test-Path 'C:\Provisioning\Invoke-WindowsUpdate.ps1'
      }

      SetScript = {
        $ErrorActionPreference = 'Stop'

        $provRoot = 'C:\Provisioning'
        $dst = Join-Path $provRoot 'Invoke-WindowsUpdate.ps1'
        $tag = 'AUTOUNATTEND.TAG'

        $cd = (Get-Volume | Where-Object DriveType -eq 'CD-ROM' |
          ForEach-Object { $_.DriveLetter + ':\' } |
          Where-Object { Test-Path (Join-Path $_ $tag) } |
          Select-Object -First 1)

        if (-not $cd) { $cd = 'D:\' }

        $src = Join-Path $cd 'files\scripts\Invoke-WindowsUpdate.ps1'
        if (-not (Test-Path $src)) {
          throw "No se encontró el script de Windows Update en $src"
        }

        Copy-Item -Path $src -Destination $dst -Force
      }

      DependsOn = "[File]ProvisioningRoot"
    }

    # Registramos una Scheduled Task que ejecute el script de Windows Update al inicio. 
    Script RegisterWindowsUpdateTask {
      GetScript = { @{ Result = 'RegisterWindowsUpdateTask' } }

      TestScript = {
        try {
          $t = Get-ScheduledTask -TaskName 'TFG-Invoke-WindowsUpdate' -ErrorAction Stop
          return ($null -ne $t)
        } catch {
          return $false
        }
      }

      SetScript = {
        $ErrorActionPreference = 'Stop'

        $taskName = 'TFG-Invoke-WindowsUpdate'
        $script   = 'C:\Provisioning\Invoke-WindowsUpdate.ps1'
        $logPath  = 'C:\Provisioning\Logs\Invoke-WindowsUpdate-launch.log'

        if (-not (Test-Path $script)) {
          throw "No existe $script"
        }

        $action = New-ScheduledTaskAction `
          -Execute 'PowerShell.exe' `
          -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" *> `"$logPath`""

        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

        try {
          Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}

        Register-ScheduledTask `
          -TaskName $taskName `
          -Action $action `
          -Trigger $trigger `
          -Principal $principal `
          -Description 'Ejecuta Windows Update para preparar la template'
      }

      DependsOn = "[Script]CopyWindowsUpdateScript"
    }
  }
}

$NodeId = $Server

$ConfigData = @{
  AllNodes = @(
    @{
      NodeName                    = $NodeId
      PSDscAllowPlainTextPassword = $true
    }
  )
}


$Out = Join-Path $PSScriptRoot "OUT-01-BASE"
if (Test-Path $Out) {
  Remove-Item "$Out\*" -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $Out | Out-Null
}

# Compilamos la configuración DSC:
Write-Host ">> Compilando MOF..." -ForegroundColor Cyan
ServidorBaseUpdate -NodeName $NodeId `
  -ConfigurationData $ConfigData `
  -OutputPath $Out

# Aplicamos la configuración DSC a la VM con Start-DscConfiguration, usando las credenciales de administrador para la conexión remota:
# -Path apunta a la carpeta donde se generó el MOF, 
# -ComputerName es el servidor destino, 
# -Credential son las credenciales para la conexión remota, 
# -Force fuerza la aplicación incluso si ya hay una configuración aplicada,
# -Wait hace que el comando espere hasta que la configuración se aplique completamente, 
# -Verbose muestra información detallada del proceso.
Write-Host ">> Aplicando DSC a $Server..." -ForegroundColor Cyan
Start-DscConfiguration -Path $Out -ComputerName $Server -Credential $Credential -Force -Wait -Verbose

# ===================================
# LANZAR WINDOWS UPDATE FUERA DE DSC
# ==================================
Write-Host ">> Lanzando Scheduled Task de Windows Update..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $Credential -ScriptBlock {
  $taskName = 'TFG-Invoke-WindowsUpdate'

  Remove-Item 'C:\Provisioning\WindowsUpdate.done' -Force -ErrorAction SilentlyContinue
  Remove-Item 'C:\Provisioning\WindowsUpdate.failed' -Force -ErrorAction SilentlyContinue

  Start-ScheduledTask -TaskName $taskName
}

# =========================
# ESPERAR FIN
# =========================
Write-Host ">> Esperando a que termine Windows Update..." -ForegroundColor Cyan

while ($true) {
  try {
    $status = Invoke-Command -ComputerName $Server -Credential $Credential -ScriptBlock {
      [pscustomobject]@{
        Done   = Test-Path 'C:\Provisioning\WindowsUpdate.done'
        Failed = Test-Path 'C:\Provisioning\WindowsUpdate.failed'
      }
    }

    if ($status.Failed) {
      throw "Windows Update marcó error. Revisa C:\Provisioning\Logs en la VM."
    }

    if ($status.Done) {
      break
    }
  } catch {
    # durante reinicios de updates
  }

  Start-Sleep -Seconds 15
}

# =========================
# VERIFICACIÓN POST
# =========================
Write-Host ">> Verificando estado final..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $Credential -ScriptBlock {
  [pscustomobject]@{
    DSC_OK_Existe = Test-Path 'C:\DSC-DEMO\DSC_OK.txt'
    ScriptWU      = Test-Path 'C:\Provisioning\Invoke-WindowsUpdate.ps1'
    WUDone        = Test-Path 'C:\Provisioning\WindowsUpdate.done'
    LastHotFixes  = (
      Get-HotFix |
      Sort-Object InstalledOn -Descending |
      Select-Object -First 5 HotFixID, InstalledOn |
      Format-Table -AutoSize | Out-String
    ).Trim()
  }
} | Format-List

Write-Host ">> FIN Script 01. Si todo está correcto, ya puedes pasar a sysprep." -ForegroundColor Cyan