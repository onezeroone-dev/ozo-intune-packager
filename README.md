# OZO Intune Packager

## Overview

### The Problem

Packaging applications for Intune can be a giant headache. On the surface it seems simple: Wrap an installer using the `IntuneWinAppUtil.exe` utility; provide silent installation and uninstallation commands; provide a detection method; and call it a day, right? *However*:

- It's actually many more steps than that and there's plenty of room for human error.
- Your installer might be an MSI, or an EXE, or even a CMD/BAT. Intune handles MSI packages differently, and they can use the "MSI" detection method while everything else uses the "Registry" or "File" detection methods.
- The uninstaller might be the same as the installer, or it might be a completely different executable that is either included in the Intune package or found on the local disk *after* the installation finishes e.g., `C:\Program Files\...\uninstall.exe`.
- Your installer might be an EXE but the uninstall command is something like `msiexec.exe /x {SOME-LONG-MSI-CODE} /quiet /qn`.
- The installer might write to keys in the 32-bit or 64-bit registry, or might not write keys to the registry at all! This can make *detection* challenging.
- The registry keys might remain static from version-to-version, or they might change (looking at you *Oracle JRE* with your different MSI package string for each release...sheesh!).
- What if you want to run some additional CMD or PowerShell commands before or after installation or uninstallation?
- What if you need to include additional file assets like an MST transform?
- What if you need to redeploy an application without changing the version?

### The Solution

This script attempts to "normalize" application deployment with Intune. It creates `install.cmd` and `uninstall.cmd` wrapper scripts for your application, and packages them into an `.intunewin` along with the installer and any additional file assets you've placed in the application's `assetsDirectory`; and writes a predictable registry key-value-data entry that can be used to *detect* the installation\*. On the endpoint:

1. Intune downloads the `.intunewin` and extracts it to a temporary directory.
1. Intune opens a <a href="https://www.anoopcnair.com/intune-win32-app-deploy-system32-vs-syswow64" target="_blank">32-bit CMD shell</a> in the temporary directory and executes the "Install" command (`install.cmd`).
1. The `install.cmd` script:
    1. Looks for `preinstall.cmd` and if found, executes it.
    1. Looks for `preinstall.ps1` and if found, executes `powershell.exe -ExecutionPolicy RemoteSigned -File .\preinstall.ps1`
    1. Performs the installation.
    1. Looks for `icons.cmd` and if found, executes it.
    1. Looks for `postinstall.cmd` and if found, executes it.
    1. Looks for `postinstall.ps1` and if found, executes `powershell.exe -ExecutionPolicy RemoteSigned -File .\postinstall.ps1`
    1. If all of the above is successful, it writes a value *name* containing data *version-deployment* to a custom key in the 64-bit registry.

\*If an application is uninstalled *manually* but the custom key-value-data entry is *not* removed, Intune will continue to evaluate the application as *installed*. Uninstallations should be managed through Intune (with `uninstall.cmd`), and/or care should be taken to delete the registry value when performing a manual uninstallation.

## The Configuration File

The configuration file is JSON so backslashes ("\\") and other special characters must be escaped, e.g., `C:\\Program Files\\` instead of `C:\Program Files\`.

### Global Configuration

The script requires the following:

|Element|Description|Example Value|
|-------|-----------|-------------|
|`desktopIconsDirectory`|The location of the "All Users" desktop directory where applications often place icon files.|`C:\\Users\\Public\\Desktop`|
|`enableFIPSBugMitigation`|The Intune Content Prep Tool will fail on systems with FIPS mode enabled due to a bug. The registry key-value pairs that correspond with enabling FIPS mode ("1") will be temporarily changed to "0" when this is *TRUE*.|`TRUE`|
|`msiexecPath`|The path to `msiexec.exe` on the endpoint.|`C:\\Windows\\System32\\msiexec.exe`|
|`intuneInstallBehavior`|Intune application *Program > Install behavior*|`System`|
|`intuneInstallCommand`|Intune application *Program > Install command*.|`install.cmd`|
|`intuneUninstallCommand`|Intune application *Program > Uninstall command*.|`uninstall.cmd`|
|`intuneOperatingSystemArchitecture`|Intune application *Requirements > Operating system architecture*.|`64-bit`|
|`intuneMinimumOperatingSystem`|Intune application *Requirements > Minimum operating system*.|`Windows 10 20H2`|
|`intuneDetectionRulesFormat`|Intune application *Detection > Rules format*.|`Manually configure detection rules`|
|`intuneDetectionRuleType`|Intune application *Detection > Rule type*.|`Registry`|
|`intuneDetectionKeyPath`|Intune application *Detection > Key Path*.|`HKEY_LOCAL_MACHINE\\SOFTWARE\\One Zero One\\Intune Packager`|
|`intuneDetectionMethod`|Intune application *Detection > Detection Method*.|`String comparison`|
|`intuneDetectionOperator`|Intune application *Detection > Operator format*.|`Equals`|
|`intuneWinAppUtilURL`|Download URL for the Intune Content Prep Tool.|`https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe`|
|`packagesDirectory`|The directory where `.intunewin` packages should be stored.|`C:\\Users\\Public\\Documents\\OZO Intune Packager\\Packages`|
|`assetsDirectory`|The directory containing per-package subdirectories of additional assets to be included in the `.intunewin` package|`C:\\Users\\Public\\Documents\\OZO Intune Packager\\Assets`|
|`templatesDirectory`|The directory where `install-template.cmd`, `uninstall-template.cmd`, and `icons-template.cmd` are found (may be a subdirectory of this Git repository). These files are copied to the temporary packaging directory and updated with values for the application being processed.|`C:\\Users\\Public\\Documents\\OZO Intune Packager\\Templates`|
|`workingDirectory`|A writable location on the local disk where application assets are temporarily gathered together and processed into an `.intunewin` file.|`C:\\Temp`|
|`applications`|This is a list of dictionaries containing application configurations.|`[{}, {}, {}, ...]` (See below)|

### Applications Configuration

How an application is processed is determined by the extension of the installer. MSI, EXE, CMD, and BAT are handled; all other extensions are ignored. Each application dictionary requires values for `name`, `enabled`, `version`, and `deployment`; and must have a `downloadURL` OR `installerPath` defined that ends with a supported extension. If `downloadURL` is defined, installerPath is ignored. Unused elements may be omitted.

    {
        "name":"",
        "shortName":"",
        "enabled":"TRUE|FALSE",
        "version":"",
        "deployment":"",
        "downloadURL":"",
        "installerPath":"",
        "installerArguments":"",
        "uninstallerPath":"",
        "uninstallerArguments":"",
        "assetsDirectory":"",
        "desktopIcons":[]
    }

#### MSI Applications

MSI applications installed by calling *`msiexec.exe /i [INSTALLER].msi /qn /quiet [installerArguments]`* and uninstalled by calling *`msiexec.exe /x [INSTALLER].msi /qn /quiet [uninstallerArguments]`*.

|Element|Required|Description|Example Value|
|-------|--------|-----------|-------------|
|`name`|Yes|The name of the application.|`7-Zip`|
|`shortName`|Yes|The application name in lower case with no spaces or special characters. This is used to create "safer" temporary directories.|`7zip`|
|`enabled`|Yes|TRUE or FALSE. Only enabled applications will be parsed.|`TRUE`|
|`version`|Yes|The application version.|`22.01`|
|`deployment`|Yes|Your deployment number e.g. "001" ... "002" ... etc. Set this to "000" for the first deployment of a new version of an application. This is useful when you need to redeploy the same version of an application.|`000`|
|`downloadURL` or `installerPath`|Yes|If `downloadURL` is specified, `installerPath` is ignored. If `installerPath` is specified, the file must exist.||
|`installerArguments`|No|Specify any *additional* installer arguments (script presumes `/i` to install with `/quiet /qn`).|`AllUsers=1`|
|`uninstallerArguments`|No|Specify any *additional* uninstaller arguments (script presumes `/x` to uninstall with `/quiet /qn`).|`REBOOT=ReallySuppress`|
|`uninstallerPath`|No|This element is not used in MSI deployments.||
|`assetsDirectory`|No|The path to a directory containing additional file assets that should be included in the `.intunewin` file.|`C:\\Users\\Public\\Documents\\OZO Intune Packager\\Assets\\gvim`|
|`desktopIcons`|No|A comma-delimited list of quoted icon file names relative to `desktopIconsDirectory` to delete after installation|`["gVim 9.0.lnk","gVim Easy 9.0.lnk","gVim Read only 9.0.lnk"]`|

#### EXE, CMD, and BAT Applications

EXE, CMD, and BAT application definitions are similar to MSI but also allow for an `unisntallerPath`. Applications are installed by calling `installerPath [installerArguments]` and uninstalled by calling `uninstallerPath [uninstallerArguments]` so it's possible for the installer and uninstaller to be different e.g., when the `.intunewin` package includes an `uninstall.exe`...or when the installer places an `uninstall.exe` in the application's Program Files folder during installation.

|Element|Required|Description|Example Value|
|-------|--------|-----------|-------------|
|`name`|Yes|The name of the application.|`7-Zip`|
|`shortName`|Yes|The application name in lower case with no spaces or special characters. This is used to create "safer" temporary directories.|`7zip`|
|`enabled`|Yes|TRUE or FALSE. Only enabled applications will be parsed.|`TRUE`|
|`version`|Yes|The application version.|`22.01`
|`deployment`|Yes|Your deployment number e.g. "001" ... "002" ... etc. Set this to "000" for the first deployment of a new version of an application. This is useful when you need to redeploy the same version of an application.|`000`|
|`downloadURL` or `installerPath`|Yes|If `downloadURL` is specified, `installerPath` is ignored. If `installerPath` is specified, the file must exist.||
|`uninstallerPath`|No|If specified, `uninstallerPath` may be relative (`uninstall.exe`) when the uninstaller is included in the `.intunewin` package or absolute (`C:\\Program Files\\...\\uninstall.exe`) when the uninstaller is placed on the local disk by the installer. If `uninstallerPath` is not specified, the script uses `installerPath` for uninstallation.|`C:\\Program Files\\Vim\\vim90\\uninstall-gui.exe`
|`installerArguments`|No|Specify the arguments required to perform a silent installation.|`/S`|
|`uninstallerArguments`|No|Specify the arguments required to perfrom a silent uninstallation.|`/S`|
|`assetsDirectory`|No|The path to a directory containing additional file assets that should be included in the `.intunewin` file.|`D:\Intune Assets\gvim`|
|`desktopIcons`|No|A comma-delimited list of quoted icon file names relative to `desktopIconsDirectory` to delete after installation|`["gVim 9.0.lnk","gVim Easy 9.0.lnk","gVim Read only 9.0.lnk"]`|

## How to Use this Script

1. Set all applications to `"enabled":"FALSE"`
1. Determine which applications have new versions and set `enabled`, `version`, `deployment`, and `downloadURL` or `installerPath`, and any other desired elements for that application in the configuration JSON file.
1. Run the script.
1. Upload `.intunewin` files to corresponding Intune application and make sure install command, uninstall command, and detection rules match what is provided in `results.txt`.
1. Use the information in `results.txt` to create a change management log entry.

## Running the Script

The script requires an *Administrator* PowerShell so it can manipulate the registry. It requires the path to a *JSON* configuration file. Usage:

`[Admin] PS> is-intune-packager.ps1 [[-Json] <string>] [-Cleanup]`

|Parameter|Description|
|---------|-----------|
|`-Json`|Path to a JSON configuration file. If omitted, the application uses `configuration.json` in the script directory.|
|`-Cleanup`|Using this switch will cause the script to delete the working directory after processing is complete.|

## Future Improvements
If the application is successfully packaged, perhaps we can use the PowerShell Intune module update the Intune application.
