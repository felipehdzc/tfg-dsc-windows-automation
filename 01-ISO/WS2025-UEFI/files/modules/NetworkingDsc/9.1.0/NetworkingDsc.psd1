@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'NetworkingDsc.psm1'

    # Version number of this module.
    moduleVersion        = '9.1.0'

    # ID used to uniquely identify this module
    GUID                 = 'e6647cc3-ce9c-4c86-9eb8-2ee8919bf358'

    # Author of this module
    Author               = 'DSC Community'

    # Company or vendor of this module
    CompanyName          = 'DSC Community'

    # Copyright statement for this module
    Copyright            = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'DSC resources for configuring settings related to networking.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion    = '4.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion           = '4.0'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport    = @()

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport      = @()

    # DSC resources to export from this module
    DscResourcesToExport = @('DefaultGatewayAddress','DnsClientGlobalSetting','DnsClientNrptGlobal','DnsClientNrptRule','DnsConnectionSuffix','DnsServerAddress','Firewall','FirewallProfile','HostsFile','IPAddress','IPAddressOption','NetAdapterAdvancedProperty','NetAdapterBinding','NetAdapterLso','NetAdapterName','NetAdapterRdma','NetAdapterRsc','NetAdapterRss','NetAdapterState','NetBios','NetConnectionProfile','NetIPInterface','NetworkTeam','NetworkTeamInterface','ProxySettings','Route','WaitForNetworkTeam','WinsServerAddress','WinsSetting')

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{

        PSData = @{
            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease   = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/NetworkingDsc/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/NetworkingDsc'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [9.1.0] - 2025-05-09

### Changed

- Added the following resources:
  - **DnsClientNrptGlobal**: Configure DNS Client global Name Resolution Policy Table (NRPT) settings.
  - **DnsClientNrptRule**: Sets a DNS Client NRPT rule on a node.

- Updated CHANGELOG.md
  - Renamed NetworkingDSc to NetworkingDsc in CHANGELOG.md - fixes [Issue #513](https://github.com/dsccommunity/NetworkingDsc/issues/513).
- CI Pipeline
  - Updated pipeline files to match current DSC Community patterns - fixes [Issue #528](https://github.com/dsccommunity/NetworkingDsc/issues/528).
  - Updated HQRM and build steps to use windows-latest image.
  - Update build pipeline to pin GitVersion v5.
  - Added Server 2025 into Unit and Integration tests.
  - Remove duplicated pipeline steps and use matrix of VM images.
  - Use ModuleFast
  - Merge Unit test CodeCoverage
- Tests
  - Update to use Pester 5.
- `New-InvalidArgumentException` change to `New-ArgumentException` for HQRM.
- `NetworkingDsc.Common`
  - Changed to a buildable module.

### Fixed

- `DSC_Firewall`
  - Fixed comment typo.
  - Fixed `ParameterList` in `Set-TargetResource` typo.
  - Remove `DisplayGroup` property when creating new firewall rule.
  - `Test-RuleProperties`
    - Fixed `Convert-CIDRToSubnetMask` function call typo.

### Removed

- `Build.psd1`
  - Removed as not required.
- `DSC_IPAddress`
  - Remove IPv6 prefix length as unused.
- `CommonTestHelper`
  - Use `Get-InvalidArgumentRecord` from `DscResource.Test`.

'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}
