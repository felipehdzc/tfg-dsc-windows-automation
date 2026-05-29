#Region '.\prefix.ps1' -1

using module .\Modules\DscResource.Base

# Import nested, 'DscResource.Common' module
$script:dscResourceCommonModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\DscResource.Common'
Import-Module -Name $script:dscResourceCommonModulePath

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'
#EndRegion '.\prefix.ps1' 8
#Region '.\Enum\1.Ensure.ps1' -1

enum Ensure
{
    Present
    Absent
}
#EndRegion '.\Enum\1.Ensure.ps1' 6
#Region '.\Classes\001.DnsServerReason.ps1' -1

<#
    .SYNOPSIS
        The reason a property of a DSC resource is not in desired state.

    .DESCRIPTION
        A DSC resource can have a read-only property `Reasons` that the compliance
        part (audit via Azure Policy) of Azure AutoManage Machine Configuration
        uses. The property Reasons holds an array of DnsServerReason. Each DnsServerReason
        explains why a property of a DSC resource is not in desired state.
#>

class DnsServerReason
{
    [DscProperty()]
    [System.String]
    $Code

    [DscProperty()]
    [System.String]
    $Phrase
}
#EndRegion '.\Classes\001.DnsServerReason.ps1' 22
#Region '.\Classes\012.ResourcePropertiesBase.ps1' -1

<#
    .SYNOPSIS
        A class with DSC properties that are equal for all class-based resources.

    .DESCRIPTION
       A class with DSC properties that are equal for all class-based resources.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use 'localhost'
        for the current node. Defaults to `'localhost'`.
#>

class ResourcePropertiesBase
{
    [DscProperty()]
    [System.String]
    $DnsServer = 'localhost'
}
#EndRegion '.\Classes\012.ResourcePropertiesBase.ps1' 19
#Region '.\Classes\015.DnsRecordBase.ps1' -1

<#
    .SYNOPSIS
        A DSC Resource for MS DNS Server that is not exposed to end users representing the common fields available to all resource records.

    .DESCRIPTION
        A DSC Resource for MS DNS Server that is not exposed to end users representing the common fields available to all resource records.

    .PARAMETER ZoneName
        Specifies the name of a DNS zone. (Key Parameter)

    .PARAMETER TimeToLive
        Specifies the TimeToLive value of the SRV record. Value must be in valid TimeSpan string format (i.e.: Days.Hours:Minutes:Seconds.Miliseconds or 30.23:59:59.999).

    .PARAMETER Ensure
        Whether the host record should be present or removed.
#>

class DnsRecordBase : ResourcePropertiesBase
{
    [DscProperty(Key)]
    [System.String]
    $ZoneName

    [DscProperty()]
    [System.String]
    $TimeToLive

    [DscProperty()]
    [Ensure]
    $Ensure = [Ensure]::Present

    # Hidden property to determine whether the class is a scoped version
    hidden [System.Boolean] $isScoped

    # Hidden property for holding localization strings
    hidden [System.Collections.Hashtable] $localizedData

    # Hidden method to integrate localized strings from classes up the inheritance stack
    hidden [void] SetLocalizedData()
    {
        # Create a list of the inherited class names
        $inheritedClasses = @(, $this.GetType().Name)
        $parentClass = $this.GetType().BaseType
        while ($parentClass -ne [System.Object])
        {
            $inheritedClasses += $parentClass.Name
            $parentClass = $parentClass.BaseType
        }

        $this.localizedData = @{}

        foreach ($className in $inheritedClasses)
        {

            try
            {
                $tmpData = Get-LocalizedData -DefaultUICulture 'en-US' -FileName $className -ErrorAction Stop

                # Append only previously unspecified keys in the localization data
                foreach ($key in $tmpData.Keys)
                {
                    if (-not $this.localizedData.ContainsKey($key))
                    {
                        $this.localizedData[$key] = $tmpData[$key]
                    }
                }
            }
            catch
            {
                if ($_.CategoryInfo.Category.ToString() -eq 'ObjectNotFound')
                {
                    Write-Warning -Message $_.Exception.Message
                }
                else
                {
                    throw $_
                }
            }
        }

        Write-Debug -Message ($this.localizedData | ConvertTo-JSON)
    }

    # Default constructor sets the $isScoped variable and loads the localization strings
    DnsRecordBase()
    {
        # Determine scope
        $this.isScoped = $this.PSObject.Properties.Name -contains 'ZoneScope'

        # Import the localization strings
        $this.SetLocalizedData()
    }

    #region Generic DSC methods -- DO NOT OVERRIDE

    [DnsRecordBase] Get()
    {
        Write-Verbose -Message ($this.localizedData.GettingDscResourceObject -f $this.GetType().Name)

        $dscResourceObject = $null

        $record = $this.GetResourceRecord()

        if ($null -eq $record)
        {
            Write-Verbose -Message $this.localizedData.RecordNotFound

            <#
                Create an object of the correct type (i.e.: the subclassed resource type)
                and set its values to those specified in the object, but set Ensure to Absent
            #>
            $dscResourceObject = [System.Activator]::CreateInstance($this.GetType())

            foreach ($propertyName in $this.PSObject.Properties.Name)
            {
                $dscResourceObject.$propertyName = $this.$propertyName
            }

            $dscResourceObject.Ensure = 'Absent'
        }
        else
        {
            Write-Verbose -Message $this.localizedData.RecordFound

            # Build an object reflecting the current state based on the record found
            $dscResourceObject = $this.NewDscResourceObjectFromRecord($record)
        }

        return $dscResourceObject
    }

    [void] Set()
    {
        # Initialize dns cmdlet Parameters for removing a record
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        # Accomodate for scoped records as well
        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = ($this.PSObject.Properties | Where-Object -FilterScript { $_.Name -eq 'ZoneScope' }).Value
        }

        $existingRecord = $this.GetResourceRecord()

        if ($this.Ensure -eq 'Present')
        {
            if ($null -ne $existingRecord)
            {
                $currentState = $this.Get() | ConvertFrom-DscResourceInstance
                $desiredState = $this | ConvertFrom-DscResourceInstance

                # Remove properties that have $null as the value
                @($desiredState.Keys) | ForEach-Object -Process {
                    if ($null -eq $desiredState[$_])
                    {
                        $desiredState.Remove($_)
                    }
                }

                # Returns all enforced properties not in desires state, or $null if all enforced properties are in desired state
                $propertiesNotInDesiredState = Compare-DscParameterState -CurrentValues $currentState -DesiredValues $desiredState -Properties $desiredState.Keys -IncludeValue

                if ($null -ne $propertiesNotInDesiredState)
                {
                    Write-Verbose -Message $this.localizedData.ModifyingExistingRecord

                    $this.ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
                }
            }
            else
            {
                Write-Verbose -Message ($this.localizedData.AddingNewRecord -f $this.GetType().Name)

                # Adding record
                $this.AddResourceRecord()
            }
        }
        elseif ($this.Ensure -eq 'Absent')
        {
            if ($null -ne $existingRecord)
            {
                Write-Verbose -Message $this.localizedData.RemovingExistingRecord

                # Removing existing record
                $existingRecord | Remove-DnsServerResourceRecord @dnsParameters -Force
            }
        }
    }

    [System.Boolean] Test()
    {
        $isInDesiredState = $true

        $currentState = $this.Get() | ConvertFrom-DscResourceInstance
        $desiredState = $this | ConvertFrom-DscResourceInstance

        if ($this.Ensure -eq 'Present')
        {
            if ($currentState.Ensure -eq 'Present')
            {
                # Remove properties that have $null as the value
                @($desiredState.Keys) | ForEach-Object -Process {
                    if ($null -eq $desiredState[$_])
                    {
                        $desiredState.Remove($_)
                    }
                }

                # Returns all enforced properties not in desires state, or $null if all enforced properties are in desired state
                $propertiesNotInDesiredState = Compare-DscParameterState -CurrentValues $currentState -DesiredValues $desiredState -Properties $desiredState.Keys -ExcludeProperties @('Ensure')

                if ($propertiesNotInDesiredState)
                {
                    $isInDesiredState = $false
                }
            }
            else
            {
                Write-Verbose -Message ($this.localizedData.PropertyIsNotInDesiredState -f 'Ensure', $desiredState['Ensure'], $currentState['Ensure'])

                $isInDesiredState = $false
            }
        }

        if ($this.Ensure -eq 'Absent')
        {
            if ($currentState['Ensure'] -eq 'Present')
            {
                Write-Verbose -Message ($this.localizedData.PropertyIsNotInDesiredState -f 'Ensure', $desiredState['Ensure'], $currentState['Ensure'])

                $isInDesiredState = $false
            }
        }

        if ($isInDesiredState)
        {
            Write-Verbose -Message $this.localizedData.ObjectInDesiredState
        }
        else
        {
            Write-Verbose -Message $this.localizedData.ObjectNotInDesiredState
        }

        return $isInDesiredState
    }

    #endregion

    #region Methods to override

    # Using the values supplied to $this, query the DNS server for a resource record and return it
    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        throw $this.localizedData.GetResourceRecordNotImplemented
    }

    # Add a resource record using the properties of this object.
    hidden [void] AddResourceRecord()
    {
        throw $this.localizedData.AddResourceRecordNotImplemented
    }

    <#
        Modifies a resource record using the properties of this object.

        The data in each hashtable will contain the following properties:

        - ActualType (System.RuntimeType)
        - ExpectedType (System.RuntimeType)
        - Property (String)
        - ExpectedValue (the property's type)
        - ActualValue (the property's type)
        - InDesiredState (System.Boolean)
    #>
    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        throw $this.localizedData.ModifyResourceRecordNotImplemented
    }

    # Given a resource record object, create an instance of this class with the appropriate data
    hidden [DnsRecordBase] NewDscResourceObjectFromRecord($record)
    {
        throw $this.localizedData.NewResourceObjectFromRecordNotImplemented
    }

    #endregion
}
#EndRegion '.\Classes\015.DnsRecordBase.ps1' 291
#Region '.\Classes\020.DnsRecordCname.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordCname DSC resource manages CNAME DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordCname DSC resource manages CNAME DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER Name
        Specifies the name of a DNS server resource record object. (Key Parameter)

    .PARAMETER HostNameAlias
        Specifies a a canonical name target for a CNAME record. This must be a fully qualified domain name (FQDN). (Key Parameter)
#>

[DscResource()]
class DnsRecordCname : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $Name

    [DscProperty(Key)]
    [System.String]
    $HostNameAlias

    DnsRecordCname()
    {
    }

    [DnsRecordCname] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'CNAME', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'CNAME'
            Name         = $this.Name
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            # Ensure that HostNameAlias we using for filtering contains precisely one dot at the end.
            $_.RecordData.HostNameAlias -eq $($this.HostNameAlias.Trim('.') + '.')
        }

        return $record
    }

    hidden [DnsRecordCname] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordCname] @{
            ZoneName      = $this.ZoneName
            Name          = $this.Name
            HostNameAlias = $this.HostNameAlias
            TimeToLive    = $record.TimeToLive.ToString()
            DnsServer     = $this.DnsServer
            Ensure        = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName      = $this.ZoneName
            ComputerName  = $this.DnsServer
            CNAME         = $true
            Name          = $this.Name
            HostNameAlias = $this.HostNameAlias
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'CNAME', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\020.DnsRecordCname.ps1' 139
#Region '.\Classes\020.DnsRecordPtr.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordPtr DSC resource manages PTR DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordPtr DSC resource manages PTR DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER IpAddress
        Specifies the IP address to which the record is associated (Can be either IPv4 or IPv6. (Key Parameter)

    .PARAMETER Name
        Specifies the FQDN of the host when you add a PTR resource record. (Key Parameter)

    .NOTES
        Reverse lookup zones do not support scopes, so there should be no DnsRecordPtrScoped subclass created.
#>

[DscResource()]
class DnsRecordPtr : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $IpAddress

    [DscProperty(Key)]
    [System.String]
    $Name

    hidden [System.String] $recordHostName

    DnsRecordPtr()
    {
    }

    [DnsRecordPtr] Get()
    {
        # Ensure $recordHostName is set
        $this.recordHostName = $this.getRecordHostName($this.IpAddress)

        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        # Ensure $recordHostName is set
        $this.recordHostName = $this.getRecordHostName($this.IpAddress)

        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        # Ensure $recordHostName is set
        $this.recordHostName = $this.getRecordHostName($this.IpAddress)

        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'Ptr', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'PTR'
            Name         = $this.recordHostName
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.RecordData.PtrDomainName -eq "$($this.Name)."
        }

        return $record
    }

    hidden [DnsRecordPtr] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordPtr] @{
            ZoneName   = $this.ZoneName
            IpAddress  = $this.IpAddress
            Name       = $this.Name
            TimeToLive = $record.TimeToLive.ToString()
            DnsServer  = $this.DnsServer
            Ensure     = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName      = $this.ZoneName
            ComputerName  = $this.DnsServer
            PTR           = $true
            Name          = $this.recordHostName
            PtrDomainName = $this.Name
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'PTR', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }

    # Take a compressed IPv6 string (i.e.: fd00::1) and expand it out to the full notation (i.e.: fd00:0000:0000:0000:0000:0000:0000:0001)
    hidden [System.String] expandIPv6String($string)
    {
        # Split the string on the colons
        $segments = [System.Collections.ArrayList]::new(($string -split ':'))

        # Determine how many segments need to be added to reach the 8 required
        $blankSegmentCount = 8 - $segments.count

        # Hold the expanded segments
        $newSegments = [System.Collections.ArrayList]::new()

        # Insert missing segments
        foreach ($segment in $segments)
        {
            if ([System.String]::IsNullOrEmpty($segment))
            {
                for ($i = 0; $i -le $blankSegmentCount; $i++)
                {
                    $newSegments.Add('0000')
                }
            }
            else
            {
                $newSegments.Add($segment)
            }
        }

        # Pad out all segments with leading zeros
        $paddedSegments = $newSegments | ForEach-Object {
            $_.PadLeft(4, '0')
        }
        return ($paddedSegments -join ':')
    }

    # Translate the IP address to the reverse notation used by the DNS server
    hidden [System.String] getReverseNotation([System.Net.IpAddress] $IPAddressObj)
    {
        $significantData = [System.Collections.ArrayList]::New()

        switch ($ipAddressObj.AddressFamily)
        {
            'InterNetwork'
            {
                $significantData.AddRange(($ipAddressObj.IPAddressToString -split '\.'))
                break
            }

            'InterNetworkV6'
            {
                # Get the hex values into an ArrayList
                $significantData.AddRange(($this.expandIPv6String($ipAddressObj.IPAddressToString) -replace ':', '' -split ''))
                break
            }
        }

        $significantData.Reverse()

        # The reverse lookup notation puts a '.' between each hex value
        return ($significantData -join '.').Trim('.')
    }

    # Determine the record host name
    hidden [System.String] getRecordHostName([System.String] $IPAddress)
    {
        Assert-IPAddress -Address $IPAddress
        $ipAddressObj = [System.Net.IpAddress] $IPAddress

        $reverseLookupAddressComponent = ''

        switch ($ipAddressObj.AddressFamily)
        {
            'InterNetwork'
            {
                if (-not $this.ZoneName.ToLower().EndsWith('.in-addr.arpa'))
                {
                    throw ($this.localizedData.NotAnIPv4Zone -f $this.ZoneName)
                }
                $reverseLookupAddressComponent = $this.ZoneName.Replace('.in-addr.arpa', '')
                break
            }

            'InterNetworkV6'
            {
                if (-not $this.ZoneName.ToLower().EndsWith('.ip6.arpa'))
                {
                    throw ($this.localizedData.NotAnIPv6Zone -f $this.ZoneName)
                }
                $reverseLookupAddressComponent = $this.ZoneName.Replace('.ip6.arpa', '')
                break
            }
        }

        $reverseNotation = $this.getReverseNotation($ipAddressObj)

        # Check to make sure that the ip address actually belongs in this zone
        if ($reverseNotation -notmatch "$($reverseLookupAddressComponent)`$")
        {
            throw $this.localizedData.WrongZone -f $ipAddressObj.IPAddressToString, $this.ZoneName
        }

        # Strip the zone name from the reversed IP using a regular expression
        $ptrRecordHostName = $reverseNotation -replace "\.$([System.Text.RegularExpressions.Regex]::Escape($reverseLookupAddressComponent))`$", ''

        return $ptrRecordHostName
    }
}
#EndRegion '.\Classes\020.DnsRecordPtr.ps1' 244
#Region '.\Classes\030.DnsRecordA.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordA DSC resource manages A DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordA DSC resource manages A DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER Name
        Specifies the name of a DNS server resource record object. (Key Parameter)

    .PARAMETER IPv4Address
        Specifies the IPv4 address of a host. (Key Parameter)
#>

[DscResource()]
class DnsRecordA : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $Name

    [DscProperty(Key)]
    [System.String]
    $IPv4Address

    DnsRecordA ()
    {
    }

    [DnsRecordA] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'A', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'A'
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }



        if ($this.Name -in '@', '.', $this.ZoneName)
        {
            # Using -Node switch parameter with Get-DnsServerResourceRecord if dealing with **same as parrent folder** record.
            $dnsParameters.Node = $true
        }
        else
        {
            # Using -Name parameter with Get-DnsServerResourceRecord if dealing with regular DNS A records.
            $dnsParameters.Name = $this.Name
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object {
            $_.RecordData.IPv4Address -eq $this.IPv4Address
        }

        return $record
    }

    hidden [DnsRecordA] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordA] @{
            ZoneName    = $this.ZoneName
            Name        = $this.Name
            IPv4Address = $this.IPv4Address
            TimeToLive  = $record.TimeToLive.ToString()
            DnsServer   = $this.DnsServer
            Ensure      = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            A            = $true
            Name         = $this.Name
            IPv4Address  = $this.IPv4Address
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'A', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\030.DnsRecordA.ps1' 150
#Region '.\Classes\030.DnsRecordAaaa.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordAaaa DSC resource manages AAAA DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordAaaa DSC resource manages AAAA DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER Name
        Specifies the name of a DNS server resource record object. (Key Parameter)

    .PARAMETER IPv6Address
        Specifies the IPv6 address of a host. (Key Parameter)
#>

[DscResource()]
class DnsRecordAaaa : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $Name

    [DscProperty(Key)]
    [System.String]
    $IPv6Address

    DnsRecordAaaa()
    {
    }

    [DnsRecordAaaa] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'Aaaa', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'AAAA'
            Name         = $this.Name
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.RecordData.IPv6Address -eq $this.IPv6Address
        }

        return $record
    }

    hidden [DnsRecordAaaa] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordAaaa] @{
            ZoneName    = $this.ZoneName
            Name        = $this.Name
            IPv6Address = $this.IPv6Address
            TimeToLive  = $record.TimeToLive.ToString()
            DnsServer   = $this.DnsServer
            Ensure      = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            AAAA         = $true
            Name         = $this.name
            IPv6Address  = $this.IPv6Address
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'AAAA', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\030.DnsRecordAaaa.ps1' 138
#Region '.\Classes\030.DnsRecordMx.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordMx DSC resource manages MX DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordMx DSC resource manages MX DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER EmailDomain
        Everything after the '@' in the email addresses supported by this mail exchanger. It must be a subdomain the zone or the zone itself. To specify all subdomains, use the '*' character (i.e.: *.contoso.com). (Key Parameter)

    .PARAMETER MailExchange
        FQDN of the server handling email for the specified email domain. When setting the value, this FQDN must resolve to an IP address and cannot reference a CNAME record. (Key Parameter)

    .PARAMETER Priority
        Specifies the priority for this MX record among other MX records that belong to the same email domain, where a lower value has a higher priority. (Mandatory Parameter)
#>

[DscResource()]
class DnsRecordMx : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $EmailDomain

    [DscProperty(Key)]
    [System.String]
    $MailExchange

    [DscProperty(Mandatory)]
    [System.UInt16]
    $Priority

    hidden [System.String] $recordName

    DnsRecordMx()
    {
    }

    [DnsRecordMx] Get()
    {
        $this.recordName = $this.getRecordName()
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        $this.recordName = $this.getRecordName()
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        $this.recordName = $this.getRecordName()
        return ([DnsRecordBase] $this).Test()
    }

    [System.String] getRecordName()
    {
        $aRecordName = $null
        $regexMatch = $this.EmailDomain | Select-String -Pattern "^((.*?)\.){0,1}$($this.ZoneName)`$"
        if ($null -eq $regexMatch)
        {
            throw ($this.localizedData.DomainZoneMismatch -f $this.EmailDomain, $this.ZoneName)
        }
        else
        {
            # Match group 2 contains the value in which we are interested.
            $aRecordName = $regexMatch.Matches.Groups[2].Value
            if ($aRecordName -eq '')
            {
                $aRecordName = '.'
            }
        }
        return $aRecordName
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'Mx', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'MX'
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $translatedRecordName = $this.getRecordName()
            if ($translatedRecordName -eq '.')
            {
                $translatedRecordName = '@'
            }
            $_.HostName -eq $translatedRecordName -and
            $_.RecordData.MailExchange -eq "$($this.MailExchange)."
        }

        <#
            It is technically possible, outside of this resource to have more than one record with the same target, but
            different priorities. So, although the idea of doing so is nonsensical, we have to ensure we are selecting
            only one record in this method. It doesn't matter which one.
        #>
        return $record | Select-Object -First 1
    }

    hidden [DnsRecordMx] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordMx] @{
            ZoneName     = $this.ZoneName
            EmailDomain  = $this.EmailDomain
            MailExchange = $this.MailExchange
            Priority     = $record.RecordData.Preference
            TimeToLive   = $record.TimeToLive.ToString()
            DnsServer    = $this.DnsServer
            Ensure       = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            MX           = $true
            Name         = $this.getRecordName()
            MailExchange = $this.MailExchange
            Preference   = $this.Priority
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'MX', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement

                'Priority'
                {
                    $newRecord.RecordData.Preference = $propertyToChange.ExpectedValue
                }

                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\030.DnsRecordMx.ps1' 188
#Region '.\Classes\030.DnsRecordNs.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordNs DSC resource manages NS DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordNs DSC resource manages NS DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER DomainName
        Specifies the fully qualified DNS domain name for which the NameServer is authoritative. It must be a subdomain the zone or the zone itself. To specify all subdomains, use the '*' character (i.e.: *.contoso.com). (Key Parameter)

    .PARAMETER NameServer
        Specifies the name server of a domain. This should be a fully qualified domain name, not an IP address (Key Parameter)
#>

[DscResource()]
class DnsRecordNs : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $DomainName

    [DscProperty(Key)]
    [System.String]
    $NameServer

    DnsRecordNs()
    {
    }

    [DnsRecordNs] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    [System.String] getRecordName()
    {
        $aRecordName = $null

        # Use regex matching to determine if the domain name provided is a subdomain of the ZoneName (ends in ZoneName).
        $regexMatch = $this.DomainName | Select-String -Pattern "^((.*?)\.){0,1}$($this.ZoneName)`$"

        if ($null -eq $regexMatch)
        {
            throw ($this.localizedData.DomainZoneMismatch -f $this.DomainName, $this.ZoneName)
        }
        else
        {
            # Match group 2 contains the value in which we are interested.
            $aRecordName = $regexMatch.Matches.Groups[2].Value
            if ($aRecordName -eq '')
            {
                $aRecordName = '.'
            }
        }
        return $aRecordName
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'Ns', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'NS'
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $translatedRecordName = $this.getRecordName()
            if ($translatedRecordName -eq '.')
            {
                $translatedRecordName = '@'
            }
            $_.HostName -eq $translatedRecordName -and
            $_.RecordData.NameServer -eq "$($this.NameServer)."
        }

        return $record
    }

    hidden [DnsRecordNs] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordNs] @{
            ZoneName   = $this.ZoneName
            DomainName = $this.DomainName
            NameServer = $this.NameServer
            TimeToLive = $record.TimeToLive.ToString()
            DnsServer  = $this.DnsServer
            Ensure     = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            NS           = $true
            Name         = $this.getRecordName()
            NameServer   = $this.NameServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'NS', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement

                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\030.DnsRecordNs.ps1' 167
#Region '.\Classes\030.DnsRecordSrv.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordSrv DSC resource manages SRV DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordSrv DSC resource manages SRV DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER SymbolicName
        Service name for the SRV record. eg: xmpp, ldap, etc. (Key Parameter)

    .PARAMETER Protocol
        Service transmission protocol ('TCP' or 'UDP') (Key Parameter)

    .PARAMETER Port
        The TCP or UDP port on which the service is found (Key Parameter)

    .PARAMETER Target
        Specifies the Target Hostname or IP Address. (Key Parameter)

    .PARAMETER Priority
        Specifies the Priority value of the SRV record. (Mandatory Parameter)

    .PARAMETER Weight
        Specifies the weight of the SRV record. (Mandatory Parameter)
#>

[DscResource()]
class DnsRecordSrv : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $SymbolicName

    [DscProperty(Key)]
    [ValidateSet('TCP', 'UDP')]
    [System.String]
    $Protocol

    [DscProperty(Key)]
    [ValidateRange(1, 65535)]
    [System.UInt16]
    $Port

    [DscProperty(Key)]
    [System.String]
    $Target

    [DscProperty(Mandatory)]
    [System.UInt16]
    $Priority

    [DscProperty(Mandatory)]
    [System.UInt16]
    $Weight

    hidden [System.String] getRecordHostName()
    {
        return $this.getRecordHostName($this.SymbolicName, $this.Protocol)
    }

    hidden [System.String] getRecordHostName($aSymbolicName, $aProtocol)
    {
        return "_$($aSymbolicName)._$($aProtocol)".ToLower()
    }

    DnsRecordSrv()
    {
    }

    [DnsRecordSrv] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        $recordHostName = $this.getRecordHostName()

        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f $recordHostName, $this.target, 'SRV', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            Name         = $recordHostName
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'SRV'
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.HostName -eq $recordHostName -and
            $_.RecordData.Port -eq $this.Port -and
            $_.RecordData.DomainName -eq "$($this.Target)."
        }

        return $record
    }

    hidden [DnsRecordSrv] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordSrv] @{
            ZoneName     = $this.ZoneName
            SymbolicName = $this.SymbolicName
            Protocol     = $this.Protocol.ToLower()
            Port         = $this.Port
            Target       = ($record.RecordData.DomainName).TrimEnd('.')
            Priority     = $record.RecordData.Priority
            Weight       = $record.RecordData.Weight
            TimeToLive   = $record.TimeToLive.ToString()
            DnsServer    = $this.DnsServer
            Ensure       = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $recordHostName = $this.getRecordHostName()

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            Name         = $recordHostName
            Srv          = $true
            DomainName   = $this.Target
            Port         = $this.Port
            Priority     = $this.Priority
            Weight       = $this.Weight
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'SRV', $recordHostName, $this.Target, $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $recordHostName = $this.getRecordHostName()

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'Priority'
                {
                    $newRecord.RecordData.Priority = $propertyToChange.ExpectedValue
                }

                'Weight'
                {
                    $newRecord.RecordData.Weight = $propertyToChange.ExpectedValue
                }

                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }
}
#EndRegion '.\Classes\030.DnsRecordSrv.ps1' 203
#Region '.\Classes\030.DnsRecordTxt.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordTxt DSC resource manages TXT DNS records against a specific zone on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordTxt DSC resource manages TXT DNS records against a specific zone on a Domain Name System (DNS) server.

    .PARAMETER Name
        Specifies the name of a DNS server resource record object.

    .PARAMETER DescriptiveText
        Specifies additional text to describe a resource record on a DNS server. It is limited to 254 characters per line.

    .NOTES
        About long and muli-lined DNS TXT records.

        Microsoft DNS Server generally supports creating long multi-line TXT DNS records.
        For example, using the DNS MMC snap-in (which directly utilizes the DNS API), you can create a record containing multiple lines.
        However, when saving such a record, all lines will be truncated to 140 characters.

        Using the Add-DnsServerResourceRecord cmdlet (PowerShell/WMI), you can create a single-line record up to 254 characters long.
        However, it is not possible to create a multi-line DNS TXT record, thereby increasing the maximum possible record length beyond 254 characters.

        There is also a method to create records using DNSCMD.EXE, but this approach does not support Scoped DNS TXT records.

        For more details, refer to:
        https://learn.microsoft.com/en-us/answers/questions/1189058/how-to-set-multiline-txt-fields-with-add-dnsserver

        Another Important Consideration:
        When attempting to retrieve the value of a multi-line TXT record using:
        ```Powershell
        (Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType TXT -Name $Name).RecordData.DescriptiveText
        ```
        only the first line is returned.
        To obtain the full multi-line record, you would need to use:
        ```Powershell
        Resolve-DnsName -Name $Name -Type TXT -Server $DnsServer
        ```
        then you would parse Strings[] parameter of returned object like `Strings[0], Strings[1]... etc`.

        Conclusion:
        Based on the above, this DSC resource only works with single-line DNS TXT records, limited to 254 characters maximum.

#>

[DscResource()]
class DnsRecordTxt : DnsRecordBase
{
    [DscProperty(Key)]
    [System.String]
    $Name

    [DscProperty(Key)]
    [System.String]
    $DescriptiveText

    DnsRecordTxt ()
    {
    }

    [DnsRecordTxt] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        Write-Verbose -Message ($this.localizedData.GettingDnsRecordMessage -f 'TXT', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
            RRType       = 'TXT'
            Name         = $this.Name
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        $record = Get-DnsServerResourceRecord @dnsParameters -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.RecordData.DescriptiveText -eq $this.DescriptiveText
        }

        return $record
    }

    hidden [DnsRecordTxt] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordTxt] @{
            ZoneName        = $this.ZoneName
            Name            = $this.Name
            DescriptiveText = $this.DescriptiveText
            TimeToLive      = $record.TimeToLive.ToString()
            DnsServer       = $this.DnsServer
            Ensure          = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        $dnsParameters = @{
            ZoneName        = $this.ZoneName
            ComputerName    = $this.DnsServer
            TXT             = $true
            Name            = $this.Name
            DescriptiveText = $this.DescriptiveText
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        if ($null -ne $this.TimeToLive)
        {
            $dnsParameters.Add('TimeToLive', $this.TimeToLive)
        }

        Write-Verbose -Message ($this.localizedData.CreatingDnsRecordMessage -f 'TXT', $this.ZoneName, $this.ZoneScope, $this.DnsServer)

        Add-DnsServerResourceRecord @dnsParameters
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        $dnsParameters = @{
            ZoneName     = $this.ZoneName
            ComputerName = $this.DnsServer
        }

        if ($this.isScoped)
        {
            $dnsParameters['ZoneScope'] = $this.ZoneScope
        }

        # Copy the existing record and modify values as appropriate
        $newRecord = [Microsoft.Management.Infrastructure.CimInstance]::new($existingRecord)

        foreach ($propertyToChange in $propertiesNotInDesiredState)
        {
            switch ($propertyToChange.Property)
            {
                # Key parameters will never be affected, so only include Mandatory and Optional values in the switch statement
                'TimeToLive'
                {
                    $newRecord.TimeToLive = [System.TimeSpan] $propertyToChange.ExpectedValue
                }

            }
        }

        Set-DnsServerResourceRecord @dnsParameters -OldInputObject $existingRecord -NewInputObject $newRecord -Verbose
    }

    # Called by ResourceBase class in Get() Set() and Test() methods to assert that all properties are valid.
    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        switch ($properties.keys)
        {
            'DescriptiveText'
            {
                if ($properties.DescriptiveText.Length -lt 1 -or $properties.DescriptiveText.Length -gt 254)
                {
                    $errorMessage = $this.localizedData.PropertyIsNotInValidRange -f 'DescriptiveText'
                    New-InvalidOperationException -Message $errorMessage
                }
            }
        }

    }
}
#EndRegion '.\Classes\030.DnsRecordTxt.ps1' 186
#Region '.\Classes\030.DnsServerCache.ps1' -1

<#
    .SYNOPSIS
        The DnsServerCache DSC resource manages cache settings on a Microsoft Domain
        Name System (DNS) server.

    .DESCRIPTION
        The DnsServerCache DSC resource manages cache settings on a Microsoft Domain
        Name System (DNS) server.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use `'localhost'`
        for the current node.

    .PARAMETER IgnorePolicies
        Specifies whether to ignore policies for this cache.

    .PARAMETER LockingPercent
        Specifies a percentage of the original Time to Live (TTL) value that caching
        can consume. Cache locking is configured as a percent value. For example, if
        the cache locking value is set to `50`, the DNS server does not overwrite a
        cached entry for half of the duration of the TTL. If the cache locking percent
        is set to `100` that means the DNS server will not overwrite cached entries
        for the entire duration of the TTL.

    .PARAMETER MaxKBSize
        Specifies the maximum size, in kilobytes, of the memory cache of a DNS server.
        If set to `0` there is no limit.

    .PARAMETER MaxNegativeTtl
        Specifies how long an entry that records a negative answer to a query remains
        stored in the DNS cache. Minimum value is `'00:00:01'` and maximum value is
        `'30.00:00:00'`

    .PARAMETER MaxTtl
        Specifies how long a record is saved in cache. Minimum value is `'00:00:00'`
        and maximum value is `'30.00:00:00'`. If the TimeSpan is set to `'00:00:00'`
        (0 seconds), the DNS server does not cache records.

    .PARAMETER EnablePollutionProtection
        Specifies whether DNS filters name service (NS) resource records that are
        cached. Valid values are False (`$false`), which caches all responses to name
        queries; and True (`$true`), which caches only the records that belong to the
        same DNS subtree.

        When you set this parameter value to False (`$false`), cache pollution
        protection is disabled. A DNS server caches the Host (A) record and all queried
        NS resources that are in the DNS server zone. In this case, DNS can also cache
        the NS record of an unauthorized DNS server. This event causes name resolution
        to fail or to be appropriated for subsequent queries in the specified domain.

        When you set the value for this parameter to True (`$true`), the DNS server
        enables cache pollution protection and ignores the Host (A) record. The DNS
        server performs a cache update query to resolve the address of the NS if the
        NS is outside the zone of the DNS server. The additional query minimally
        affects DNS server performance.

    .PARAMETER StoreEmptyAuthenticationResponse
        Specifies whether a DNS server stores empty authoritative responses in the
        cache (RFC-2308).

    .PARAMETER Reasons
        Returns the reason a property is not in desired state.
#>

[DscResource()]
class DnsServerCache : ResourceBase
{
    [DscProperty(Key)]
    [System.String]
    $DnsServer

    [DscProperty()]
    [Nullable[System.Boolean]]
    $IgnorePolicies

    [DscProperty()]
    [Nullable[System.UInt32]]
    $LockingPercent

    [DscProperty()]
    [Nullable[System.UInt32]]
    $MaxKBSize

    [DscProperty()]
    [System.String]
    $MaxNegativeTtl

    [DscProperty()]
    [System.String]
    $MaxTtl

    [DscProperty()]
    [Nullable[System.Boolean]]
    $EnablePollutionProtection

    [DscProperty()]
    [Nullable[System.Boolean]]
    $StoreEmptyAuthenticationResponse

    [DscProperty(NotConfigurable)]
    [DnsServerReason[]]
    $Reasons

    DnsServerCache() : base ($PSScriptRoot)
    {
        # These properties will not be enforced.
        $this.ExcludeDscProperties = @(
            'DnsServer'
        )
    }

    [DnsServerCache] Get()
    {
        # Call the base method to return the properties.
        return ([ResourceBase] $this).Get()
    }

    # Base method Get() call this method to get the current state as a Hashtable.
    [System.Collections.Hashtable] GetCurrentState([System.Collections.Hashtable] $properties)
    {
        $getParameters = @{
            ComputerName = $properties.DnsServer
        }

        $getCurrentStateResult = Get-DnsServerCache @getParameters

        $state = @{
            DnsServer                        = $properties.DnsServer
            IgnorePolicies                   = $getCurrentStateResult.IgnorePolicies
            LockingPercent                   = [System.UInt32] $getCurrentStateResult.LockingPercent
            MaxKBSize                        = [System.UInt32] $getCurrentStateResult.MaxKBSize
            MaxNegativeTtl                   = $getCurrentStateResult.MaxNegativeTtl
            MaxTtl                           = $getCurrentStateResult.MaxTtl
            EnablePollutionProtection        = $getCurrentStateResult.EnablePollutionProtection
            StoreEmptyAuthenticationResponse = $getCurrentStateResult.StoreEmptyAuthenticationResponse
        }

        return $state
    }

    [void] Set()
    {
        # Call the base method to enforce the properties.
        ([ResourceBase] $this).Set()
    }

    <#
        Base method Set() call this method with the properties that should be
        enforced and that are not in desired state.
    #>
    [void] Modify([System.Collections.Hashtable] $properties)
    {
        <#
            If the property 'EnablePollutionProtection' was present and not in desired state,
            then the property name must be change for the cmdlet Set-DnsServerCache. In the
            cmdlet Get-DnsServerCache the property name is 'EnablePollutionProtection', but
            in the cmdlet Set-DnsServerCache the parameter is 'PollutionProtection'.
        #>
        if ($properties.ContainsKey('EnablePollutionProtection'))
        {
            $properties['PollutionProtection'] = $properties.EnablePollutionProtection

            $properties.Remove('EnablePollutionProtection')
        }

        Set-DnsServerCache @properties
    }

    [System.Boolean] Test()
    {
        # Call the base method to test all of the properties that should be enforced.
        return ([ResourceBase] $this).Test()
    }

    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        if ($null -ne $properties.MaxNegativeTtl)
        {
            Assert-TimeSpan -PropertyName 'MaxNegativeTtl' -Value $properties.MaxNegativeTtl -Minimum '0.00:00:01' -Maximum '30.00:00:00'
        }

        if ($null -ne $properties.MaxTtl)
        {
            Assert-TimeSpan -PropertyName 'MaxTtl' -Value $properties.MaxTtl -Minimum '0.00:00:00' -Maximum '30.00:00:00'
        }
    }
}
#EndRegion '.\Classes\030.DnsServerCache.ps1' 188
#Region '.\Classes\030.DnsServerDsSetting.ps1' -1

<#
    .SYNOPSIS
        The DnsServerDsSetting DSC resource manages DNS Active Directory settings
        on a Microsoft Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsServerDsSetting DSC resource manages DNS Active Directory settings
        on a Microsoft Domain Name System (DNS) server.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use `'localhost'`
        for the current node.

    .PARAMETER DirectoryPartitionAutoEnlistInterval
        Specifies the interval, during which a DNS server tries to enlist itself
        in a DNS domain partition and DNS forest partition, if it is not already
        enlisted. We recommend that you limit this value to the range one hour to
        180 days, inclusive, but you can use any value. We recommend that you set
        the default value to one day. You must set the value 0 (zero) as a flag
        value for the default value. However, you can allow zero and treat it
        literally.

    .PARAMETER LazyUpdateInterval
        Specifies a value, in seconds, to determine how frequently the DNS server
        submits updates to the directory server without specifying the
        LDAP_SERVER_LAZY_COMMIT_OID control ([MS-ADTS] section 3.1.1.3.4.1.7) at
        the same time that it processes DNS dynamic update requests. We recommend
        that you limit this value to the range 0x00000000 to 0x0000003c. You must
        set the default value to 0x00000003. You must set the value zero to
        indicate that the DNS server does not specify the
        LDAP_SERVER_LAZY_COMMIT_OID control at the same time that it processes
        DNS dynamic update requests. For more information about
        LDAP_SERVER_LAZY_COMMIT_OID, see LDAP_SERVER_LAZY_COMMIT_OID control
        code. The LDAP_SERVER_LAZY_COMMIT_OID control instructs the DNS server
        to return the results of a directory service modification command after
        it is completed in memory but before it is committed to disk. In this
        way, the server can return results quickly and save data to disk without
        sacrificing performance. The DNS server must send this control only to
        the directory server that is attached to an LDAP update that the DNS
        server initiates in response to a DNS dynamic update request. If the
        value is nonzero, LDAP updates that occur during the processing of DNS
        dynamic update requests must not specify the LDAP_SERVER_LAZY_COMMIT_OID
        control if a period of less than DsLazyUpdateInterval seconds has passed
        since the last LDAP update that specifies this control. If a period that
        is greater than DsLazyUpdateInterval seconds passes, during which time
        the DNS server does not perform an LDAP update that specifies this
        control, the DNS server must specify this control on the next update.

    .PARAMETER MinimumBackgroundLoadThreads
        Specifies the minimum number of background threads that the DNS server
        uses to load zone data from the directory service. You must limit this
        value to the range 0x00000000 to 0x00000005, inclusive. You must set the
        default value to 0x00000001, and you must treat the value zero as a flag
        value for the default value.

    .PARAMETER PollingInterval
        Specifies how frequently the DNS server polls Active Directory Domain
        Services (AD DS) for changes in Active Directory-integrated zones. You
        must limit the value to the range 30 seconds to 3,600 seconds, inclusive.

    .PARAMETER RemoteReplicationDelay
        Specifies the minimum interval, in seconds, that the DNS server waits
        between the time that it determines that a single object has changed on
        a remote directory server, to the time that it tries to replicate a
        single object change. You must limit the value to the range 0x00000005
        to 0x00000E10, inclusive. You must set the default value to 0x0000001E,
        and you must treat the value zero as a flag value for the default value.

    .PARAMETER TombstoneInterval
        Specifies the amount of time that DNS keeps tombstoned records alive in
        Active Directory. We recommend that you limit this value to the range
        three days to eight weeks, inclusive, but you can set it to any value in
        the range 82 hours to 8 weeks. We recommend that you set the default
        value to 14 days and treat the value zero as a flag value for the
        default. However, you can allow the value zero and treat it literally.
        At 2:00 A.M. local time every day, the DNS server must search all
        directory service zones for nodes that have the Active Directory
        dnsTombstoned attribute set to True, and for a directory service
        EntombedTime (section 2.2.2.2.3.23 of MS-DNSP) value that is greater
        than previous directory service DSTombstoneInterval seconds. You must
        permanently delete all such nodes from the directory server.

    .PARAMETER Reasons
        Returns the reason a property is not in desired state.
#>

[DscResource()]
class DnsServerDsSetting : ResourceBase
{
    [DscProperty(Key)]
    [System.String]
    $DnsServer

    [DscProperty()]
    [System.String]
    $DirectoryPartitionAutoEnlistInterval

    [DscProperty()]
    [Nullable[System.UInt32]]
    $LazyUpdateInterval

    [DscProperty()]
    [Nullable[System.UInt32]]
    $MinimumBackgroundLoadThreads

    [DscProperty()]
    [System.String]
    $PollingInterval

    [DscProperty()]
    [Nullable[System.UInt32]]
    $RemoteReplicationDelay

    [DscProperty()]
    [System.String]
    $TombstoneInterval

    [DscProperty(NotConfigurable)]
    [DnsServerReason[]]
    $Reasons

    DnsServerDsSetting() : base ($PSScriptRoot)
    {
        # These properties will not be enforced.
        $this.ExcludeDscProperties = @(
            'DnsServer'
        )
    }

    [DnsServerDsSetting] Get()
    {
        # Call the base method to return the properties.
        return ([ResourceBase] $this).Get()
    }

    # Base method Get() call this method to get the current state as a Hashtable.
    [System.Collections.Hashtable] GetCurrentState([System.Collections.Hashtable] $properties)
    {
        $getParameters = @{
            ComputerName = $properties.DnsServer
        }

        $getCurrentStateResult = Get-DnsServerDsSetting @getParameters

        $state = @{
            DnsServer                            = $properties.DnsServer
            DirectoryPartitionAutoEnlistInterval = $getCurrentStateResult.DirectoryPartitionAutoEnlistInterval
            LazyUpdateInterval                   = [System.UInt32] $getCurrentStateResult.LazyUpdateInterval
            MinimumBackgroundLoadThreads         = [System.UInt32] $getCurrentStateResult.MinimumBackgroundLoadThreads
            PollingInterval                      = $getCurrentStateResult.PollingInterval
            RemoteReplicationDelay               = [System.UInt32] $getCurrentStateResult.RemoteReplicationDelay
            TombstoneInterval                    = $getCurrentStateResult.TombstoneInterval
        }

        return $state
    }

    [void] Set()
    {
        # Call the base method to enforce the properties.
        ([ResourceBase] $this).Set()
    }

    <#
        Base method Set() call this method with the properties that should be
        enforced and that are not in desired state.
    #>
    [void] Modify([System.Collections.Hashtable] $properties)
    {
        Set-DnsServerDsSetting @properties
    }

    [System.Boolean] Test()
    {
        # Call the base method to test all of the properties that should be enforced.
        return ([ResourceBase] $this).Test()
    }

    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        @(
            'DirectoryPartitionAutoEnlistInterval',
            'TombstoneInterval'
        ) | ForEach-Object -Process {

            # Only evaluate properties that have a value.
            if ($null -ne $properties.$_)
            {
                Assert-TimeSpan -PropertyName $_ -Value $properties.$_ -Minimum '0.00:00:00'
            }
        }
    }
}
#EndRegion '.\Classes\030.DnsServerDsSetting.ps1' 194
#Region '.\Classes\030.DnsServerEDns.ps1' -1

<#
    .SYNOPSIS
        The DnsServerEDns DSC resource manages _extension mechanisms for DNS (EDNS)_
        on a Microsoft Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsServerEDns DSC resource manages _extension mechanisms for DNS (EDNS)_
        on a Microsoft Domain Name System (DNS) server.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use `'localhost'`
        for the current node.

    .PARAMETER CacheTimeout
        Specifies the number of seconds that the DNS server caches EDNS information.

    .PARAMETER EnableProbes
        Specifies whether to enable the server to probe other servers to determine
        whether they support EDNS.

    .PARAMETER EnableReception
        Specifies whether the DNS server accepts queries that contain an EDNS record.

    .PARAMETER Reasons
        Returns the reason a property is not in desired state.
#>

[DscResource()]
class DnsServerEDns : ResourceBase
{
    [DscProperty(Key)]
    [System.String]
    $DnsServer

    [DscProperty()]
    [System.String]
    $CacheTimeout

    [DscProperty()]
    [Nullable[System.Boolean]]
    $EnableProbes

    [DscProperty()]
    [Nullable[System.Boolean]]
    $EnableReception

    [DscProperty(NotConfigurable)]
    [DnsServerReason[]]
    $Reasons

    DnsServerEDns() : base ($PSScriptRoot)
    {
        # These properties will not be enforced.
        $this.ExcludeDscProperties = @(
            'DnsServer'
        )
    }

    [DnsServerEDns] Get()
    {
        # Call the base method to return the properties.
        return ([ResourceBase] $this).Get()
    }

    # Base method Get() call this method to get the current state as a Hashtable.
    [System.Collections.Hashtable] GetCurrentState([System.Collections.Hashtable] $properties)
    {
        $getParameters = @{
            ComputerName = $properties.DnsServer
        }

        $getCurrentStateResult = Get-DnsServerEDns @getParameters

        $state = @{
            DnsServer       = $properties.DnsServer
            CacheTimeout    = $getCurrentStateResult.CacheTimeout
            EnableProbes    = $getCurrentStateResult.EnableProbes
            EnableReception = $getCurrentStateResult.EnableReception
        }

        return $state
    }

    [void] Set()
    {
        # Call the base method to enforce the properties.
        ([ResourceBase] $this).Set()
    }

    <#
        Base method Set() call this method with the properties that should be
        enforced and that are not in desired state.
    #>
    [void] Modify([System.Collections.Hashtable] $properties)
    {
        Set-DnsServerEDns @properties
    }

    [System.Boolean] Test()
    {
        # Call the base method to test all of the properties that should be enforced.
        return ([ResourceBase] $this).Test()
    }

    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        @(
            'CacheTimeout'
        ) | ForEach-Object -Process {
            # Only evaluate properties that have a value.
            if ($null -ne $properties.$_)
            {
                Assert-TimeSpan -PropertyName $_ -Value $properties.$_ -Minimum '0.00:00:00'
            }
        }
    }
}
#EndRegion '.\Classes\030.DnsServerEDns.ps1' 118
#Region '.\Classes\030.DnsServerRecursion.ps1' -1

<#
    .SYNOPSIS
        The DnsServerRecursion DSC resource manages recursion settings on a Microsoft
        Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsServerRecursion DSC resource manages recursion settings on a Microsoft
        Domain Name System (DNS) server. Recursion occurs when a DNS server queries
        other DNS servers on behalf of a requesting client, and then sends the answer
        back to the client.

        The property `SecureResponse` that can be set by the cmdlet `Set-DnsServerRecursion`
        changes the same value as `EnablePollutionProtection` in the resource _DnsServerCache_
        does. Use the property `EnablePollutionProtection` in the resource _DnsServerCache_
        to enforce pollution protection.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use `'localhost'`
        for the current node.

    .PARAMETER Enable
        Specifies whether the server enables recursion.

    .PARAMETER AdditionalTimeout
        Specifies the time interval, in seconds, that a DNS server waits as it uses
        recursion to get resource records from a remote DNS server. Valid values are
        in the range of `1` second to `15` seconds. See recommendation in the documentation
        of [Set-DnsServerRecursion](https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverrecursion).

    .PARAMETER RetryInterval
        Specifies elapsed seconds before a DNS server retries a recursive lookup.
        Valid values are in the range of `1` second to `15` seconds. The
        recommendation is that in general this value should not be change. However,
        under a few circumstances it can be considered changing the value. For
        example, if a DNS server contacts a remote DNS server over a slow link and
        retries the lookup before it gets a response, it could help to raise the
        retry interval to be slightly longer than the observed response time.
        See recommendation in the documentation of [Set-DnsServerRecursion](https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverrecursion).

    .PARAMETER Timeout
        Specifies the number of seconds that a DNS server waits before it stops
        trying to contact a remote server. The valid value is in the range of `1`
        second to `15` seconds. Recommendation is to increase this value when
        recursion occurs over a slow link. See recommendation in the documentation
        of [Set-DnsServerRecursion](https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverrecursion).

    .PARAMETER Reasons
        Returns the reason a property is not in desired state.

    .NOTES
        The cmdlet Set-DsnServerRecursion allows to set the value 0 (zero) for the
        properties AdditionalTimeout, RetryInterval, and Timeout, but setting the
        value 0 reverts the property to its respectively default value. The default
        value for the properties on Windows Server 2016 is 4 seconds for property
        AdditionalTimeout, 3 seconds for RetryInterval, and 8 seconds for property
        Timeout. If it was allowed to set 0 (zero) as the value in this resource
        for these properties then the state would never become in desired state.
#>

[DscResource()]
class DnsServerRecursion : ResourceBase
{
    [DscProperty(Key)]
    [System.String]
    $DnsServer

    [DscProperty()]
    [Nullable[System.Boolean]]
    $Enable

    [DscProperty()]
    [Nullable[System.UInt32]]
    $AdditionalTimeout

    [DscProperty()]
    [Nullable[System.UInt32]]
    $RetryInterval

    [DscProperty()]
    [Nullable[System.UInt32]]
    $Timeout

    [DscProperty(NotConfigurable)]
    [DnsServerReason[]]
    $Reasons

    DnsServerRecursion() : base ($PSScriptRoot)
    {
        # These properties will not be enforced.
        $this.ExcludeDscProperties = @(
            'DnsServer'
        )
    }

    [DnsServerRecursion] Get()
    {
        # Call the base method to return the properties.
        return ([ResourceBase] $this).Get()
    }

    # Base method Get() call this method to get the current state as a Hashtable.
    [System.Collections.Hashtable] GetCurrentState([System.Collections.Hashtable] $properties)
    {
        $getParameters = @{
            ComputerName = $properties.DnsServer
        }

        $getCurrentStateResult = Get-DnsServerRecursion @getParameters

        $state = @{
            DnsServer         = $properties.DnsServer
            Enable            = $getCurrentStateResult.Enable
            AdditionalTimeout = [System.UInt32] $getCurrentStateResult.AdditionalTimeout
            RetryInterval     = [System.UInt32] $getCurrentStateResult.RetryInterval
            Timeout           = [System.UInt32] $getCurrentStateResult.Timeout
        }

        return $state
    }

    [void] Set()
    {
        # Call the base method to enforce the properties.
        ([ResourceBase] $this).Set()
    }

    <#
        Base method Set() call this method with the properties that should be
        enforced and that are not in desired state.
    #>
    [void] Modify([System.Collections.Hashtable] $properties)
    {
        Set-DnsServerRecursion @properties
    }

    [System.Boolean] Test()
    {
        # Call the base method to test all of the properties that should be enforced.
        return ([ResourceBase] $this).Test()
    }

    # Called by the base method Set() and Test() to assert that all properties are valid.
    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        @(
            'AdditionalTimeout'
            'RetryInterval'
            'Timeout'
        ) | ForEach-Object -Process {
            $propertyValue = $properties.$_

            # Only evaluate properties that have a value.
            if ($null -ne $propertyValue -and $propertyValue -notin (1..15))
            {
                $errorMessage = $this.localizedData.PropertyIsNotInValidRange -f $_, $propertyValue

                New-InvalidOperationException -Message $errorMessage
            }
        }
    }
}
#EndRegion '.\Classes\030.DnsServerRecursion.ps1' 162
#Region '.\Classes\030.DnsServerScavenging.ps1' -1

<#
    .SYNOPSIS
        The DnsServerScavenging DSC resource manages scavenging on a Microsoft
        Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsServerScavenging DSC resource manages scavenging on a Microsoft
        Domain Name System (DNS) server.

    .PARAMETER DnsServer
        The host name of the Domain Name System (DNS) server, or use 'localhost'
        for the current node.

    .PARAMETER ScavengingState
        Specifies whether to Enable automatic scavenging of stale records.
        `ScavengingState` determines whether the DNS scavenging feature is enabled
        by default on newly created zones.

    .PARAMETER ScavengingInterval
        Specifies a length of time as a value that can be converted to a `[TimeSpan]`
        object. `ScavengingInterval` determines whether the scavenging feature for
        the DNS server is enabled and sets the number of hours between scavenging
        cycles. The value `0` disables scavenging for the DNS server. A setting
        greater than `0` enables scavenging for the server and sets the number of
        days, hours, minutes, and seconds (formatted as dd.hh:mm:ss) between
        scavenging cycles. The minimum value is 0. The maximum value is 365.00:00:00
        (1 year).

    .PARAMETER RefreshInterval
        Specifies the refresh interval as a value that can be converted to a `[TimeSpan]`
        object (formatted as dd.hh:mm:ss). During this interval, a DNS server can
        refresh a resource record that has a non-zero time stamp. Zones on the server
        inherit this value automatically. If a DNS server does not refresh a resource
        record that has a non-zero time stamp, the DNS server can remove that record
        during the next scavenging. Do not select a value smaller than the longest
        refresh period of a resource record registered in the zone. The minimum value
        is `0`. The maximum value is 365.00:00:00 (1 year).

    .PARAMETER NoRefreshInterval
        Specifies a length of time as a value that can be converted to a `[TimeSpan]`
        object (formatted as dd.hh:mm:ss). `NoRefreshInterval` sets a period of time
        in which no refreshes are accepted for dynamically updated records. Zones on
        the server inherit this value automatically. This value is the interval between
        the last update of a timestamp for a record and the earliest time when the
        timestamp can be refreshed. The minimum value is 0. The maximum value is
        365.00:00:00 (1 year).

    .PARAMETER LastScavengeTime
        The time when the last scavenging cycle was executed.

    .PARAMETER Reasons
        Returns the reason a property is not in desired state.
#>

[DscResource()]
class DnsServerScavenging : ResourceBase
{
    [DscProperty(Key)]
    [System.String]
    $DnsServer

    [DscProperty()]
    [Nullable[System.Boolean]]
    $ScavengingState

    [DscProperty()]
    [System.String]
    $ScavengingInterval

    [DscProperty()]
    [System.String]
    $RefreshInterval

    [DscProperty()]
    [System.String]
    $NoRefreshInterval

    [DscProperty(NotConfigurable)]
    [Nullable[System.DateTime]]
    $LastScavengeTime

    [DscProperty(NotConfigurable)]
    [DnsServerReason[]]
    $Reasons

    DnsServerScavenging() : base ($PSScriptRoot)
    {
        # These properties will not be enforced.
        $this.ExcludeDscProperties = @(
            'DnsServer'
        )
    }

    [DnsServerScavenging] Get()
    {
        # Call the base method to return the properties.
        return ([ResourceBase] $this).Get()
    }

    # Base method Get() call this method to get the current state as a Hashtable.
    [System.Collections.Hashtable] GetCurrentState([System.Collections.Hashtable] $properties)
    {
        $getParameters = @{
            ComputerName = $properties.DnsServer
        }

        $getCurrentStateResult = Get-DnsServerScavenging @getParameters

        $state = @{
            DnsServer          = $properties.DnsServer
            ScavengingState    = $getCurrentStateResult.ScavengingState
            ScavengingInterval = $getCurrentStateResult.ScavengingInterval
            RefreshInterval    = $getCurrentStateResult.RefreshInterval
            NoRefreshInterval  = $getCurrentStateResult.NoRefreshInterval
            LastScavengeTime   = $getCurrentStateResult.LastScavengeTime
        }

        return $state
    }

    [void] Set()
    {
        # Call the base method to enforce the properties.
        ([ResourceBase] $this).Set()
    }

    <#
        Base method Set() call this method with the properties that should be
        enforced and that are not in desired state.
    #>
    [void] Modify([System.Collections.Hashtable] $properties)
    {
        Set-DnsServerScavenging @properties
    }

    [System.Boolean] Test()
    {
        # Call the base method to test all of the properties that should be enforced.
        return ([ResourceBase] $this).Test()
    }

    hidden [void] AssertProperties([System.Collections.Hashtable] $properties)
    {
        @(
            'ScavengingInterval'
            'RefreshInterval'
            'NoRefreshInterval'
        ) | ForEach-Object -Process {

            # Only evaluate properties that have a value.
            if ($null -ne $properties.$_)
            {
                Assert-TimeSpan -PropertyName $_ -Value $properties.$_ -Maximum '365.00:00:00' -Minimum '0.00:00:00'
            }
        }
    }
}
#EndRegion '.\Classes\030.DnsServerScavenging.ps1' 158
#Region '.\Classes\040.DnsRecordAaaaScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordAaaaScoped DSC resource manages AAAA DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordAaaaScoped DSC resource manages AAAA DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordAaaaScoped : DnsRecordAaaa
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordAaaaScoped()
    {
    }

    [DnsRecordAaaaScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordAaaa] $this).GetResourceRecord()
    }

    hidden [DnsRecordAaaaScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordAaaaScoped] @{
            ZoneName    = $this.ZoneName
            ZoneScope   = $this.ZoneScope
            Name        = $this.Name
            IPv6Address = $this.IPv6Address
            TimeToLive  = $record.TimeToLive.ToString()
            DnsServer   = $this.DnsServer
            Ensure      = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordAaaa] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordAaaa] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordAaaaScoped.ps1' 68
#Region '.\Classes\040.DnsRecordAScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordAScoped DSC resource manages A DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordAScoped DSC resource manages A DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordAScoped : DnsRecordA
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordAScoped ()
    {
    }

    [DnsRecordAScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordA] $this).GetResourceRecord()
    }

    hidden [DnsRecordAScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordAScoped] @{
            ZoneName    = $this.ZoneName
            ZoneScope   = $this.ZoneScope
            Name        = $this.Name
            IPv4Address = $this.IPv4Address
            TimeToLive  = $record.TimeToLive.ToString()
            DnsServer   = $this.DnsServer
            Ensure      = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordA] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordA] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordAScoped.ps1' 68
#Region '.\Classes\040.DnsRecordCnameScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordCnameScoped DSC resource manages CNAME DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordCnameScoped DSC resource manages CNAME DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordCnameScoped : DnsRecordCname
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordCnameScoped()
    {
    }

    [DnsRecordCnameScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordCname] $this).GetResourceRecord()
    }

    hidden [DnsRecordCnameScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordCnameScoped] @{
            ZoneName      = $this.ZoneName
            ZoneScope     = $this.ZoneScope
            Name          = $this.Name
            HostNameAlias = $this.HostNameAlias
            TimeToLive    = $record.TimeToLive.ToString()
            DnsServer     = $this.DnsServer
            Ensure        = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordCname] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordCname] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordCnameScoped.ps1' 68
#Region '.\Classes\040.DnsRecordMxScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordMxScoped DSC resource manages MX DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordMxScoped DSC resource manages MX DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordMxScoped : DnsRecordMx
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordMxScoped()
    {
    }

    [DnsRecordMxScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordMx] $this).GetResourceRecord()
    }

    hidden [DnsRecordMxScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordMxScoped] @{
            ZoneName     = $this.ZoneName
            ZoneScope    = $this.ZoneScope
            EmailDomain  = $this.EmailDomain
            MailExchange = $this.MailExchange
            Priority     = $record.RecordData.Preference
            TimeToLive   = $record.TimeToLive.ToString()
            DnsServer    = $this.DnsServer
            Ensure       = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordMx] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordMx] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordMxScoped.ps1' 69
#Region '.\Classes\040.DnsRecordNsScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordNsScoped DSC resource manages NS DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordNsScoped DSC resource manages NS DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordNsScoped : DnsRecordNs
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordNsScoped()
    {
    }

    [DnsRecordNsScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordNs] $this).GetResourceRecord()
    }

    hidden [DnsRecordNsScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordNsScoped] @{
            ZoneName   = $this.ZoneName
            ZoneScope  = $this.ZoneScope
            DomainName = $this.DomainName
            NameServer = $this.NameServer
            TimeToLive = $record.TimeToLive.ToString()
            DnsServer  = $this.DnsServer
            Ensure     = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordNs] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordNs] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordNsScoped.ps1' 68
#Region '.\Classes\040.DnsRecordSrvScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordSrvScoped DSC resource manages SRV DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordSrvScoped DSC resource manages SRV DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordSrvScoped : DnsRecordSrv
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordSrvScoped()
    {
    }

    [DnsRecordSrvScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordSrv] $this).GetResourceRecord()
    }

    hidden [DnsRecordSrvScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordSrvScoped] @{
            ZoneName     = $this.ZoneName
            ZoneScope    = $this.ZoneScope
            SymbolicName = $this.SymbolicName
            Protocol     = $this.Protocol.ToLower()
            Port         = $this.Port
            Target       = ($record.RecordData.DomainName).TrimEnd('.')
            Priority     = $record.RecordData.Priority
            Weight       = $record.RecordData.Weight
            TimeToLive   = $record.TimeToLive.ToString()
            DnsServer    = $this.DnsServer
            Ensure       = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordSrv] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordSrv] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordSrvScoped.ps1' 72
#Region '.\Classes\040.DnsRecordTxtScoped.ps1' -1

<#
    .SYNOPSIS
        The DnsRecordTxtScoped DSC resource manages TXT DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .DESCRIPTION
        The DnsRecordTxtScoped DSC resource manages TXT DNS records against a specific zone and zone scope on a Domain Name System (DNS) server.

    .PARAMETER ZoneScope
        Specifies the name of a zone scope. (Key Parameter)
#>

[DscResource()]
class DnsRecordTxtScoped : DnsRecordTxt
{
    [DscProperty(Key)]
    [System.String]
    $ZoneScope

    DnsRecordTxtScoped ()
    {
    }

    [DnsRecordTxtScoped] Get()
    {
        return ([DnsRecordBase] $this).Get()
    }

    [void] Set()
    {
        ([DnsRecordBase] $this).Set()
    }

    [System.Boolean] Test()
    {
        return ([DnsRecordBase] $this).Test()
    }

    hidden [Microsoft.Management.Infrastructure.CimInstance] GetResourceRecord()
    {
        return ([DnsRecordTxt] $this).GetResourceRecord()
    }

    hidden [DnsRecordTxtScoped] NewDscResourceObjectFromRecord([Microsoft.Management.Infrastructure.CimInstance] $record)
    {
        $dscResourceObject = [DnsRecordTxtScoped] @{
            ZoneName        = $this.ZoneName
            ZoneScope       = $this.ZoneScope
            Name            = $this.Name
            DescriptiveText = $this.DescriptiveText
            TimeToLive      = $record.TimeToLive.ToString()
            DnsServer       = $this.DnsServer
            Ensure          = 'Present'
        }

        return $dscResourceObject
    }

    hidden [void] AddResourceRecord()
    {
        ([DnsRecordTxt] $this).AddResourceRecord()
    }

    hidden [void] ModifyResourceRecord([Microsoft.Management.Infrastructure.CimInstance] $existingRecord, [System.Collections.Hashtable[]] $propertiesNotInDesiredState)
    {
        ([DnsRecordTxt] $this).ModifyResourceRecord($existingRecord, $propertiesNotInDesiredState)
    }
}
#EndRegion '.\Classes\040.DnsRecordTxtScoped.ps1' 68
#Region '.\Private\Assert-TimeSpan.ps1' -1

<#
    .SYNOPSIS
        Assert that the value provided can be converted to a TimeSpan object.

    .PARAMETER Value
        The time value as a string that should be converted.
#>
function Assert-TimeSpan
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.String]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PropertyName,

        [Parameter()]
        [System.TimeSpan]
        $Maximum,

        [Parameter()]
        [System.TimeSpan]
        $Minimum
    )

    $timeSpanObject = $Value | ConvertTo-TimeSpan

    # If the conversion fails $null is returned.
    if ($null -eq $timeSpanObject)
    {
        $errorMessage = $script:localizedData.PropertyHasWrongFormat -f $PropertyName, $Value

        New-InvalidOperationException -Message $errorMessage
    }

    if ($PSBoundParameters.ContainsKey('Maximum') -and $timeSpanObject -gt $Maximum)
    {
        $errorMessage = $script:localizedData.TimeSpanExceedMaximumValue -f $PropertyName, $timeSpanObject.ToString(), $Maximum

        New-InvalidOperationException -Message $errorMessage
    }

    if ($PSBoundParameters.ContainsKey('Minimum') -and $timeSpanObject -lt $Minimum)
    {
        $errorMessage = $script:localizedData.TimeSpanBelowMinimumValue -f $PropertyName, $timeSpanObject.ToString(), $Minimum

        New-InvalidOperationException -Message $errorMessage
    }
}
#EndRegion '.\Private\Assert-TimeSpan.ps1' 54
#Region '.\Private\ConvertTo-TimeSpan.ps1' -1

<#
    .SYNOPSIS
        Converts a string value to a TimeSpan object.

    .PARAMETER Value
        The time value as a string that should be converted.

    .OUTPUTS
        Returns an TimeSpan object containing the converted value, or $null if
        conversion was not possible.
#>
function ConvertTo-TimeSpan
{
    [CmdletBinding()]
    [OutputType([System.TimeSpan])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.String]
        $Value
    )

    $timeSpan = New-TimeSpan

    if (-not [System.TimeSpan]::TryParse($Value, [ref] $timeSpan))
    {
        $timeSpan = $null
    }

    return $timeSpan
}
#EndRegion '.\Private\ConvertTo-TimeSpan.ps1' 32
