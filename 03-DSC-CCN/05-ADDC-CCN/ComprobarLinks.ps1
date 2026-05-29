$dc   = "192.168.137.10"
$cred = Get-Credential "ADTFG\BG_DC_Domain"

Invoke-Command -ComputerName $dc -Credential $cred -ScriptBlock {
  Import-Module ActiveDirectory
  Import-Module GroupPolicy

  $d = (Get-ADDomain).DistinguishedName

  $targets = [ordered]@{
    "DOMINIO"                 = $d
    "OU Domain Controllers"   = "OU=Domain Controllers,$d"
    "OU Servidores"           = "OU=Servidores,$d"
    "OU Clientes"             = "OU=Clientes,$d"
    "OU ServidoresDeFicheros" = "OU=ServidoresDeFicheros,OU=Servidores,$d"
    "OU EstacionesDeTrabajo"  = "OU=EstacionesDeTrabajo,OU=Clientes,$d"
    "OU EstacionesWS25"       = "OU=EstacionesWS25,OU=Clientes,$d"   
  }

  foreach ($name in $targets.Keys) {
    $t = $targets[$name]
    "===== $name ====="
    if (-not (Get-ADObject -LDAPFilter "(distinguishedName=$t)" -ErrorAction SilentlyContinue) -and $name -ne "DOMINIO") {
      "(!) No existe el target: $t"
      ""
      continue
    }

    $links = (Get-GPInheritance -Target $t).GpoLinks |
      Select-Object DisplayName,Enabled,Enforced

    if (-not $links) {
      "(sin links)"
      ""
      continue
    }

    # Muestra links no-default primero
    $links | Sort-Object @{Expression={ $_.DisplayName -like "Default*" }},DisplayName | Format-Table -AutoSize

    # Señala si hay algo NO default y Enabled=True (lo que NO debería pasar en staging)
    $unexpected = $links | Where-Object { $_.DisplayName -notlike "Default*" -and $_.Enabled }
    if ($unexpected) {
      "!! ATENCION: Links NO-default habilitados en ${name}:"
      $unexpected | Select DisplayName,Enabled,Enforced | Format-Table -AutoSize
    }

    ""
  }
}
