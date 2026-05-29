@{
    # Script module or binary module file associated with this manifest.
    RootModule            = 'ActiveDirectoryDsc.psm1'

    # Version number of this module.
    moduleVersion        = '6.7.1'

    # ID used to uniquely identify this module
    GUID                 = '9FECD4F6-8F02-4707-99B3-539E940E9FF5'

    # Author of this module
    Author               = 'DSC Community'

    # Company or vendor of this module
    CompanyName          = 'DSC Community'

    # Copyright statement for this module
    Copyright            = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'The ActiveDirectoryDsc module contains DSC resources for deployment and configuration of Active Directory.

    These DSC resources allow you to configure new domains, child domains, and high availability domain controllers, establish cross-domain trusts and manage users, groups and OUs.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion    = '5.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion           = '4.0'

    # Nested modules to load when this module is imported.
    NestedModules        = 'Modules\ActiveDirectoryDsc.Common\ActiveDirectoryDsc.Common.psm1'

    # Functions to export from this module
    FunctionsToExport    = @(
      # Exported so that WaitForADDomain can use this function in a separate scope.
      'Find-DomainController'
    )

    # Cmdlets to export from this module
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module
    AliasesToExport      = @()

    # Dsc Resources to export from this module
    DscResourcesToExport = @('ADComputer','ADDomain','ADDomainController','ADDomainControllerProperties','ADDomainDefaultPasswordPolicy','ADDomainFunctionalLevel','ADDomainTrust','ADFineGrainedPasswordPolicy','ADForestFunctionalLevel','ADForestProperties','ADGroup','ADKDSKey','ADManagedServiceAccount','ADObjectEnabledState','ADObjectPermissionEntry','ADOptionalFeature','ADOrganizationalUnit','ADReadOnlyDomainControllerAccount','ADReplicationSite','ADReplicationSiteLink','ADReplicationSubnet','ADServicePrincipalName','ADUser','WaitForADDomain')

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/ActiveDirectoryDsc/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/ActiveDirectoryDsc'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [6.7.1] - 2025-12-05

### Added

- ADReadOnlyDomainControllerAccount
  - Added read-only value Enabled indicating whether a pre-staged account is Enabled or Disabled (Unoccupied).
- `ActiveDirectoryDsc`
  - Added strings.psd1 for HQRM compliance.
- `ADObjectPermissionEntry`
  - The "ObjectType" parameter now supports the display name of the object to which
    the access rule applies, in addition to the schema GUID.
    ([issue #744](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/744)).
  - The "InheritedObjectType" parameter now supports the display name of the object
    type that can inherit this access rule, in addition to the schema GUID.
    ([issue #744](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/744)).
- ADDomain
  - Skip LCM reboot signal if `SuppressReboot` parameter is set to `true`
    ([issue #742](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/742)).

### Removed

- All Resources
  - Removed about_*.help.txt from sources as these are now generated at build time.
- `ActiveDirectoryDsc.Common`
  - `Test-DscPropertyState` now provided by `DscResource.Common`.
  - `Compare-ResourcePropertyState` now provided by `DscResource.Common`.

### Changed

- `build.ps1`
  - Update to latest Sampler version.
- `Resolve-Dependency.ps1`
  - Update to latest Sampler version.
- `Resolve-Dependency.psd1`
  - Update to latest Sampler version.
  - Enable ModuleFast.
- `RequiredModules.psd1`
  - Add PlatyPS fixes [#714](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/714).
  - Indented.ScriptAnalyzerRules.
- `analyzersettings.psd1`
  - Update to latest dsccommunity version.
- `ActiveDirectory.psd1`
  - Fix formatting.
  - Clear DscResourcesToExport as this is overwritten by ModuleBuilder.
  - Add RootModule.
- `build.yaml`
  - Add doc generation.
  - Move module to buildModule directory.
  - Add wiki to release assets.
- `ActiveDirectoryDsc`
  - Migrate tests to Pester 5.
  - Add VSCode settings for Pester Extension.

### Fixed

- ADObjectPermissionEntry
  - Fixed Get-TargetResource to return valid ActiveDirectoryRights when ACE is absent.
- ADDomain
  - Report domain exists in `Get-TargetResource` during pending DC promotion reboot.
    ([issue #742](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/742)).
- ADDomainController
  - Check the operating system to see if it is a domain controller before locating the
    domain controller object.
    Fixes [issue #747](https://github.com/dsccommunity/ActiveDirectoryDsc/issues/747).
  - Updated documentation to reflect parameters that should not be used with UseExistingAccount.
  - Additional guards against null properties when getting DelegatedAdministratorAccountName.
- ActiveDirectoryDsc.Common
  - Removed operating system check from Get-DomainControllerObject and moved into ADDomainController above.

'

            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease   = ''
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}
