param(
  [Parameter(Mandatory=$true)]
  [string]$Server
)

$DomainName       = "ad.umtfg.com"
$DomainNetbios    = "ADTFG"
$DomainDN         = "DC=ad,DC=umtfg,DC=com"

$FileServerName   = "FS2"          # el nombre real del fileserver en el dominio
$HomeShareName    = "TFGData"      # Share donde se crearán los directorios home de los usuarios (ej: \\FS2\TFGData\userIT)
$HomeBase         = "\\$FileServerName\$HomeShareName\USUARIOS" # base para los home directories (ej: \\FS2\TFGData\USUARIOS\userIT)
$HomeDrive        = "H:"


# Ya en dominio, credencial de dominio
$DomainAdminCredential = New-Object pscredential(
  "$DomainNetbios\Administrador",
  (ConvertTo-SecureString "DC_local!2026" -AsPlainText -Force)
)

# Password para los usuarios (ADUser espera PSCredential en Password)
$NormalUserPassword = New-Object pscredential(
  "unused",
  (ConvertTo-SecureString "User123!2026" -AsPlainText -Force)
)


# --- ADMINISTRACIÓN / BREAKGLASS (DOMINIO) ---
$BGDomainSam = "BG_DC_Domain"
$BGDomainUpn = "$BGDomainSam@$DomainName"
$BGDomainPassword = New-Object pscredential(
  "unused",
  (ConvertTo-SecureString "BG_Admin!2026" -AsPlainText -Force)
)

# Admin delegado (operación normal, NO Domain Admin)
$OpsAdminSam = "OpsAdmin"
$OpsAdminUpn = "$OpsAdminSam@$DomainName"
$OpsAdminPassword = New-Object pscredential(
  "unused",
  (ConvertTo-SecureString "Ops_admin!2026" -AsPlainText -Force)
)

# Grupo de admins delegados
$GgServerAdminsSam    = "GG_Server_Admins"
$GgFsLocalAdminsSam   = "GG_FS_LocalAdmins"
$GgWs25LocalAdminsSam = "GG_WS25_LocalAdmins"

# === MGMT SCOPE (tu PC / subred de admin) ===
$MgmtIPv4Filter       = "192.168.137.0/24"     # WinRM policy filter (string)
$MgmtRemoteAddr       = @("192.168.137.0/24")  # Firewall remote address (array)

$GpoWinRmMembers      = "EXC-MGMT-WinRM-Members"
$GpoWinRmDCs          = "EXC-MGMT-WinRM-DCs"

Configuration AD_Objects {
  param(
    [Parameter(Mandatory)][string]$NodeName,
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][pscredential]$DomainAdminCredential,
    [Parameter(Mandatory)][string]$DomainDN,
    [Parameter(Mandatory)][string]$HomeDrive,
    [Parameter(Mandatory)][string]$HomeBase,
    [Parameter(Mandatory)][pscredential]$NormalUserPassword,

    [Parameter(Mandatory)][string]$BGDomainSam,
    [Parameter(Mandatory)][string]$BGDomainUpn,
    [Parameter(Mandatory)][pscredential]$BGDomainPassword,
    [Parameter(Mandatory)][string]$OpsAdminSam,
    [Parameter(Mandatory)][string]$OpsAdminUpn,
    [Parameter(Mandatory)][pscredential]$OpsAdminPassword,
    [Parameter(Mandatory)][string]$GgServerAdminsSam,

    [Parameter(Mandatory)][string]   $MgmtIPv4Filter,
    [Parameter(Mandatory)][string[]] $MgmtRemoteAddr,
    [Parameter(Mandatory)][string]   $GpoWinRmMembers,
    [Parameter(Mandatory)][string]   $GpoWinRmDCs
  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration
  Import-DscResource -ModuleName ActiveDirectoryDsc

  Node $NodeName {

    #Esperamos a que el dominio esté listo antes de crear objetos AD, para evitar errores de replicación o de controladores de dominio no disponibles.
    WaitForADDomain DomainReady {
      DomainName   = $DomainName
      Credential   = $DomainAdminCredential
      WaitTimeout  = 600 
      RestartCount = 0
    }

    
    # OUs base CCN raíz "OU=Servidores,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_Servidores {
      Name    = "Servidores"
      Path    = $DomainDN   # "DC=ad,DC=umtfg,DC=com"
      Ensure  = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[WaitForADDomain]DomainReady"
    }

    # "OU=Clientes,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_Clientes {
      Name    = "Clientes"
      Path    = $DomainDN   # "DC=ad,DC=umtfg,DC=com"
      Ensure  = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[WaitForADDomain]DomainReady"
    }

    # "OU=Identidades,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_Identidades {
      Name    = "Identidades"
      Path    = $DomainDN   # "DC=ad,DC=umtfg,DC=com"
      Ensure  = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[WaitForADDomain]DomainReady"
    }

    
    $RootServidoresOU   = "OU=Servidores,$DomainDN"   
    $RootClientesOU     = "OU=Clientes,$DomainDN"     
    $RootIdentidadesOU  = "OU=Identidades,$DomainDN"


    # SubOU Servers: "OU=ServidoresMiembro,OU=Servidores,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_ServidoresMiembro {
      Name  = "ServidoresMiembro"
      Path  = $RootServidoresOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Servidores"
    }

    # SubOU FileServers: "OU=ServidoresDeFicheros,OU=Servidores,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_ServidoresDeFicheros {
      Name  = "ServidoresDeFicheros"
      Path  = $RootServidoresOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Servidores"
    }

    # SubOU Workstations: "OU=EstacionesDeTrabajo,OU=Clientes,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_EstacionesDeTrabajo { 
      Name  = "EstacionesDeTrabajo"
      Path  = $RootClientesOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Clientes"
    }

    # SubOU Workstations: "OU=EstacionesWS25,OU=Clientes,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_EstacionesWS25 { 
      Name  = "EstacionesWS25"
      Path  = $RootClientesOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Clientes"
    }
    
    # SubOU Usuarios: "OU=Usuarios,OU=Identidades,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_Usuarios{ 
      Name  = "Usuarios"
      Path  = $RootIdentidadesOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Identidades"
    }

    # SubOU Grupos: "OU=Grupos,OU=Identidades,DC=ad,DC=umtfg,DC=com"
    ADOrganizationalUnit OU_Grupos {
      Name  = "Grupos"
      Path  = $RootIdentidadesOU
      Ensure = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Identidades"
    }
    
# OUs DE ADMINISTRACIÓN Y BREAKGLASS (en Identidades)
    ADOrganizationalUnit OU_Admins {
      Name    = "Admins"
      Path    = $RootIdentidadesOU
      Ensure  = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Identidades"
    }

    ADOrganizationalUnit OU_BreakGlass {
      Name    = "BreakGlass"
      Path    = "OU=Admins,$RootIdentidadesOU"
      Ensure  = "Present"
      ProtectedFromAccidentalDeletion = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Admins"
    }


    $AdminsOU     = "OU=Admins,$RootIdentidadesOU"
    $BreakGlassOU = "OU=BreakGlass,$AdminsOU"

    # Usuario OpsAdmin (admin delegado)
    ADUser OpsAdmin {
      UserName   = $OpsAdminSam
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $OpsAdminPassword
      Path       = $AdminsOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Admins"
    }

    # BreakGlass de dominio (EMERGENCIA)
    ADUser BG_DomainAdmin {
      UserName           = $BGDomainSam
      Ensure             = "Present"
      DomainName         = $DomainName
      UserPrincipalName  = $BGDomainUpn
      Password           = $BGDomainPassword
      Path               = $BreakGlassOU
      Enabled            = $true
      PasswordNeverExpires = $true   # LAB: en real, mejor rotación + vault
      Credential         = $DomainAdminCredential
      DependsOn          = "[ADOrganizationalUnit]OU_BreakGlass"
    }


# USUARIOS DEL CLIENTE (con acceso a recursos departamentales, HOMES, etc.)
    
    # "OU=Usuarios,OU=Identidades,DC=ad,DC=umtfg,DC=com"
    $UsersOU  = "OU=Usuarios,$RootIdentidadesOU"
    

    # Usuario de IT
    ADUser UserIT {
      UserName   = "userIT"
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $NormalUserPassword
      Path       = $UsersOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      HomeDrive     = $HomeDrive
      HomeDirectory = "$HomeBase\userIT"    # para userIT
      DependsOn  = "[ADOrganizationalUnit]OU_Usuarios"
    }

    # Usuario de Finanzas
    ADUser UserFIN {
      UserName   = "userFIN"
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $NormalUserPassword
      Path       = $UsersOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      HomeDrive     = $HomeDrive
      HomeDirectory = "$HomeBase\userFIN"    # para userFIN
      DependsOn  = "[ADOrganizationalUnit]OU_Usuarios"
    }

    # Usuario de RRHH
    ADUser UserRRHH {
      UserName   = "userRRHH"
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $NormalUserPassword
      Path       = $UsersOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      HomeDrive     = $HomeDrive
      HomeDirectory = "$HomeBase\userRRHH"   # para userRRHH
      DependsOn  = "[ADOrganizationalUnit]OU_Usuarios"
    }

    # Usuario solo para PUBLIC (sin acceso a recursos departamentales)
    ADUser UserPublic {
      UserName   = "UserPublic"
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $NormalUserPassword
      Path       = $UsersOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Usuarios"
    }

    # Usuario sin permisos (no se incluye en ningún grupo)
    ADUser UserSinPermisos {
      UserName   = "SinPermisos"
      Ensure     = "Present"
      DomainName = $DomainName
      Password   = $NormalUserPassword
      Path       = $UsersOU
      Enabled    = $true
      Credential = $DomainAdminCredential
      DependsOn  = "[ADOrganizationalUnit]OU_Usuarios"
    }


    # "OU=Groups,OU=Identidades,DC=ad,DC=umtfg,DC=com" 
    $GroupsOU = "OU=Grupos,$RootIdentidadesOU" 

    # Grupo de admins de servidores (delegado)
    ADGroup GG_Server_Admins {
      GroupName        = "GG_Server_Admins"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("OpsAdmin", $BGDomainSam)
      Credential       = $DomainAdminCredential
      DependsOn        = @(
        "[ADOrganizationalUnit]OU_Grupos",
        "[ADUser]OpsAdmin",
        "[ADUser]BG_DomainAdmin"
      )
    }

    ADGroup GG_FS_LocalAdmins {
      GroupName        = $GgFsLocalAdminsSam
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @($BGDomainSam, $OpsAdminSam)
      Credential       = $DomainAdminCredential
      DependsOn        = @(
        "[ADOrganizationalUnit]OU_Grupos",
        "[ADUser]BG_DomainAdmin",
        "[ADUser]OpsAdmin"
      )
    }

    ADGroup GG_WS25_LocalAdmins {
      GroupName        = $GgWs25LocalAdminsSam
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @($BGDomainSam, $OpsAdminSam)
      Credential       = $DomainAdminCredential
      DependsOn        = @(
        "[ADOrganizationalUnit]OU_Grupos",
        "[ADUser]BG_DomainAdmin",
        "[ADUser]OpsAdmin"
      )
    }

    ADGroup BG_in_DomainAdmins {
      GroupName           = "Domain Admins"
      MembersToInclude    = @($BGDomainSam)
      MembershipAttribute = "SamAccountName"
      Credential          = $DomainAdminCredential
      DependsOn           = "[ADUser]BG_DomainAdmin"
    }


    # Creamos los grupos para el servicio de ficheros
    # PUBLIC
    ADGroup GG_FS_PUBLIC_RW {
      GroupName        = "GG_FS_PUBLIC_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userIT","userFIN","userRRHH")  
      MembersToExclude = @("SinPermisos","UserPublic")  # opcional
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserFIN","[ADUser]UserRRHH","[ADUser]UserSinPermisos","[ADUser]UserPublic")
    }

    ADGroup GG_FS_PUBLIC_RO {
      GroupName        = "GG_FS_PUBLIC_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("UserPublic")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserPublic")
    }

    # DEPOTS/IT
    ADGroup GG_FS_IT_RW {
      GroupName        = "GG_FS_IT_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userIT")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT")
    }

    ADGroup GG_FS_IT_RO {
      GroupName        = "GG_FS_IT_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      #MembersToInclude = @("userIT")  # opcional: si no se incluye, el acceso de lectura se hereda del grupo PUBLIC_RO
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT")
    }
 
    # DEPTOS/RRHH
    ADGroup GG_FS_RRHH_RW {
      GroupName        = "GG_FS_RRHH_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userRRHH")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserRRHH")
    }

    ADGroup GG_FS_RRHH_RO {
      GroupName        = "GG_FS_RRHH_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      #MembersToInclude = @("userRRHH")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserRRHH")
    }

    # DEPOTS/FINANZAS
    ADGroup GG_FS_FIN_RW {
      GroupName        = "GG_FS_FIN_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userFIN")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserFIN")
    }

    ADGroup GG_FS_FIN_RO {
      GroupName        = "GG_FS_FIN_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      #MembersToInclude = @("userFIN")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserFIN")
    }

    # PROYECTO A
    ADGroup GG_FS_PROY_A_RW {
      GroupName        = "GG_FS_PROY_A_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userIT","userFIN")  # ejemplo de usuario con acceso a varios recursos
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserFIN")
    }

    ADGroup GG_FS_PROY_A_RO {
      GroupName        = "GG_FS_PROY_A_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      #MembersToInclude = @("userIT","userFIN")
      MembersToExclude = @("userRRHH")  # opcional
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserFIN","[ADUser]UserRRHH")
    }

    # PROYECTO B
    ADGroup GG_FS_PROY_B_RW {
      GroupName        = "GG_FS_PROY_B_RW"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userIT","userRRHH")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserRRHH")
    }

    ADGroup GG_FS_PROY_B_RO {
      GroupName        = "GG_FS_PROY_B_RO"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      #MembersToInclude = @("userIT","userRRHH")
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserRRHH")
    }

    # HOMES
    ADGroup GG_FS_HOMES_CREATE {
      GroupName        = "GG_FS_HOMES_CREATE"
      GroupScope       = "Global"
      Category         = "Security"
      Path             = $GroupsOU
      Ensure           = "Present"
      MembersToInclude = @("userIT","userFIN","userRRHH")  # ejemplo de usuario con acceso a varios recursos
      Credential       = $DomainAdminCredential
      DependsOn        = @("[ADOrganizationalUnit]OU_Grupos","[ADUser]UserIT","[ADUser]UserFIN","[ADUser]UserRRHH")
    }

    Script BG_in_BuiltinAdministrators {
      PsDscRunAsCredential = $DomainAdminCredential

      TestScript = {
        Import-Module ActiveDirectory -ErrorAction Stop

        $m = Get-ADGroupMember -Identity 'S-1-5-32-544' -Recursive -ErrorAction SilentlyContinue |
             Where-Object SamAccountName -eq $using:BGDomainSam

        return [bool]$m
      }

      SetScript = {
        Import-Module ActiveDirectory -ErrorAction Stop

        $m = Get-ADGroupMember -Identity 'S-1-5-32-544' -Recursive -ErrorAction SilentlyContinue |
             Where-Object SamAccountName -eq $using:BGDomainSam

        if (-not $m) {
          Add-ADGroupMember -Identity 'S-1-5-32-544' -Members $using:BGDomainSam -ErrorAction Stop
        }
      }

      GetScript = {
        @{ Result = "BG ensured in BUILTIN\\Administrators" }
      }

      DependsOn = @(
        "[ADUser]BG_DomainAdmin",
        "[ADGroup]BG_in_DomainAdmins"
      )
    }

    
    Script GG_ServerAdmins_in_RemoteManagementUsers {
      PsDscRunAsCredential = $DomainAdminCredential

      TestScript = {
        Import-Module ActiveDirectory -ErrorAction Stop

        $m = Get-ADGroupMember -Identity 'S-1-5-32-580' -Recursive -ErrorAction SilentlyContinue |
            Where-Object SamAccountName -eq $using:GgServerAdminsSam

        return [bool]$m
      }

      SetScript = {
        Import-Module ActiveDirectory -ErrorAction Stop

        $m = Get-ADGroupMember -Identity 'S-1-5-32-580' -Recursive -ErrorAction SilentlyContinue |
            Where-Object SamAccountName -eq $using:GgServerAdminsSam

        if (-not $m) {
          Add-ADGroupMember -Identity 'S-1-5-32-580' -Members $using:GgServerAdminsSam -ErrorAction Stop
        }
      }

      GetScript = {
        @{ Result = "GG_Server_Admins ensured in BUILTIN\Remote Management Users" }
      }

      DependsOn = @(
        "[ADGroup]GG_Server_Admins"
      )
    }

    Script GPO_ExcWinRM_Members {
      PsDscRunAsCredential = $DomainAdminCredential
      DependsOn = @(
        "[WaitForADDomain]DomainReady",
        "[ADOrganizationalUnit]OU_ServidoresDeFicheros",
        "[ADOrganizationalUnit]OU_EstacionesWS25"
      )

      TestScript = {
        Import-Module GroupPolicy -ErrorAction Stop
        Import-Module NetSecurity -ErrorAction Stop

        $g = Get-GPO -Name $using:GpoWinRmMembers -ErrorAction SilentlyContinue
        if (-not $g) { return $false }

        # Chequeo rápido de 2 valores clave (política WinRM)
        $svcKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
        $a  = Get-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "AllowAutoConfig" -ErrorAction SilentlyContinue
        $f4 = Get-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "IPv4Filter"     -ErrorAction SilentlyContinue
        $f6 = Get-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "IPv6Filter"     -ErrorAction SilentlyContinue

        if (-not $a  -or $a.Value  -ne 1)   { return $false }
        if (-not $f4 -or $f4.Value -ne "*") { return $false }
        if (-not $f6 -or $f6.Value -ne "*") { return $false }

        # Regla de firewall en el PolicyStore del GPO
        $store = "$($using:DomainName)\$($using:GpoWinRmMembers)"
        try {
          $null = Get-NetFirewallRule -PolicyStore $store -Name "MGMT-WinRM-HTTP-In" -ErrorAction Stop
        } catch {
          return $false
        }

        # Comprobar que la GPO está linkada en los 2 targets
        $memberTargets = @(
          "OU=ServidoresDeFicheros,OU=Servidores,$($using:DomainDN)",
          "OU=EstacionesWS25,OU=Clientes,$($using:DomainDN)"
        )

        foreach ($t in $memberTargets) {
          $links = (Get-GPInheritance -Target $t).GpoLinks
          if (-not ($links | Where-Object DisplayName -eq $using:GpoWinRmMembers)) { return $false }
        }

        return $true
      }

      SetScript = {
        # Asegura módulos/features si hiciera falta
        if (-not (Get-Module -ListAvailable GroupPolicy)) {
          Import-Module ServerManager -ErrorAction SilentlyContinue
          Install-WindowsFeature -Name GPMC -IncludeManagementTools | Out-Null
        }
        Import-Module GroupPolicy -ErrorAction Stop
        Import-Module NetSecurity -ErrorAction Stop

        # 1) Crear GPO si no existe
        $gpo = Get-GPO -Name $using:GpoWinRmMembers -ErrorAction SilentlyContinue
        if (-not $gpo) {
          $gpo = New-GPO -Name $using:GpoWinRmMembers -Comment "Excepción: mantener WinRM para DSC push (Members)"
        }

        # 2) Set de políticas WinRM vía registro (equivalente a ADMX)
        #    Claves conocidas bajo HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\... :contentReference[oaicite:3]{index=3}
        $svcKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"

        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "AllowAutoConfig" -Type DWord -Value 1
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "IPv4Filter"     -Type String -Value "*"
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "IPv6Filter"     -Type String -Value "*"
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "AllowBasic"     -Type DWord  -Value 0
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $svcKey -ValueName "AllowUnencryptedTraffic" -Type DWord -Value 0

        $cliKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $cliKey -ValueName "AllowBasic"            -Type DWord  -Value 0
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $cliKey -ValueName "AllowUnencryptedTraffic" -Type DWord -Value 0

        # Remote Shell (PowerShell Remoting) – útil para Enter-PSSession / DSC push
        # Key habitual: ...WinRM\Service\WinRS\AllowRemoteShellAccess (DWORD 1)
        $winrsKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS"
        Set-GPRegistryValue -Name $using:GpoWinRmMembers -Key $winrsKey -ValueName "AllowRemoteShellAccess" -Type DWord -Value 1

        # 3) Firewall rule dentro del GPO usando GPOSession (más eficiente)
        # PolicyStore en GPO: "dominio\GPOName" :contentReference[oaicite:4]{index=4}
        # Ejemplo Open-NetGPO + Save-NetGPO :contentReference[oaicite:5]{index=5}
        $store = "$($using:DomainName)\$($using:GpoWinRmMembers)"

        Remove-NetFirewallRule -Name "MGMT-WinRM-HTTP-In" -PolicyStore $store -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule `
          -Name "MGMT-WinRM-HTTP-In" `
          -DisplayName "MGMT WinRM HTTP (5985) - Scoped" `
          -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 `
          -RemoteAddress $using:MgmtRemoteAddr `
          -Profile Domain,Private `
          -PolicyStore $store | Out-Null

        # 4) Link a OU=Servidores con Order=1 (máxima precedencia)
        # Targets reales donde caen tus equipos
        $memberTargets = @(
          "OU=ServidoresDeFicheros,OU=Servidores,$($using:DomainDN)",
          "OU=EstacionesWS25,OU=Clientes,$($using:DomainDN)"
        )

        foreach ($t in $memberTargets) {
          # Link si no existe
          $links = (Get-GPInheritance -Target $t).GpoLinks
          if (-not ($links | Where-Object DisplayName -eq $using:GpoWinRmMembers)) {
            New-GPLink -Name $using:GpoWinRmMembers -Target $t -LinkEnabled Yes | Out-Null
          }

          # Máxima precedencia en ESA OU
          Set-GPLink -Name $using:GpoWinRmMembers -Target $t -Order 1 -LinkEnabled Yes -Enforced No | Out-Null
        }
      }

      GetScript = { @{ Result = "GPO EXC WinRM Members ensured" } }
    }

    Script GPO_ExcWinRM_DCs {
      PsDscRunAsCredential = $DomainAdminCredential
      DependsOn = "[WaitForADDomain]DomainReady"

      TestScript = {
        Import-Module GroupPolicy -ErrorAction Stop
        Import-Module NetSecurity -ErrorAction Stop

        $g = Get-GPO -Name $using:GpoWinRmDCs -ErrorAction SilentlyContinue
        if (-not $g) { return $false }

        $svcKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
        $a  = Get-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "AllowAutoConfig" -ErrorAction SilentlyContinue
        $f4 = Get-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "IPv4Filter"     -ErrorAction SilentlyContinue
        $f6 = Get-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "IPv6Filter"     -ErrorAction SilentlyContinue

        if (-not $a  -or $a.Value  -ne 1)   { return $false }
        if (-not $f4 -or $f4.Value -ne "*") { return $false }
        if (-not $f6 -or $f6.Value -ne "*") { return $false }

        $store = "$($using:DomainName)\$($using:GpoWinRmDCs)"
        try {
          $null = Get-NetFirewallRule -PolicyStore $store -Name "MGMT-WinRM-HTTP-In" -ErrorAction Stop
        } catch {
          return $false
        }

        $dcOU = "OU=Domain Controllers,$($using:DomainDN)"
        $links = (Get-GPInheritance -Target $dcOU).GpoLinks
        if (-not ($links | Where-Object { $_.DisplayName -eq $using:GpoWinRmDCs })) {
          return $false
        }

        return $true
      }

      SetScript = {
        if (-not (Get-Module -ListAvailable GroupPolicy)) {
          Import-Module ServerManager -ErrorAction SilentlyContinue
          Install-WindowsFeature -Name GPMC -IncludeManagementTools | Out-Null
        }

        Import-Module GroupPolicy -ErrorAction Stop
        Import-Module NetSecurity -ErrorAction Stop

        $gpo = Get-GPO -Name $using:GpoWinRmDCs -ErrorAction SilentlyContinue
        if (-not $gpo) {
          $gpo = New-GPO -Name $using:GpoWinRmDCs -Comment "Excepción: mantener WinRM para DSC push (DCs)"
        }

        $svcKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "AllowAutoConfig" -Type DWord -Value 1
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "IPv4Filter" -Type String -Value "*"
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "IPv6Filter" -Type String -Value "*"
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "AllowBasic" -Type DWord -Value 0
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $svcKey -ValueName "AllowUnencryptedTraffic" -Type DWord -Value 0

        $winrsKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS"
        Set-GPRegistryValue -Name $using:GpoWinRmDCs -Key $winrsKey -ValueName "AllowRemoteShellAccess" -Type DWord -Value 1

        $store = "$($using:DomainName)\$($using:GpoWinRmDCs)"

        Remove-NetFirewallRule -Name "MGMT-WinRM-HTTP-In" -PolicyStore $store -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule `
          -Name "MGMT-WinRM-HTTP-In" `
          -DisplayName "MGMT WinRM HTTP (5985) - Scoped" `
          -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 `
          -RemoteAddress $using:MgmtRemoteAddr `
          -Profile Domain,Private `
          -PolicyStore $store | Out-Null

        $dcOU = "OU=Domain Controllers,$($using:DomainDN)"
        $links = (Get-GPInheritance -Target $dcOU).GpoLinks

        if (-not ($links | Where-Object { $_.DisplayName -eq $using:GpoWinRmDCs })) {
          New-GPLink -Name $using:GpoWinRmDCs -Target $dcOU -LinkEnabled Yes | Out-Null
        }

        Set-GPLink -Name $using:GpoWinRmDCs -Target $dcOU -Order 1 -LinkEnabled Yes -Enforced No | Out-Null
      }

      GetScript = { @{ Result = "GPO EXC WinRM DCs ensured" } }
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


$Out = Join-Path $PSScriptRoot "ADObjects-Out"
if (Test-Path $Out) { Remove-Item "$Out\*" -Recurse -Force } else { New-Item -ItemType Directory -Path $Out | Out-Null }

Write-Host ">> Compilando configuración para AD-Objects --> $Server..." -ForegroundColor Cyan

AD_Objects -NodeName $Server `
  -DomainName $DomainName `
  -DomainAdminCredential $DomainAdminCredential `
  -DomainDN $DomainDN `
  -NormalUserPassword $NormalUserPassword `
  -HomeDrive $HomeDrive `
  -HomeBase $HomeBase `
  -BGDomainSam $BGDomainSam `
  -BGDomainUpn $BGDomainUpn `
  -BGDomainPassword $BGDomainPassword `
  -OpsAdminSam $OpsAdminSam `
  -OpsAdminUpn $OpsAdminUpn `
  -OpsAdminPassword $OpsAdminPassword `
  -GgServerAdminsSam $GgServerAdminsSam `
  -MgmtIPv4Filter  $MgmtIPv4Filter `
  -MgmtRemoteAddr  $MgmtRemoteAddr `
  -GpoWinRmMembers $GpoWinRmMembers `
  -GpoWinRmDCs     $GpoWinRmDCs `
  -OutputPath $Out `
  -ConfigurationData $ConfigData


Write-Host ">> Aplicando AD Provisioning --> $Server..." -ForegroundColor Cyan
Start-DscConfiguration -Path $Out -ComputerName $Server -Credential $DomainAdminCredential -Wait -Force -Verbose


#$BGCred = New-Object pscredential("$DomainNetbios\$BGDomainSam",(ConvertTo-SecureString "BG_admin!2026" -AsPlainText -Force))
#Invoke-Command -ComputerName $Server -Credential $BGCred -ScriptBlock { whoami; Get-ADDomain | Select-Object DNSRoot } -ErrorAction Stop


Invoke-Command -ComputerName $Server -Credential $DomainAdminCredential -Authentication Negotiate -ScriptBlock {
  Import-Module ActiveDirectory

  Write-Host "=== USER ==="
  Get-ADUser BG_DC_Domain -Properties Enabled,LockedOut,PasswordNeverExpires,MemberOf |
    Select-Object SamAccountName, Enabled, LockedOut, PasswordNeverExpires

  Write-Host "=== GROUPS ==="
  Get-ADPrincipalGroupMembership BG_DC_Domain |
    Select-Object Name | Sort-Object Name

  Write-Host "=== DOMAIN ADMINS CHECK ==="
  Get-ADGroupMember "Domain Admins" |
    Where-Object SamAccountName -eq "BG_DC_Domain" |
    Select-Object Name, SamAccountName
} -ErrorAction Stop


Write-Host ">> FIN SCRIPT 2 (AD Provisioning)." -ForegroundColor Cyan
