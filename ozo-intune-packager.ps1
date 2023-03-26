#Requires -RunAsAdministrator

# Usage:
# powershell.exe -ExecutionPolicy RemoteSigned -File "path\to\ozo-intune-packager.ps1" -Conf "path\to\configuration.json"

# command line parameters
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false,HelpMessage = "Configuration file. Defaults to the configuration.json file in the same directory as this script. Please see the documentation for more information.")][String]$Json = (Join-Path -Path (Split-Path -Path $myInvocation.MyCommand.Definition -Parent) -Child "configuration.json"),
    [Switch]$Cleanup
)

# Classes

class Configuration {
    [boolean]$jsonValidates = $true
    [boolean]$configurationValidates = $true
    [String]$resultsPath = $null
    [String]$workingDirectory = $null
    [PSCustomObject]$json = $null
    [Int]$applicationCounter = $null
    [System.Collections.ArrayList]$desktopIcons = @()
    [System.Collections.ArrayList]$validApplications = @()

    [void]Validate($Json) {
        # ensure our logging source is defined
        Try {
            Get-EventLog -LogName Application -Source "OZO Intune Packager"
        } Catch {
            New-EventLog -LogName Application -Source "OZO Intune Packager"
        }
        # log
        Write-OZOLog -Message ("Starting OZO Intune Packager using " + $Json + ".")
        # this method reads in the JSON configuration file and performs some high-level sanity checks before finally calling ParseApplications
        Try {
            # read in configuration JSON
            $this.json = Get-Content $Json | ConvertFrom-Json
            Write-OZOLog -Message "JSON validates."
        } Catch {
            # reading JSON failed; report
            $this.jsonValidates = $false
            Write-OZOLog -Level Error -Message "Invalid JSON."
        }
        If ($this.jsonValidates -eq $true) {
            # check that working directory is specified
            If ($null -eq $this.json.workingDirectory) {
                $this.configurationValidates = $false
                Write-OZOLog -Level Error -Message ("Working directory is not defined in " + $Json + ".")
            } Else {
                $this.workingDirectory = Join-Path -Path $this.json.workingDirectory -Child ((Get-Date -format "yyyyMMdd-HHmm") + "-ozo-intune-Packager")
                Write-OZOLog -Message ("Using " + $this.workingDirectory + " as working directory.")
            }
            # check that the templates directory exists
            If (Test-Path $this.json.templatesDirectory) {
                Write-OZOLog -Message ("Using " + $this.json.templatesDirectory + " for templates.")
            } Else {
                $this.configurationValidates = $false
                Write-OZOLog -Level Error -Message ("Templates directory " + $this.json.templatesDirectory + " is missing or inaccessible.")
            }
            # check that the output packages directory exists; create if missing
            If (-Not(Test-Path $this.json.packagesDirectory)) {
                New-Item -ItemType Directory -Path $this.json.packagesDirectory -Force
            }
            Write-OZOLog -Message ("Using " + $this.json.packagesDirectory + " to store Intune packages.")
            # check that the registry path is specified
            If ($null -eq $this.json.intuneDetectionKeyPath) {
                $this.configurationValidates = $false
                Write-OZOLog -Level Error -Message ("Registry path is not defined in " + $Json + ".")
            } Else {
                Write-OZOLog -Message ("Using " + $this.json.intuneDetectionKeyPath + " for registry keys.")
            }
            # create the path for file output
            $this.resultsPath = (Join-Path -Path $this.json.packagesDirectory -Child "Results" | Join-Path -Child ((Get-Date -format "yyyyMMdd-HHmm") + "-results.txt"))
            # check that the desktop icons directory is specified
            If ($null -eq $this.json.desktopIconsDirectory) {
                $this.configurationValidates = $false
                Write-OZOLog -Level Error -Message ("Desktop icons directory is not defined in " + $Json + ".")
            } Else {
                Write-OZOLog -Message ("Using " + $this.json.desktopIconsDirectory + " as desktop icons directory.")
            }
            # check that we can retrieve IntuneWinAppUtil.exe
            Try {
                Invoke-WebRequest $this.json.intuneWinAppUtilURL -DisableKeepAlive -UseBasicParsing -Method head
            } Catch {
                $this.configurationValidates = $false
                Write-OZOLog -Level Error -Message ("Cannot download " + $this.json.intuneWinAppUtilURL + ".")
            }
            If ($this.json.applications.Count -gt 0) {
                Write-OZOLog -Message ("Found " + $this.json.applications.Count.ToString() + " applications in " + $Json + "; parsing.")
                $this.ParseApplications()
            } Else {
                Write-OZOLog -Level Error -Message ("No applications found in " + $Json + "; aborting.")
            }
        }
    }

    [void]ParseApplications() {
        # this method iterates through the applications and:
        # (a) determines if all required properties are specified in the JSON configuration file,
        # (b) determines if the installer is a downloadURL or local installerPath and populates installerFile accordingly, and
        # (c) determines if the installation is from an MSI or EXE and configures installerCMD uninstallerCMD with appropriate values

        # iterate through the enabled applications and check that they are valid
        $this.applicationCounter = 1
        Foreach ($application in $this.json.applications) {
            # add a NoteProperty making valid=True
            $application | Add-Member -NotePropertyName "valid" -NotePropertyValue $true
            $application | Add-Member -NotePropertyName "installerFile" -NotePropertyValue $null
            $application | Add-Member -NotePropertyName "installerCMD" -NotePropertyValue $null
            $application | Add-Member -NotePropertyName "uninstallerCMD" -NotePropertyValue $null
            # determine if the name, shortName, enabled, version, deployment quintangle is specified; and that one of downloadURL or installerPath is specified
            If (($null -ne $application.name) -And ($null -ne $application.shortName) -And ($application.enabled -eq $true) -And ($null -ne $application.version) -And ($null -ne $application.deployment) -And (($null -ne $application.downloadURL) -Or ($null -ne $application.installerPath))) {
                # all required properties present; log and proceed
                Write-OZOLog -Message ("Validating " + $application.name + ".")
                # make sure successCodes is populated with at least one member, "0"
                If ($null -eq $application.successCodes) {
                    $application | Add-Member -NotePropertyName "successCodes" -NotePropertyValue 0
                }
                # determine if the installer is coming from downloadURL or installerPath
                If ($application.downloadURL.Length -gt 0) {
                    # downloadURL is specified, split it to get installerFile
                    $application.installerFile = Split-Path -Path $application.downloadURL -Leaf
                    # test that the URL will download
                    Try {
                        Invoke-WebRequest $application.downloadURL -DisableKeepAlive -UseBasicParsing -Method head
                    } Catch {
                        $application.valid = $false
                        Write-OZOLog -Level Error -Message ("Cannot download " + $application.downloadURL + ".")
                    }
                } Else {
                    # downloadURL is not specified, split installerPath to get installerFile
                    $application.installerFile = Split-Path -Path $application.installerPath -Leaf
                    # check that installer exists
                    If (-Not(Test-Path -Path $application.installerPath)) {
                        $application.valid = $false
                        Write-OZOLog -Level Error -Message ("Application " + $application.name + " installer " + $application.installerPath + " does not exist.")
                    }
                }
                # populate the remaining properties depending on MSI or not-MSI
                Switch ([System.IO.Path]::GetExtension($application.installerFile)) {
                    {$_ -eq ".msi"} {
                        # in the MSI case, msiexec.exe is the installer and uninstaller, and the MSI package is provided as an argument; set the installCMD to msiexec.exe
                        $application.installerCMD = $this.json.msiexecPath
                        # determine if any additional installation arguments have been specified
                        If ($null -ne $application.installerArguments){
                            # additional arguments are specified, prepend installerArguments with the required MSI arguments
                            $application.installerArguments = ("/i `"" + $application.installerFile + "`" /quiet /qn " + $application.installerArguments)
                        } Else {
                            # no additional arguments specified, populate installerArguments with the required MSI arguments
                            $application | Add-Member -NotePropertyName "installerArguments" -NotePropertyValue ("/i `"" + $application.installerFile + "`" /quiet /qn")
                        }
                        # set the uninstallCMD to msiexec.exe
                        $application.uninstallerCMD = $this.json.msiexecPath
                        # determine if any additional uninstallation arguments have been specified
                        If ($null -ne $application.uninstallerArguments){
                            # additional arguments are specified, prepend installerArguments with the required MSI arguments
                            $application.uninstallerArguments = ("/x `"" + $application.installerFile + "`" /quiet /qn " + $application.uninstallerArguments)
                        } Else {
                            # no additional arguments specified, populate installerArguments with the required MSI arguments
                            $application | Add-Member -NotePropertyName "uninstallerArguments" -NotePropertyValue ("/x `"" + $application.installerFile + "`" /quiet /qn")
                        } 
                    }
                    {$_ -eq ".exe" -Or $_ -eq ".cmd" -Or $_ -eq ".bat"} {
                        # in the EXE, CMD, and BAT cases, the installer command is installerFile, but the uninstaller could be different: e.g., an [included] relative file path (SupportAssist_Uninstall.ps1) or a local file absolute file path provided by the installer (C:\Program Files\...\uninstall.exe)
                        $application.installerCMD = $application.installerFile
                        # check if installer arguments are specified; warn if missing
                        If ($null -eq $application.installerArguments) { Write-OZOLog -Level Warning -Message ("Application " + $application.name + " does not have any installerArguments specified.")}
                        # check if uninstallerPath specified
                        If ($null -ne $application.uninstallerPath) {
                            # uninstallerPath is specified, assign it to be the uninstallerCMD
                            $application.uninstallerCMD = $application.uninstallerPath
                        } Else {
                            # uninstallerPath is not specified, so uninstallerCMD will be the same as installerCMD
                            $application.uninstallerCMD = $application.installerCMD
                        }
                        # check if uninstaller arguments are specified; warn if missing
                        If ($null -eq $application.uninstallerArguments) { Write-OZOLog -Level Warning -Message ("Application " + $application.name + " does not have any uninstallerArguments specified.")}
                    }
                    default {
                        $application.valid = $false
                        Write-OZOLog -Level Error -Message ("Application " + $application.installerFile + " is not handled. Extension must be .bat, .cmd, .exe, or .msi. Application will not validate.")
                    }
                }
                # check if installerCMD contains spaces
                If ($application.installerCMD -like "* *") {
                    # installerCMD has spaces, wrap it in quotes
                    $application.installerCMD = ("`"" + $application.installerCMD + "`"")
                }
                # check if uninstallerCMD contains spaces
                If ($application.uninstallerCMD -like "* *") {
                    # installerCMD has spaces, wrap it in quotes
                    $application.uninstallerCMD = ("`"" + $application.uninstallerCMD + "`"")
                }
                # iterate through desktopIcons and check that they are not absolute paths
                If ($application.desktopIcons.Count -gt 0) {
                    Write-OZOLog -Message ("Desktop icons specified for " + $application.name + ": " + ($application.desktopIcons -join ", "))
                    For ( $index = 0; $index -lt $application.desktopIcons.count; $index++)
                    {
                        If ([System.IO.Path]::IsPathRooted($application.desktopIcons[$index])) {
                            # icon path is absolute; log error
                            $application.valid = $false
                            Write-OZOLog -Level Error -Message ($application.desktopIcons[$index] + " is an absolute path. Specify only relative paths to desktop icons under " + $this.configuration.desktopIconsDirectory + ".")
                        } Else {
                            # icon path is relative; prepend with desktopIconsPath
                            Write-OZOLog -Message ($application.desktopIcons[$index] + " is an absolute path; including.")
                            $application.desktopIcons[$index] = "`"" + (Join-Path -Path $this.json.desktopIconsDirectory -Child $application.desktopIcons[$index]) + "`""
                        }
                    }
                } Else {
                    Write-OZOLog -Message ("No desktop icons specified for " + $application.name + ".")
                }
                # check if there an assets directory has been specified
                If ($null -ne $application.assetsDirectory) {
                    # assets directory has been specified; check that it exists
                    If (Test-Path $application.assetsDirectory) {
                        Write-OZOLog -Message ("Using " + $application.assetsDirectory + " for additional file assets for " + $application.name + ".")
                    } Else {
                        Write-OZOLog -Level Error -Message ("Application " + $application.name + " is configured to include additional file assets in " + $application.assetsDirectory + " however this directory can not be found.")
                    }
                }
                # add some values
                $application | Add-Member -NotePropertyName "packagingDirectory" -NotePropertyValue (Join-Path -Path $this.workingDirectory -Child ($application.shortName + "-" + $application.version + "-" + $application.deployment))
                $application | Add-Member -NotePropertyName "intunePackagePath" -NotePropertyValue (Join-Path -Path $this.json.packagesDirectory -Child ($application.shortName + "-" + $application.version + "-" + $application.deployment + ".intunewin"))
                If (Test-Path $application.intunePackagePath) {
                    $application.valid = $false
                    Write-OZOLog -Level Error -Message ("Application " + $application.name + " output file " + $application.intunePackagePath + " already exists; skipping.")
                }
                # if we make it this far and the application is still valid, add to validApplications; log
                If ($application.valid -eq $true) {
                    $this.validApplications.Add($application)
                    Write-OZOLog -Message ("Application " + $application.name + " version " + $application.version + " deployment " + $application.deployment + " validates.")
                } Else {
                    Write-OZOLog -Level Error -Message ("Application " + $application.name + " version " + $application.version + " deployment " + $application.deployment + " did not validate; see prior log entries for more information.") -WriteResults $this.resultsPath
                }
            } Else {
                $application.valid = $false
                Write-OZOLog -Level Warning -Message ("Application number " + $this.applicationCounter.ToString() + " is not enabled or missing one of name, shortName, version, or deployment; and downloadURL or installerPath. Skipping.")
            }
            $this.applicationCounter += 1
        }
    }
}

class Package {
    [boolean]$jobValidates = $true

    [void]Jobs($configuration,$cleanup) {
        Write-Host($configuration.resultsPath)
        # create the working directory
        Try {
            New-Item -ItemType Directory -Path $configuration.workingDirectory -ErrorAction SilentlyContinue
            Write-OZOLog -Message ("Created working directory " + $configuration.workingDirectory + ".")
            Try {
                # attempt to download the latest intuneWinAppUtil
                Start-BitsTransfer -Source $configuration.json.intuneWinAppUtilURL -Destination $configuration.workingDirectory
            } Catch {
                $this.jobValidates = $false
                Write-OZOLog -Level Error -Message ("Error downloading " + $configuration.json.intuneWinAppUtilURL + ".")
            }
        }
        Catch {
            # unable to create working directory
            $this.jobValidates = $false
            Write-OZOLog -Level Error -Message ("Unable to create working directory " + $configuration.workingDirectory + ".")
        }
        If ($this.jobValidates -eq $true) {
            $intuneWinAppUtil = Join-Path -Path $configuration.workingDirectory -Child (Split-Path -Path $configuration.json.intuneWinAppUtilURL -Leaf)
            $processedApplicationsCount = 0
            # iterate through valid applications and process
            ForEach ($application in $configuration.validApplications) {
                $application | Add-Member -NotePropertyName "packageSuccess" -NotePropertyValue $true
                $installCMDPath = Join-Path -Path $application.packagingDirectory -Child $configuration.json.intuneInstallCommand
                $uninstallCMDPath = Join-Path -Path $application.packagingDirectory -Child $configuration.json.intuneUninstallCommand
                $iconsCMDPath = Join-Path -Path $application.packagingDirectory -Child "icons.cmd"
                # create the application packaging subfolder; log
                New-Item -ItemType Directory -Path $application.packagingDirectory
                Write-OZOLog -Message ("Using " + $application.packagingDirectory + " to package " + $application.name + ".")
                # check if the installer comes downloadURL or installerPath
                If ($application.downloadURL.Length -gt 0) {
                    Start-BitsTransfer -Source $application.downloadURL -Destination $application.packagingDirectory
                    Write-OZOLog -Message ("Downloaded " + $application.downloadURL + " to " + $application.packagingDirectory + ".")
                } Else {
                    Copy-Item -Path $application.installerPath -Destination $application.packagingDirectory
                    Write-OZOLog -Message ("Copied " + $application.installerPath + " to " + $application.packagingDirectory + ".")
                }
                # copy install-template.cmd to packagingDirectory
                Copy-Item -Path (Join-Path -Path $configuration.json.templatesDirectory -Child "install-template.cmd") -Destination $installCMDPath
                # perform text processing on packagingDirectory/install.cmd
                (Get-Content $installCMDPath).Replace("APPNAME",$application.name) | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("INSTALLERCMD",$application.installerCMD) | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("INSTALLERARGUMENTS",$application.installerArguments) | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("SUCCESSCODES",$application.successCodes -Join ",") | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("KEYPATH",$configuration.json.intuneDetectionKeyPath) | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("VERSION",$application.version) | Set-Content $installCMDPath
                (Get-Content $installCMDPath).Replace("DEPLOYNUM",$application.deployment) | Set-Content $installCMDPath
                # check if desktopIcons has elements
                If ($application.desktopIcons.Count -ne 0) {
                    # at least one icon in the list; copy icons-template.cmd to packagingDirectory
                    Copy-Item -Path (Join-Path -Path $configuration.json.templatesDirectory -Child "icons-template.cmd") -Destination $iconsCMDPath
                    # perform text processing on icons.cmd
                    (Get-Content $iconsCMDPath).Replace("DESKTOPICONS",($application.desktopIcons -Join ",")) | Set-Content $iconsCMDPath
                }
                # copy uninstall-template.cmd to packagingDirectory
                Copy-Item -Path (Join-Path -Path $configuration.json.templatesDirectory -Child "uninstall-template.cmd") -Destination $uninstallCMDPath
                # perform text processing on packagingDirectory/uninstall.cmd
                (Get-Content $uninstallCMDPath).Replace("APPNAME",$application.name) | Set-Content $uninstallCMDPath
                (Get-Content $uninstallCMDPath).Replace("UNINSTALLERCMD",$application.uninstallerCMD) | Set-Content $uninstallCMDPath
                (Get-Content $uninstallCMDPath).Replace("UNINSTALLERARGUMENTS",$application.uninstallerArguments) | Set-Content $uninstallCMDPath
                (Get-Content $uninstallCMDPath).Replace("KEYPATH",$configuration.json.intuneDetectionKeyPath) | Set-Content $uninstallCMDPath
                # check if assetsPath is set for this application
                If ($null -ne $application.assetsDirectory) {
                    # assetsPath is set; copy the assets to the packagingDirectory
                    Copy-Item -Recurse -Path (Join-Path -Path $application.assetsDirectory -Child "*") -Destination $application.packagingDirectory
                    Write-OZOLog -Message ("Copied additional file assets for " + $application.name + " to " + $application.packagingDirectory + ".")
                }
                # store current FIPS registry values
                $regFipsEnabled = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled").Enabled
                $regFipsMDMEnabled = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "MDMEnabled").MDMEnabled
                # package does not exist; check if FIPS bug mitigation is needed
                If ($configuration.json.enableFIPSBugMitigation -eq $true) {
                    # mitigation needed; store current registry values    
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled" -Value 0 -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "MDMEnabled" -Value 0 -ErrorAction Stop
                }
                # create the package
                Try { 
                    Start-Process -FilePath "$intuneWinAppUtil" -ArgumentList ("-q -c `"" + $application.packagingDirectory + "`" -s `"" + $configuration.json.intuneInstallCommand + "`" -o `"" + $application.packagingDirectory + "`"") -NoNewWindow -Wait
                    Copy-Item -Path (Join-Path -Path $application.packagingDirectory -Child "install.intunewin") -Destination $application.intunePackagePath
                    $processedApplicationsCount += 1
                    Write-OZOLog -Message ("Created " + $application.intunePackagePath + ".")
                    Write-OZOLog -Message ("
------------------------------------------------------------
Details for " + $application.name + "
------------------------------------------------------------
Package                       : " + $application.intunePackagePath + "
Install command               : " + $configuration.json.intuneInstallCommand +"
Uninstall command             : " + $configuration.json.intuneUninstallCommand + "
Install behavior              : " + $configuration.json.intuneInstallBehavior + "
Operating system architecture : " + $configuration.json.intuneOperatingSystemArchitecture + "
Minimum operating system      : " + $configuration.json.intuneMinimumOperatingSystem + "
Rules format                  : " + $configuration.json.intuneDetectionRulesFormat + "
Rule type                     : " + $configuration.json.intuneDetectionRuleType + "
Key path                      : Computer\" + $configuration.json.intuneDetectionKeyPath + "
Value name                    : " + $application.name + "
Detection method              : " + $configuration.json.intuneDetectionMethod + "
Operator                      : " + $configuration.json.intuneDetectionOperator + "
Value                         : " + $application.version + "-" + $application.deployment + "
                    ") -WriteResults $configuration.resultsPath
                } Catch {
                    $application.packageSuccess=$false
                    Write-OZOLog -Level Error -Messsage ("Could not generate package for " + $application.name + ".")
                    Write-OZOLog -Message ("Errors processing " + $application.name + ". Please see the Application log for more information.") -WriteHost
                }
                # check if FIPS bug un-mitigation is needed
                If ($configuration.json.enableFIPSBugMitigation -eq $true) {
                    # un-mitigation needed; restore registry values
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "Enabled" -Value $regFipsEnabled -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -Name "MDMEnabled" -Value $regFipsMDMEnabled -ErrorAction Stop
                }
            }
            # cleanup
            If ($cleanup) {
                Remove-Item -Recurse -Force $configuration.workingDirectory
                Write-OZOLog -Message ("Wiped working directory " + $configuration.workingDirectory + ".")
            }
            # check how many applications were processed
            If ($processedApplicationsCount -eq $configuration.validApplications.Count) {
                # all applications processed
                Write-OZOLog -Message "All applications processed." -WriteHost
            } Else {
                # some application processed
                Write-OZOLog -Level Error -Message "Some applications processed." -WriteHost
            }
            # log advice with console output
            Write-OZOLog -Message ("See " + $configuration.resultsPath + " for individual applications status.") -WriteHost
            & notepad.exe $configuration.resultsPath
        }
    }
}
# Functions
Function Write-OZOLog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)][ValidateSet("Error", "Information", "FailureAudit", "SuccessAudit", "Warning")][String]$Level = "Information",
        [Parameter(Mandatory=$False)][Int]$EventID = 0000,
        [Parameter(Mandatory=$False)][Int16]$Category = 0,
        [Parameter(Mandatory=$True)][String]$Message,
        [Switch]$WriteHost,
        [Parameter(Mandatory=$False)][String]$WriteResults = "nope"
    )
    Write-EventLog -LogName Application -Source "OZO Intune Packager" -EventID $EventID -EntryType $Level -Category $Category -Message $Message
    If ($WriteHost -eq $true) {
        Write-Host("`r`n" + $Message + "`r`n")
    }
    If ("$WriteResults" -ne "nope") {
        If (-Not(Test-Path (Split-Path -Path $WriteResults -Parent))) {
            New-Item -ItemType Directory -Path (Split-Path -Path $WriteResults -Parent)
        }
        ($Message + "`r`n`r`n") | Out-File -Append -FilePath $WriteResults
    }
}

# MAIN
# create an instance of the Configuration class
$configuration = [Configuration]::new()
# validate the JSON and configuration elements
$configuration.Validate($Json)
# check that the configuration validates
If ($configuration.configurationValidates) {
    # configuration validates; call the Package method
    $packages = [Package]::new()
    $packages.Jobs($configuration,$Cleanup)
}
