
# Detecta el CD con el TAG
$cd = (Get-Volume | Where-Object DriveType -eq 'CD-ROM' | ForEach-Object { $_.DriveLetter + ':\' } |
       Where-Object { Test-Path (Join-Path $_ 'AUTOUNATTEND.TAG') }) | Select-Object -First 1
if (-not $cd) { $cd = 'D:\' }  # fallback, no falla :)


# Función para copiar módulos DSC desde la ISO a la ruta de módulos del sistema
function Copy-DscModuleFromMedia {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$MediaModulesRoot,   # D:\files\modules

        [string]$SystemModulesRoot = 'C:\Program Files\WindowsPowerShell\Modules'
    )

    $src = Join-Path $MediaModulesRoot $ModuleName
    if (-not (Test-Path $src)) {
        Write-Host "ADVERTENCIA: No se encontró $src. No se copia $ModuleName."
        return
    }

    $dst = Join-Path $SystemModulesRoot $ModuleName
    New-Item -Path $dst -ItemType Directory -Force | Out-Null

    Write-Host "Copiando módulo $ModuleName desde $src a $dst"
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force

    # Verificación
    $mod = Get-Module -ListAvailable $ModuleName
    if ($mod) {
        $top = $mod | Sort-Object Version -Descending | Select-Object -First 1
        Write-Host "$ModuleName OK. Versión visible: $($top.Version)"
    } else {
        Write-Host "ADVERTENCIA: $ModuleName no aparece en Get-Module -ListAvailable."
    }
}


# Copiar módulos DSC a la ruta de módulos del sistema
$mediaModules = Join-Path $cd 'files\modules'

Copy-DscModuleFromMedia -ModuleName 'PackageManagement'  -MediaModulesRoot $mediaModules # No es necesario si copiamos los modulos desde la ISO
Copy-DscModuleFromMedia -ModuleName 'PowerShellGet'      -MediaModulesRoot $mediaModules # solo son necesarios para instalar desde PSGallery (install-module/save-module)
Copy-DscModuleFromMedia -ModuleName 'NetworkingDsc'      -MediaModulesRoot $mediaModules
Copy-DscModuleFromMedia -ModuleName 'ActiveDirectoryDsc' -MediaModulesRoot $mediaModules
Copy-DscModuleFromMedia -ModuleName 'DnsServerDsc'       -MediaModulesRoot $mediaModules
Copy-DscModuleFromMedia -ModuleName 'ComputerManagementDsc'       -MediaModulesRoot $mediaModules
Copy-DscModuleFromMedia -ModuleName 'PSWindowsUpdate'       -MediaModulesRoot $mediaModules

# ConfiguraciOn de red estatica + PING(ICMP) 
$ipAddress  = "192.168.137.10"   # IP VM
$prefixLen  = 24                 # /24 = 255.255.255.0
$gateway    = "192.168.137.1"    # Win10 host
$dnsServers = @("8.8.8.8")       

# Cogemos el primer adaptador de red "normal" que este activo/levantado
$nic = Get-NetAdapter |
    Where-Object { $_.Status -eq "Up" -and -not $_.Virtual } |
    Select-Object -First 1

if ($nic) {

    # Limpia posibles IPs anteriores (DHCP/APIPA)
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    Get-NetRoute -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # IP estatica + gateway
    New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $ipAddress `
        -PrefixLength $prefixLen -DefaultGateway $gateway

    # DNS
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $dnsServers

    # Permitir ping
    New-NetFirewallRule -DisplayName "Allow ICMPv4 In" -Protocol ICMPv4 `
        -Direction Inbound -Action Allow -ErrorAction SilentlyContinue
}



# WinRM + Remoting 
winrm quickconfig -q      # Configura WinRM
Enable-PSRemoting -Force  # Habilita PowerShell Remoting
try { Set-ExecutionPolicy Bypass -Scope Process -Force } catch {}
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in action=allow protocol=TCP localport=5985 # WinRM HTTP firewall rule 
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force # Permite todos los hosts en TrustedHosts (LAB)



# OpenSSH Server
# Habilitamos SSH Server (característica opcional de Windows)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic

#Añadimos regla de firewall para permitir conexiones SSH entrantes (puerto 22 TCP)
netsh advfirewall firewall add rule name="OpenSSH-Server-In-TCP" dir=in action=allow protocol=TCP localport=22



# Instala Cloudbase-Init 
$log = "C:\Setup-CloudInit.log"
"=== Setup.ps1 CloudInit $(Get-Date) ===" | Out-File $log -Append -Encoding utf8

$dstUnattendDir = "C:\Windows\Panther\Unattend"
$dstUnattend    = Join-Path $dstUnattendDir "unattend.xml"

$dstCbConfDir   = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf"
$dstCbUnattConf = Join-Path $dstCbConfDir "cloudbase-init-unattend.conf"

$cbMsi = Join-Path $cd 'files\cloudbase-init\CloudbaseInitSetup_1_1_6_x64.msi'

# Instala Cloudbase-Init desde el MSI incluido en la ISO
# Define el fichero cloudbase-init.conf (misma configuración que en la ISO)
if (Test-Path $cbMsi) {
  Start-Process msiexec.exe -ArgumentList "/i `"$cbMsi`" /qn /norestart /l*v C:\cloudbase-init.log" -Wait
  # Config minima para Cloudbase-Init
  # inject_user_password=true:  importante para que se inyecte la contraseña del usuario en el primer arranque (si se usa unattend.xml con usuario/contraseña)
  # first_logon_behaviour=no:   evita que Cloudbase-Init ejecute tareas adicionales en el primer inicio de sesión (ya que se usará unattend.xml para eso)
  # allow_reboot=true y stop_service_on_exit=true permiten que Cloudbase-Init reinicie el sistema si es necesario (por ejemplo, para aplicar la contraseña del usuario) 
  # y que se detenga después de completar su tarea, evitando que se quede ejecutándose innecesariamente en segundo plano
  $cfg = @"
[DEFAULT]
username=Administrador
groups=Administradores
netbios_host_name_compatibility=true
inject_user_password=true
first_logon_behaviour=no
config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
verbose=true
debug=true
log_dir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
log_file=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=COM1,115200,N,8
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
check_latest_version=false
allow_reboot=true
stop_service_on_exit=true
"@
  $cfgPath = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf'
  $cfg | Out-File -FilePath $cfgPath -Encoding ascii -Force
  Set-Service -Name cloudbase-init -StartupType Manual
  Start-Service cloudbase-init
}

# Copiar Unattend.xml desde ISO
New-Item -ItemType Directory -Force $dstUnattendDir | Out-Null
"Creada/confirmada carpeta: $dstUnattendDir" | Out-File $log -Append -Encoding utf8

$srcUnattend = Join-Path $cd "files\cloudbase-init\unattend.xml"
if (Test-Path $srcUnattend) {
  Copy-Item -Path $srcUnattend -Destination $dstUnattend -Force
  "Copiado unattend.xml -> $dstUnattend" | Out-File $log -Append -Encoding utf8
} else {
  "WARNING: No se encontró $srcUnattend" | Out-File $log -Append -Encoding utf8
}
# Copiar cloudbase-init-unattend.conf desde ISO 
$srcCbUnattConf = Join-Path $cd "files\cloudbase-init\cloudbase-init-unattend.conf"
if (Test-Path $srcCbUnattConf) {
  Copy-Item -Path $srcCbUnattConf -Destination $dstCbUnattConf -Force
  "Copiado cloudbase-init-unattend.conf -> $dstCbUnattConf" | Out-File $log -Append -Encoding utf8
} else {
    "WARNING: No se encontró $srcCbUnattConf (no se copió cloudbase-init-unattend.conf)" | Out-File $log -Append -Encoding utf8
}


# QEMU Guest Agent 
$gaMsi = Join-Path $cd 'files\qemu-guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $gaMsi) {
  Start-Process msiexec.exe -ArgumentList "/i `"$gaMsi`" /qn /norestart /l*v C:\qemu-ga.log" -Wait

  # Asegurar servicio habilitado y arrancado
  $svcName = "QEMU-GA"
  try {
    Set-Service -Name $svcName -StartupType Automatic -ErrorAction Stop
    Start-Service -Name $svcName -ErrorAction Stop
  } catch {
    # fallback: algunos builds usan nombre distinto
    $s = Get-Service | Where-Object { $_.Name -match "qemu" -or $_.DisplayName -match "QEMU" } | Select-Object -First 1
    if ($s) {
      Set-Service -Name $s.Name -StartupType Automatic
      Start-Service -Name $s.Name
      $svcName = $s.Name
    }
  }

  # Verificación
  (Get-Service -Name $svcName | Select-Object Name,Status,StartType) |
    Out-File C:\qemu-ga-status.txt -Encoding utf8
} else {
  "WARNING: No se encontró $gaMsi. No se instaló QEMU Guest Agent." | Out-File $log -Append -Encoding utf8
}



# Instala drivers VirtIO con pnputil
$drvRoot = Join-Path $cd 'files\drivers\virtio'
$dirs = @(
  'NetKVM\2k25\amd64',  # red
  'vioscsi\2k25\amd64'  # disco SCSI 
)
foreach ($d in $dirs) {
  $path = Join-Path $drvRoot $d
  if (Test-Path $path) {
    Write-Host "Instalando drivers en $path"
    pnputil /add-driver "$path\*.inf" /subdirs /install | Out-Null
  }
}



# Configura LCM (DSC) en Push (para estado final, autocorreccion: ApplyAndAutoCorrect)
[DSCLocalConfigurationManager()]
configuration LCMConfig {
  Node localhost {
    Settings {
      RefreshMode = 'Push'
      ConfigurationMode = 'ApplyOnly'
      ConfigurationModeFrequencyMins = 15
      RebootNodeIfNeeded = $true
    }
  }
}
New-Item -Path C:\dsc\meta -ItemType Directory -Force | Out-Null
LCMConfig -OutputPath C:\dsc\meta
Set-DscLocalConfigurationManager -Path C:\dsc\meta -Force


# Copiar script de Windows Update desde la ISO a disco local 
$provRoot = 'C:\Provisioning'
New-Item -Path $provRoot -ItemType Directory -Force | Out-Null

$srcWuScript = Join-Path $cd 'files\update\Invoke-WindowsUpdate.ps1'
$dstWuScript = Join-Path $provRoot 'Invoke-WindowsUpdate.ps1'

if (Test-Path $srcWuScript) {
  Copy-Item -Path $srcWuScript -Destination $dstWuScript -Force
  "Copiado Invoke-WindowsUpdate.ps1 -> $dstWuScript" | Out-File $log -Append -Encoding utf8
} else {
  "WARNING: No se encontró $srcWuScript" | Out-File $log -Append -Encoding utf8
}
