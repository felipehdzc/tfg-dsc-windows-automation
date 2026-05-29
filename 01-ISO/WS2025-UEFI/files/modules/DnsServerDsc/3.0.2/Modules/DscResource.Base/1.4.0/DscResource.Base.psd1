@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'DscResource.Base.psm1'

    # Version number of this module.
    ModuleVersion        = '1.4.0'

    # ID used to uniquely identify this module
    GUID                 = '693ee082-ed36-45a7-b490-88b07c86b42f'

    # Author of this module
    Author               = 'DSC Community'

    # Company or vendor of this module
    CompanyName          = 'DSC Community'

    # Copyright statement for this module
    Copyright            = 'Copyright the DSC Community contributors. All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'This module contains common classes that can be used for class-based DSC resources development.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion    = '5.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion           = '4.0'

    # Functions to export from this module
    FunctionsToExport    = @()

    # Cmdlets to export from this module
    CmdletsToExport      = @()

    # Variables to export from this module
    VariablesToExport    = @()

    # Aliases to export from this module
    AliasesToExport      = @()

    DscResourcesToExport = @()

    RequiredAssemblies   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData          = @{

        PSData = @{
            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease   = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('DesiredStateConfiguration', 'DSC', 'DSCResourceKit', 'DSCResource')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/DscResource.Base/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/DscResource.Base'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = '## [1.4.0] - 2025-05-24

### Removed

- Removed `Clear-ZeroedEnumPropertyValue` as it was moved and implemented
  the `Get-DscProperty` command in the _DscResource.Common_ module.

### Added

- Wiki
  - How to use this base class. Fixes [#5](https://github.com/dsccommunity/DscResource.Base/issues/5)
  and [#19](https://github.com/dsccommunity/DscResource.Base/issues/19).
  - Add WikiContent to release assets.

### Changed

- `ResourceBase`
  - Refactor `GetDesiredState` method to handle zeroed enum values using
    `Get-DscProperty` when the property `FeatureOptionalEnums` is set to
    `$true`.
  - Remove calls to `Assert()` and `Normalize()` in `Test()` and `Set()` fixes [#35](https://github.com/dsccommunity/DscResource.Base/issues/35).

### Fixed

- build.yaml
  - Add `Generate_Wiki_Content`, `Generate_Wiki_Sidebar`, `Clean_Markdown_Metadata`
docs tasks. Fixes [#32](https://github.com/dsccommunity/DscResource.Base/issues/32).
- `ResourceBase`
  - Add check for properties not being `$null` fixes [#30](https://github.com/dsccommunity/DscResource.Base/issues/30).
  - Comment typo''s.

'

        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
