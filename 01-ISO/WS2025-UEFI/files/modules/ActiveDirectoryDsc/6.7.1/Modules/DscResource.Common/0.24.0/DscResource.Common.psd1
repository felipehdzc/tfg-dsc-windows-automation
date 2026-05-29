@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'DscResource.Common.psm1'

    # Version number of this module.
    ModuleVersion     = '0.24.0'

    # ID used to uniquely identify this module
    GUID              = '9c9daa5b-5c00-472d-a588-c96e8e498450'

    # Author of this module
    Author            = 'DSC Community'

    # Company or vendor of this module
    CompanyName       = 'DSC Community'

    # Copyright statement for this module
    Copyright         = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Common functions used in DSC Resources'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '4.0'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @('Assert-BoundParameter','Assert-ElevatedUser','Assert-IPAddress','Assert-Module','Compare-DscParameterState','Compare-ResourcePropertyState','ConvertFrom-DscResourceInstance','ConvertTo-CimInstance','ConvertTo-HashTable','Find-Certificate','Format-Path','Get-ComputerName','Get-DscProperty','Get-EnvironmentVariable','Get-FileProductVersion','Get-LocalizedData','Get-LocalizedDataForInvariantCulture','Get-PSModulePath','Get-RegistryPropertyValue','Get-TemporaryFolder','Get-UserName','New-ArgumentException','New-ErrorRecord','New-Exception','New-InvalidDataException','New-InvalidOperationException','New-InvalidResultException','New-NotImplementedException','New-ObjectNotFoundException','Remove-CommonParameter','Set-DscMachineRebootRequired','Set-PSModulePath','Test-AccountRequirePassword','Test-DscParameterState','Test-DscProperty','Test-IsNanoServer','Test-IsNumericType','Test-ModuleExist','Test-PendingRestart')

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport   = 'New-InvalidArgumentException'

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{

        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DSC', 'Localization')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/DscResource.Common/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/DscResource.Common'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [0.24.0] - 2025-08-26

### Added

- `Assert-BoundParameter`
  - Added parameter set `AtLeastOne` with parameter `AtLeastOneList` to
    validate that at least one parameter from a specified list is bound
    [#161](https://github.com/dsccommunity/DscResource.Common/issues/161).
  - Added parameter `IfEqualParameterList` to conditionally perform assertions
    only when specified parameters have exact values [#160](https://github.com/dsccommunity/DscResource.Common/issues/160).
- `Format-Path`
  - Added parameter `ExpandEnvironmentVariable` fixes [#147](https://github.com/dsccommunity/DscResource.Common/issues/147).
  - Added support to `Compare-DscParameterState` for comparing large hashtables
    that contain lists of elements.

### Changed

- `Get-ComputerName`
  - Replaced platform-specific logic with cross-platform implementation using 
    `[System.Environment]::MachineName` for consistent short name behavior.
  - Enhanced FQDN functionality to use `[System.Net.Dns]::GetHostByName()` for 
    proper domain name resolution on Windows, Linux, and macOS.
  - Improved error handling to gracefully fallback to short name when DNS 
    resolution fails.

'

            Prerelease   = ''
        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
