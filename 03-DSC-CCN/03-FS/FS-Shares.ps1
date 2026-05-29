param(
  [Parameter(Mandatory=$true)][string]$Server  # Se puede pasar "FS2" o la IP 192.168.137.11
)


# --- Dominio / Grupos ---
$DomainName         = "ad.umtfg.com"
$DomainNetbios      = "ADTFG"


$GroupPublicRW      = "GG_FS_PUBLIC_RW"
$GroupPublicRO      = "GG_FS_PUBLIC_RO"
$GroupITDeptoRW     = "GG_FS_IT_RW"
$GroupITDeptoRO     = "GG_FS_IT_RO"
$GroupFINDeptoRW    = "GG_FS_FIN_RW"
$GroupFINDeptoRO    = "GG_FS_FIN_RO"
$GroupRRHHDeptoRW   = "GG_FS_RRHH_RW"
$GroupRRHHDeptoRO   = "GG_FS_RRHH_RO"
$GroupProyADeptoRW  = "GG_FS_PROY_A_RW"
$GroupProyADeptoRO  = "GG_FS_PROY_A_RO"
$GroupProyBDeptoRW  = "GG_FS_PROY_B_RW"
$GroupProyBDeptoRO  = "GG_FS_PROY_B_RO"
$GroupHomesCreate   = "GG_FS_HOMES_CREATE" 


# --- Datos ---
$DataDriveLetter    = "F"
$VolumeLabel        = "DATA"
$ShareRoot          = "$DataDriveLetter`:\TFGData"
$ShareName          = "TFGData"


# Credenciales (ya en dominio, cred de dominio para aplicar DSC y para pruebas)
$DomainCred = Get-Credential "$DomainNetbios\BG_DC_Domain"

$Out = Join-Path $PSScriptRoot "FS-Shares-Out"


# ---------- Config DSC (fase 2) ----------
Configuration FileServer_Data_Shares {
  param(
    [Parameter(Mandatory)][string]   $NodeName,
    [Parameter(Mandatory)][string]   $DomainName,
    [Parameter(Mandatory)][string]   $DomainNetbios,
    [Parameter(Mandatory)][string]   $GroupPublicRW,
    [Parameter(Mandatory)][string]   $GroupPublicRO,
    [Parameter(Mandatory)][string]   $GroupITDeptoRW,
    [Parameter(Mandatory)][string]   $GroupITDeptoRO,
    [Parameter(Mandatory)][string]   $GroupFINDeptoRW,
    [Parameter(Mandatory)][string]   $GroupFINDeptoRO,
    [Parameter(Mandatory)][string]   $GroupRRHHDeptoRW,
    [Parameter(Mandatory)][string]   $GroupRRHHDeptoRO,
    [Parameter(Mandatory)][string]   $GroupProyADeptoRW,
    [Parameter(Mandatory)][string]   $GroupProyADeptoRO,
    [Parameter(Mandatory)][string]   $GroupProyBDeptoRW,
    [Parameter(Mandatory)][string]   $GroupProyBDeptoRO,
    [Parameter(Mandatory)][string]   $GroupHomesCreate,
    [Parameter(Mandatory)][string]   $DataDriveLetter,
    [Parameter(Mandatory)][string]   $VolumeLabel,
    [Parameter(Mandatory)][string]   $ShareRoot,
    [Parameter(Mandatory)][string]   $ShareName
  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration

  Node $NodeName {

    # Aseguramos el rol de File Server (necesario para crear shares)
    WindowsFeature FileServerRole {
        Name   = "FS-FileServer"
        Ensure = "Present"
    }

    # LanmanServer es el servicio de compartición de archivos. Lo aseguramos por si acaso, y lo ponemos en automático y arrancado.
    # SMB depende de este servicio, y si no está arrancado, la creación de shares fallará.
    Service LanmanServer {
        Name        = "LanmanServer"
        StartupType = "Automatic"
        State       = "Running"
        DependsOn   = "[WindowsFeature]FileServerRole"
    }

    # Deshabilitamos SMB1 (recomendado por seguridad, y evita problemas con clientes antiguos). Es idempotente.
    Script DisableSMB1 {
        TestScript = {
            (Get-SmbServerConfiguration).EnableSMB1Protocol -eq $false
        }
        SetScript = {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        }
        GetScript = { @{ Result = "SMB1 disabled" } }
        DependsOn = "[Service]LanmanServer"
    }

    # 1) Preparar disco + volumen (usa el primer disco RAW no-sistema)
    # El script es idempotente: si el disco ya tiene un volumen con la letra y etiqueta correctas, no hace nada.
    Script PrepareDataVolume {
      TestScript = {
        try {
          $vol = Get-Volume -DriveLetter $using:DataDriveLetter -ErrorAction Stop
          return ($vol.FileSystem -eq 'NTFS')
        } catch { return $false }
      }
      SetScript = {
        # Si ya existe el volumen, no tocar
        try {
          $vol = Get-Volume -DriveLetter $using:DataDriveLetter -ErrorAction Stop
          if ($vol.FileSystem -eq 'NTFS') { return }
        } catch {}

        # Buscar disco candidato (RAW, no sistema)
        $disk = Get-Disk |
          Where-Object { $_.IsSystem -eq $false -and $_.PartitionStyle -eq 'RAW' } |
          Sort-Object Number |
          Select-Object -First 1

        if (-not $disk) {
          throw "No hay disco RAW disponible para inicializar. Añade un segundo disco o ajusta la lógica."
        }

        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru | Out-Null
        $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $using:DataDriveLetter
        Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel $using:VolumeLabel -Confirm:$false | Out-Null
      }
      GetScript = { @{ Result = "Data volume checked/created" } }
    }

    # 2) Carpetas
    # Creamos el ShareRoot (si no existe) y las carpetas dentro de él. Es idempotente: si ya existen, no hace nada.
    File ShareRootFolder {
      DestinationPath = $ShareRoot
      Type            = "Directory"
      Ensure          = "Present"
      DependsOn       = "[Script]PrepareDataVolume"
    }
    
    File PublicFolder {
      DestinationPath = "$ShareRoot\PUBLIC";
      Type="Directory";
      Ensure="Present";
      DependsOn="[File]ShareRootFolder"
    }

    File DeptosFolder { 
      DestinationPath = "$ShareRoot\DEPTOS";
      Type="Directory";
      Ensure="Present";
      DependsOn="[File]ShareRootFolder"
    }
    File RRHHFolder  { 
      DestinationPath = "$ShareRoot\DEPTOS\RRHH";
      Type="Directory";
      Ensure="Present";
      DependsOn="[File]DeptosFolder"
    }
    File ITFolder    { 
      DestinationPath = "$ShareRoot\DEPTOS\IT";  
      Type="Directory";
      Ensure="Present";
      DependsOn="[File]DeptosFolder"
    }
    File FINFolder   { 
      DestinationPath = "$ShareRoot\DEPTOS\FIN";  
      Type="Directory"; 
      Ensure="Present"; 
      DependsOn="[File]DeptosFolder" 
    }

    File ProyFolder { 
      DestinationPath = "$ShareRoot\PROYECTOS";
      Type="Directory";
      Ensure="Present";
      DependsOn="[File]ShareRootFolder"
    }
    File ProyAFolder { 
      DestinationPath = "$ShareRoot\PROYECTOS\PROY_A";  
      Type="Directory"; 
      Ensure="Present"; 
      DependsOn="[File]ProyFolder" 
    }
    File ProyBFolder { 
      DestinationPath = "$ShareRoot\PROYECTOS\PROY_B";  
      Type="Directory"; 
      Ensure="Present"; 
      DependsOn="[File]ProyFolder" 
    }

    File UsersFolder { 
      DestinationPath = "$ShareRoot\USUARIOS"; 
      Type="Directory"; 
      Ensure="Present"; 
      DependsOn="[File]ShareRootFolder" 
    }


    # 3) Firewall SMB (regla por nombre, no por idioma)
    Script EnableSMBFirewall {
      TestScript = {
        $r = Get-NetFirewallRule -Name 'FPS-SMB-In-TCP' -ErrorAction SilentlyContinue
        return ($r -and $r.Enabled -eq 'True')
      }
      SetScript = {
        Enable-NetFirewallRule -Name 'FPS-SMB-In-TCP' -ErrorAction SilentlyContinue | Out-Null
      }
      GetScript = { @{ Result = "SMB firewall rule enabled" } }
      DependsOn = "[File]ShareRootFolder"
    }

    # 4) Esperar a que existan los grupos (sin RSAT: usar DirectoryServices)
    Script WaitForDomainGroups {
      TestScript = {
        try {
          $root = [ADSI]"LDAP://RootDSE"
          $dn   = $root.defaultNamingContext
          $base = [ADSI]("LDAP://$dn")
          $s = New-Object System.DirectoryServices.DirectorySearcher($base)

          $groups = @(
            $using:GroupPublicRW, $using:GroupPublicRO,
            $using:GroupITDeptoRW, $using:GroupITDeptoRO,
            $using:GroupFINDeptoRW, $using:GroupFINDeptoRO,
            $using:GroupRRHHDeptoRW, $using:GroupRRHHDeptoRO,
            $using:GroupProyADeptoRW, $using:GroupProyADeptoRO,
            $using:GroupProyBDeptoRW, $using:GroupProyBDeptoRO,
            $using:GroupHomesCreate
          )

          foreach ($g in $groups) {
            $s.Filter = "(&(objectClass=group)(sAMAccountName=$g))"
            if (-not $s.FindOne()) { return $false }
          }
          return $true
        } catch { return $false }
      }

      SetScript = {
        $deadline = (Get-Date).AddMinutes(5)

        $groups = @(
          $using:GroupPublicRW, $using:GroupPublicRO,
          $using:GroupITDeptoRW, $using:GroupITDeptoRO,
          $using:GroupFINDeptoRW, $using:GroupFINDeptoRO,
          $using:GroupRRHHDeptoRW, $using:GroupRRHHDeptoRO,
          $using:GroupProyADeptoRW, $using:GroupProyADeptoRO,
          $using:GroupProyBDeptoRW, $using:GroupProyBDeptoRO,
          $using:GroupHomesCreate
        )

        while ((Get-Date) -lt $deadline) {
          try {
            $root = [ADSI]"LDAP://RootDSE"
            $dn   = $root.defaultNamingContext
            $base = [ADSI]("LDAP://$dn")
            $s = New-Object System.DirectoryServices.DirectorySearcher($base)

            $ok = $true
            foreach ($g in $groups) {
              $s.Filter = "(&(objectClass=group)(sAMAccountName=$g))"
              if (-not $s.FindOne()) { $ok = $false; break }
            }
            if ($ok) { return }
          } catch {}

          Start-Sleep 5
        }
        throw "Timeout esperando grupos de FS en el dominio."
      }

      GetScript = { @{ Result = "All domain groups exist" } }
      DependsOn = "[Script]EnableSMBFirewall"
    }


    # 5) Crear/asegurar shares (idempotente)
    Script EnsureShares {
      TestScript = {
        $s = Get-SmbShare -Name $using:ShareName -ErrorAction SilentlyContinue
        ($s -and $s.Path -eq $using:ShareRoot)
      }
      SetScript = {
        # Limpieza de shares antiguos (por si quedaron)
        foreach ($old in @("Depto","Public")) {
          if (Get-SmbShare -Name $old -ErrorAction SilentlyContinue) {
            Remove-SmbShare -Name $old -Force
          }
        }

        $existing = Get-SmbShare -Name $using:ShareName -ErrorAction SilentlyContinue
        if ($existing -and $existing.Path -ne $using:ShareRoot) {
          Remove-SmbShare -Name $using:ShareName -Force
        }
        if (-not (Get-SmbShare -Name $using:ShareName -ErrorAction SilentlyContinue)) {
          New-SmbShare -Name $using:ShareName -Path $using:ShareRoot -CachingMode None | Out-Null
        }
      }
      GetScript = { @{ Result = "Share ensured" } }
      DependsOn = "[Script]WaitForDomainGroups","[File]ShareRootFolder"
    }



    # 6) Configurar ABE (Access-Based Enumeration). Es idempotente.
    # Así los usuarios solo verán en el explorador las carpetas a las que tengan acceso, aunque puedan acceder por ruta directa a las otras si tienen permisos NTFS.
    Script ConfigureABE {
      TestScript = {
        (Get-SmbShare -Name $using:ShareName).FolderEnumerationMode -eq "AccessBased"
      }
      SetScript = {
        Set-SmbShare -Name $using:ShareName -FolderEnumerationMode AccessBased -Force
      }
      GetScript = { @{ Result = "ABE configured" } }
      DependsOn = "[Script]EnsureShares"
    }

    # 7) Permisos SHARE (robusto a idioma usando SID 544 -> Administradores local)
    # Comprueba que el share tiene permisos de Full Control para el grupo de Administradores local (SID 544) y para Authenticated Users (SID 11), 
    # y solo para ellos. Si no, los corrige.
    Script SharePermissions {
      TestScript = {
        $admin = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).
          Translate([System.Security.Principal.NTAccount]).Value
        $auth = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')).
          Translate([System.Security.Principal.NTAccount]).Value   # Authenticated Users (localizado)

        $a = Get-SmbShareAccess -Name $using:ShareName -ErrorAction SilentlyContinue
        $hasAdmin = $a | Where-Object { $_.AccountName -eq $admin -and $_.AccessRight -eq 'Full' -and $_.AccessControlType -eq 'Allow' }
        $hasAuth  = $a | Where-Object { $_.AccountName -eq $auth  -and $_.AccessRight -eq 'Full' -and $_.AccessControlType -eq 'Allow' }
        [bool]$hasAdmin -and [bool]$hasAuth
      }

      SetScript = {
        $admin = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).
          Translate([System.Security.Principal.NTAccount]).Value
        $auth = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')).
          Translate([System.Security.Principal.NTAccount]).Value

        foreach ($x in (Get-SmbShareAccess -Name $using:ShareName -ErrorAction SilentlyContinue)) {
          if ($x.AccountName -notin @($admin,$auth)) {
            Revoke-SmbShareAccess -Name $using:ShareName -AccountName $x.AccountName -Force -ErrorAction SilentlyContinue | Out-Null
          }
        }
        Grant-SmbShareAccess -Name $using:ShareName -AccountName $admin -AccessRight Full -Force | Out-Null
        Grant-SmbShareAccess -Name $using:ShareName -AccountName $auth  -AccessRight Full -Force | Out-Null
      }

      GetScript = { @{ Result = "Share permissions ensured" } }
      DependsOn = "[Script]EnsureShares"
    }



    # 8) Permisos NTFS (SYSTEM + Admin por SID; RW/RO por nombre de dominio)
    # Permisos NTFS (solo SIDs para well-known principals)
    # - Las carpetas DEPTOS, PROYECTOS y USUARIOS no deben tener Authenticated Users (S-1-5-11) en su ACL, 
    #     para evitar que aparezcan en el explorador a usuarios sin permisos.
    Script NtfsPermissions {
      TestScript = {
        try {
          $authSid = 'S-1-5-11'  # Authenticated Users

          function HasAllowSid([string]$path, [string]$sid) {
            $acl = Get-Acl $path
            foreach ($r in $acl.Access) {
              try {
                $rsid = $r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
              } catch { continue }

              if ($rsid -eq $sid -and $r.AccessControlType -eq 'Allow') {
                return $true
              }
            }
            return $false
          }

          $root = $using:ShareRoot
          $paths = @(
            "$root\PUBLIC",
            "$root\DEPTOS",
            "$root\PROYECTOS",
            "$root\USUARIOS"
          )

          foreach ($p in $paths) { if (-not (Test-Path $p)) { return $false } }

          # Condición clave: estos contenedores NO deben tener Authenticated Users
          if (HasAllowSid "$root\DEPTOS"    $authSid) { return $false }
          if (HasAllowSid "$root\PROYECTOS" $authSid) { return $false }
          if (HasAllowSid "$root\USUARIOS"  $authSid) { return $false }

          # Y PUBLIC debe tener el RW (como antes)
          $out = (icacls "$root\PUBLIC" 2>$null) -join "`n"
          return [bool]($out -match [regex]::Escape("$using:DomainNetbios\$using:GroupPublicRW"))
        } catch {
          return $false
        }
      }

      # El SetScript es robusto a la existencia previa de permisos, y se basa en SIDs para los well-known (SYSTEM y Admins local), y en nombres para los grupos de dominio.
      # Dados los grupos de dominio que hay, la lógica de permisos es un poco compleja, pero se puede implementar con icacls y un poco de manipulación de strings.
      # La idea es:
      # - Para los contenedores (DEPTOS, PROYECTOS, USUARIOS): quitar herencia, quitar Authenticated Users, 
      #       --> y dar permisos de lectura a los grupos que pueden "ver" cada contenedor 
      #       --> (IT y FIN pueden ver DEPTOS; PA y PB pueden ver PROYECTOS; nadie excepto admins puede ver USUARIOS).
      # - Para las carpetas hoja (PUBLIC, DEPTOS\IT, DEPTOS\FIN, DEPTOS\RRHH, PROYECTOS\PROY_A, PROYECTOS\PROY_B): 
      #       --> quitar herencia y dar permisos de Full Control a SYSTEM y Admins local, RW al grupo correspondiente y RO al grupo de su mismo departamento.
      # Los permisos se establecen con icacls, pasando la lista completa de permisos que debe tener cada carpeta, y quitando los que no correspondan.
      SetScript = {
        $root = $using:ShareRoot

        $SID_SYSTEM   = "*S-1-5-18"
        $SID_ADMINS   = "*S-1-5-32-544"
        $SID_AUTH     = "*S-1-5-11"
        $SID_CREATOR  = "*S-1-3-0"

        $PUB_RW   = "$using:DomainNetbios\$using:GroupPublicRW"
        $PUB_RO   = "$using:DomainNetbios\$using:GroupPublicRO"
        $IT_RW    = "$using:DomainNetbios\$using:GroupITDeptoRW"
        $IT_RO    = "$using:DomainNetbios\$using:GroupITDeptoRO"
        $FIN_RW   = "$using:DomainNetbios\$using:GroupFINDeptoRW"
        $FIN_RO   = "$using:DomainNetbios\$using:GroupFINDeptoRO"
        $RRHH_RW  = "$using:DomainNetbios\$using:GroupRRHHDeptoRW"
        $RRHH_RO  = "$using:DomainNetbios\$using:GroupRRHHDeptoRO"
        $PA_RW    = "$using:DomainNetbios\$using:GroupProyADeptoRW"
        $PA_RO    = "$using:DomainNetbios\$using:GroupProyADeptoRO"
        $PB_RW    = "$using:DomainNetbios\$using:GroupProyBDeptoRW"
        $PB_RO    = "$using:DomainNetbios\$using:GroupProyBDeptoRO"
        $HOMES_CREATE = "$using:DomainNetbios\$using:GroupHomesCreate"

        function SetAclRootOnly([string]$path) {
          icacls $path /inheritance:r | Out-Null
          icacls $path /grant:r `
            "${SID_SYSTEM}:(F)" `
            "${SID_ADMINS}:(F)" `
            "${SID_AUTH}:(RX)" | Out-Null
        }

        function SetAclLeaf([string]$path, [string]$rw, [string]$ro) {
          icacls $path /inheritance:r | Out-Null
          icacls $path /grant:r `
            "${SID_SYSTEM}:(OI)(CI)F" `
            "${SID_ADMINS}:(OI)(CI)F" `
            "${rw}:(OI)(CI)M" `
            "${ro}:(OI)(CI)RX" | Out-Null
        }

        SetAclRootOnly $root


        function RemoveAuthUsers([string]$path) {
          # Quita Authenticated Users (S-1-5-11) del ACL del contenedor
          icacls $path /remove:g "*S-1-5-11" 2>$null | Out-Null
        }


        function SetAclContainerBrowse([string]$path, [string[]]$browseGroups) {
          icacls $path /inheritance:r | Out-Null
          RemoveAuthUsers $path

          $args = @(
            "${SID_SYSTEM}:(F)",
            "${SID_ADMINS}:(F)"
          ) + ($browseGroups | ForEach-Object { "${_}:(RX)" })

          icacls $path /grant:r @args | Out-Null
        }

        # Grupos que pueden "ver" DEPTOS
        $DeptosBrowse = @($IT_RW,$IT_RO,$FIN_RW,$FIN_RO,$RRHH_RW,$RRHH_RO)

        # Grupos que pueden "ver" PROYECTOS
        $ProyBrowse   = @($PA_RW,$PA_RO,$PB_RW,$PB_RO)

        SetAclContainerBrowse "$root\DEPTOS"    $DeptosBrowse
        SetAclContainerBrowse "$root\PROYECTOS" $ProyBrowse

        # USUARIOS (homes) - contenedor especial
        icacls "$root\USUARIOS" /inheritance:r | Out-Null
        RemoveAuthUsers "$root\USUARIOS"
        icacls "$root\USUARIOS" /grant:r `
          "${SID_SYSTEM}:(OI)(CI)F" `
          "${SID_ADMINS}:(OI)(CI)F" `
          "${SID_CREATOR}:(OI)(CI)(IO)F" `
          "${HOMES_CREATE}:(RX,AD)" | Out-Null


        SetAclLeaf "$root\PUBLIC" $PUB_RW $PUB_RO

        SetAclLeaf "$root\DEPTOS\IT"   $IT_RW   $IT_RO
        SetAclLeaf "$root\DEPTOS\FIN"  $FIN_RW  $FIN_RO
        SetAclLeaf "$root\DEPTOS\RRHH" $RRHH_RW $RRHH_RO

        SetAclLeaf "$root\PROYECTOS\PROY_A" $PA_RW $PA_RO
        SetAclLeaf "$root\PROYECTOS\PROY_B" $PB_RW $PB_RO
      }

      GetScript = { @{ Result = "NTFS permissions ensured (SID-based)" } }

      DependsOn = @(
        "[Script]SharePermissions",
        "[File]ShareRootFolder",
        "[File]PublicFolder",
        "[File]DeptosFolder","[File]ITFolder","[File]FINFolder","[File]RRHHFolder",
        "[File]ProyFolder","[File]ProyAFolder","[File]ProyBFolder",
        "[File]UsersFolder"
      )
    }

    # 9) Crear carpetas HOME para los usuarios listados en el grupo GG_FS_HOMES_CREATE, 
    #   --> con permisos adecuados (cada usuario Full Control sobre su carpeta, y owner de la misma). 
    #   --> El script es idempotente: si la carpeta ya existe y tiene los permisos correctos, no hace nada.
    Script EnsureHomeFolders {
      TestScript = {
        try {
          $homeRoot = "$using:ShareRoot\USUARIOS"
          if (-not (Test-Path $homeRoot)) { return $false }

          # Buscar el grupo en AD
          $root = [ADSI]"LDAP://RootDSE"
          $dn   = $root.defaultNamingContext
          $base = [ADSI]("LDAP://$dn")
          $s    = New-Object System.DirectoryServices.DirectorySearcher($base)
          $s.Filter = "(&(objectClass=group)(sAMAccountName=$using:GroupHomesCreate))"
          $r = $s.FindOne()
          if (-not $r) { return $false }

          $g = $r.GetDirectoryEntry()
          $members = @($g.Properties["member"])
          if ($members.Count -eq 0) { return $true }  # grupo vacío => OK

          foreach ($m in $members) {
            $u = [ADSI]("LDAP://$m")
            $sam = [string]$u.Properties["sAMAccountName"].Value
            if ([string]::IsNullOrWhiteSpace($sam)) { continue }

            $p = Join-Path $homeRoot $sam
            if (-not (Test-Path $p)) { return $false }
          }
          return $true
        } catch { return $false }
      }

      SetScript = {
        $homeRoot = "$using:ShareRoot\USUARIOS"

        # SIDs idioma-proof
        $SID_SYSTEM = "*S-1-5-18"
        $SID_ADMINS = "*S-1-5-32-544"

        # 1) localizar grupo en AD (sin módulo AD)
        $root = [ADSI]"LDAP://RootDSE"
        $dn   = $root.defaultNamingContext
        $base = [ADSI]("LDAP://$dn")
        $s    = New-Object System.DirectoryServices.DirectorySearcher($base)
        $s.Filter = "(&(objectClass=group)(sAMAccountName=$using:GroupHomesCreate))"
        $r = $s.FindOne()
        if (-not $r) { throw "No se encontró el grupo $using:GroupHomesCreate en AD" }

        $g = $r.GetDirectoryEntry()
        $members = @($g.Properties["member"])

        foreach ($m in $members) {
          $u = [ADSI]("LDAP://$m")
          $sam = [string]$u.Properties["sAMAccountName"].Value
          if ([string]::IsNullOrWhiteSpace($sam)) { continue }

          $p = Join-Path $homeRoot $sam
          if (-not (Test-Path $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
          } 

          $userAcct = "$using:DomainNetbios\$sam"
          
          # 2) ACL por carpeta HOME: SYSTEM/Admins Full, usuario Modify
          icacls $p /inheritance:r | Out-Null
          icacls $p /grant:r `
            ("{0}:(OI)(CI)F" -f $SID_SYSTEM) `
            ("{0}:(OI)(CI)F" -f $SID_ADMINS) `
            ("{0}:(OI)(CI)M" -f $userAcct) | Out-Null

          # setear el owner al usuario para que pueda administrar su carpeta (aunque el permiso Modify ya le permite cambiar permisos, etc., es más correcto que sea el owner)
          icacls $p /setowner $userAcct | Out-Null
        }
      }

      GetScript = { @{ Result = "Home folders ensured" } }

      DependsOn = @(
        "[Script]NtfsPermissions"  # para que USUARIOS ya exista y tenga ACL base
      )
    }

    # Este script aplica recomendaciones de hardening para SMB basadas en el CCN 573, y es idempotente: si ya están aplicadas, no hace nada.
    Script CCN573_SmbHardening {
      TestScript = {
        $cfg = Get-SmbServerConfiguration
        ($cfg.EnableAuthenticateUserSharing -eq $false) -and
        ($cfg.EncryptData -eq $true) -and
        ($cfg.RejectUnencryptedAccess -eq $true) -and
        ($cfg.EnableLeasing -eq $true) -and
        ($cfg.SmbServerNameHardeningLevel -eq 2)
      }
      SetScript  = {
        # 1) Deshabilitar autenticación compartida
        Set-SmbServerConfiguration -EnableAuthenticateUserSharing:$false -Confirm:$false

        # 2) Cifrado a nivel servidor (evitando el guion “–” del script CCN)
        Set-SmbServerConfiguration -EncryptData $true -Confirm:$false
        Set-SmbServerConfiguration -RejectUnencryptedAccess $true -Confirm:$false

        # (opcional) cifrado a nivel del share
        if (Get-SmbShare -Name $using:ShareName -ErrorAction SilentlyContinue) {
          Set-SmbShare -Name $using:ShareName -EncryptData $true -Force
          Set-SmbShare -Name $using:ShareName -LeasingMode Full -Force
        }

        # 3) Leasing + Name hardening
        Set-SmbServerConfiguration -EnableLeasing $true -Confirm:$false
        Set-SmbServerConfiguration -SmbServerNameHardeningLevel 2 -Confirm:$false

        # 4) Logs recomendados por CCN 573 + auditoría de accesos SMB1
        foreach ($logName in @(
          'Microsoft-Windows-FileServices-ServerManager-EventProvider/Operational',
          'Microsoft-Windows-FileServices-ServerManager-EventProvider/Admin',
          'Microsoft-Windows-Ntfs/WHC',
          'Microsoft-Windows-Ntfs/Operational'
        )) {
          $l = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
          if ($l) { $l.IsEnabled = $true; $l.SaveChanges() }
        }
        Set-SmbServerConfiguration -AuditSmb1Access $true -Confirm:$false
      }
      GetScript  = { @{ Result = "CCN 573 SMB hardening applied" } }
      DependsOn  = "[Script]EnsureShares"
    }

  }
}



New-Item -ItemType Directory -Path $Out -Force | Out-Null
Remove-Item "$Out\*" -Recurse -Force -ErrorAction SilentlyContinue

$ConfigData = @{
  AllNodes = @(
    @{
      NodeName                    = $Server
      PSDscAllowPlainTextPassword = $true
      PSDscAllowDomainUser        = $true
    }
  )
}

FileServer_Data_Shares -NodeName $Server `
  -DomainName $DomainName `
  -DomainNetbios $DomainNetbios `
  -DataDriveLetter $DataDriveLetter `
  -VolumeLabel $VolumeLabel `
  -GroupPublicRW $GroupPublicRW `
  -GroupPublicRO $GroupPublicRO `
  -GroupITDeptoRW $GroupITDeptoRW `
  -GroupITDeptoRO $GroupITDeptoRO `
  -GroupFINDeptoRW $GroupFINDeptoRW `
  -GroupFINDeptoRO $GroupFINDeptoRO `
  -GroupRRHHDeptoRW $GroupRRHHDeptoRW `
  -GroupRRHHDeptoRO $GroupRRHHDeptoRO `
  -GroupProyADeptoRW $GroupProyADeptoRW `
  -GroupProyADeptoRO $GroupProyADeptoRO `
  -GroupProyBDeptoRW $GroupProyBDeptoRW `
  -GroupProyBDeptoRO $GroupProyBDeptoRO `
  -GroupHomesCreate $GroupHomesCreate `
  -ShareRoot $ShareRoot `
  -ShareName $ShareName `
  -OutputPath $Out `
  -ConfigurationData $ConfigData


Write-Host ">> Aplicando fase 2 (disco + shares + permisos) a $Server..." -ForegroundColor Cyan
Start-DscConfiguration -Path $Out -ComputerName $Server -Credential $DomainCred -Wait -Force -Verbose

Write-Host ">> Post-check shares/permisos..." -ForegroundColor Cyan
Invoke-Command -ComputerName $Server -Credential $DomainCred -ScriptBlock {
  $s = Get-SmbShare -Name "TFGData"
  $p = $s.Path

  $s | Select Name,Path,FolderEnumerationMode
  "---- ACCESS SHARE ----"
  Get-SmbShareAccess -Name "TFGData"

  "---- NTFS ROOT ----"
  icacls $p
  "---- NTFS PUBLIC ----"
  icacls (Join-Path $p "PUBLIC")
  "---- NTFS IT ----"
  icacls (Join-Path $p "DEPTOS\IT")
} | Out-Host


