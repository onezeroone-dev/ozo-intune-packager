@ECHO OFF
set DEPLOYMENT_SUCCESS="TRUE"
set PREINSTALL_CMD_SUCCESS="FALSE"
set PREINSTALL_PS1_SUCCESS="FALSE"
set INSTALL_SUCCESS="FALSE"
set ICONS_SUCCESS="FALSE"
set POSTINSTALL_CMD_SUCCESS="FALSE"
set POSTINSTALL_PS1_SUCCESSS="FALSE"
set REGISTRY_SUCCESS="FALSE"
set LEVEL="INFORMATION"
set MESSAGE="APPNAME deployment starting."
set ID=1
CALL :LOG

IF %DEPLOYMENT_SUCCESS%=="TRUE" (
    CALL :PREINSTALL_CMD
) ELSE (
    CALL :FINISH
    EXIT
)
IF %PREINSTALL_CMD_SUCCESS%=="TRUE" (
    CALL :PREINSTALL_PS1
) ELSE (
    CALL :FINISH
    EXIT
)
IF %PREINSTALL_PS1_SUCCESS%=="TRUE" (
    CALL :INSTALL
) ELSE (
    CALL :FINISH
    EXIT
)
IF %INSTALL_SUCCESS%=="TRUE" (
    CALL :ICONS
) ELSE (
    CALL :FINISH
    EXIT
)
IF %ICONS_SUCCESS%=="TRUE" (
    CALL :POSTINSTALL_CMD
) ELSE (
    CALL :FINISH
    EXIT
)
IF %POSTINSTALL_CMD_SUCCESS%=="TRUE" (
    CALL :POSTINSTALL_PS1
) ELSE (
    CALL :FINISH
    EXIT
)
IF %POSTINSTALL_PS1_SUCCESS%=="TRUE" (
    CALL :REGISTRY
) ELSE (
    CALL :FINISH
    EXIT
)
IF %REGISTRY_SUCCESS%=="TRUE" (
    CALL :FINISH
) ELSE (
    CALL :FINISH
    EXIT
)
EXIT

:LOG
eventcreate /l APPLICATION /t %LEVEL% /id %ID% /d %MESSAGE%
EXIT /B

:PREINSTALL_CMD
IF EXIST "preinstall.cmd" (
    cmd.exe /c preinstall.cmd
    IF %ERRORLEVEL%==0 (
        set PREINSTALL_CMD_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME preinstall.cmd succeeded."
        CALL :LOG
    ) ELSE (
        set PREINSTALL_CMD_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=2
        set MESSAGE="APPNAME preinstall.cmd failed."
        CALL :LOG
    )
) ELSE (
    set PREINSTALL_CMD_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no preinstall.cmd found."
    CALL :LOG
)
EXIT /B

:PREINSTALL_PS1
IF EXIST "preinstall.ps1" (
    powershell.exe -ExecutionPolicy RemoteSigned -File .\preinstall.ps1
    IF %ERRORLEVEL%==0 (
        set PREINSTALL_PS1_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME preinstall.ps1 succeeded."
        CALL :LOG
    ) ELSE (
        set PREINSTALL_PS1_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=3
        set MESSAGE="APPNAME preinstall.ps1 failed."
        CALL :LOG
    )
) ELSE (
    set PREINSTALL_PS1_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no preinstall.ps1 found."
    CALL :LOG
)
EXIT /B

:INSTALL
cmd /c INSTALLERCMD INSTALLERARGUMENTS
FOR %%G IN (SUCCESSCODES) DO (
    IF %ERRORLEVEL%==%%~G (
        set INSTALL_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME installation succeeded."
        CALL :LOG
    ) ELSE (
        set INSTALL_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=4
        set MESSAGE="APPNAME installation failed."
        CALL :LOG
    )
)

EXIT /B

:ICONS
IF EXIST "icons.cmd" (
    cmd.exe /c icons.cmd
    IF %ERRORLEVEL%==0 (
        set ICONS_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME desktop icons managed."
        CALL :LOG
    ) ELSE (
        set ICONS_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=5
        set MESSAGE="APPNAME error processing icons."
        CALL :LOG
    )
) ELSE (
    set ICONS_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no icons.cmd found."
    CALL :LOG
)
EXIT /B

:POSTINSTALL_CMD
IF EXIST "postinstall.cmd" (
    cmd.exe /c postinstall.cmd
    IF %ERRORLEVEL%==0 (
        set POSTINSTALL_CMD_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME postinstall.cmd succeeded."
    ) ELSE (
        set POSTINSTALL_CMD_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=6
        set MESSAGE="APPNAME postinstall.cmd failed."
        CALL :LOG
    )
) ELSE (
    set POSTINSTALL_CMD_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no postinstall.cmd found."
    CALL :LOG
)
EXIT /B

:POSTINSTALL_PS1
IF EXIST "postinstall.ps1" (
    powershell.exe -ExecutionPolicy RemoteSigned -File .\postinstall.ps1
    IF %ERRORLEVEL%==0 (
        set POSTINSTALL_PS1_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME postinstall.ps1 succeeded."
    ) ELSE (
        set POSTINSTALL_PS1_SUCCESS="FALSE"
        set DEPLOYMENT_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=7
        set MESSAGE="APPNAME postinstall.ps1 failed."
        CALL :LOG
    )
) ELSE (
    set POSTINSTALL_PS1_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no postinstall.ps1 found."
    CALL :LOG
)
EXIT /B

:REGISTRY
REG ADD "KEYPATH" /v "APPNAME" /t REG_SZ /d "VERSION-DEPLOYNUM" /f /reg:64
set REGISTRY_SUCCESS="TRUE"
set LEVEL="INFORMATION"
set ID=1
set MESSAGE="APPNAME registry key added."
CALL :LOG
EXIT /B

:FINISH
IF %DEPLOYMENT_SUCCESS%=="TRUE" (
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME deployment finished with success."
    CALL :LOG
    EXIT 0
) ELSE (
    set LEVEL="ERROR"
    set ID=%ID%
    set MESSAGE="APPNAME deployment finished with errors."
    CALL :LOG
    EXIT %ID%
)
EXIT
