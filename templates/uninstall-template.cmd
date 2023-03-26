@ECHO OFF
set REMOVAL_SUCCESS="TRUE"
set PREUNINSTALL_CMD_SUCCESS="FALSE"
set PREUNINSTALL_PS1_SUCCESS="FALSE"
set UNINSTALL_SUCCESS="FALSE"
set POSTUNINSTALL_CMD_SUCCESS="FALSE"
set POSTUNINSTALL_PS1_SUCCESSS="FALSE"
set REGISTRY_SUCCESS="FALSE"
set LEVEL="INFORMATION"
set MESSAGE="APPNAME removal starting."
set ID=1
CALL :LOG

IF %REMOVAL_SUCCESS%=="TRUE" (
    CALL :PREUNINSTALL_CMD
) ELSE (
    CALL :FINISH
    EXIT
)

IF %PREUNINSTALL_CMD_SUCCESS%=="TRUE" (
    CALL :PREUNINSTALL_PS1
) ELSE (
    CALL :FINISH
    EXIT
)
IF %PREUNINSTALL_PS1_SUCCESS%=="TRUE" (
    CALL :UNINSTALL
) ELSE (
    CALL :FINISH
    EXIT
)
IF %UNINSTALL_SUCCESS%=="TRUE" (
    CALL :POSTUNINSTALL_CMD
) ELSE (
    CALL :FINISH
    EXIT
)
IF %POSTUNINSTALL_CMD_SUCCESS%=="TRUE" (
    CALL :POSTUNINSTALL_PS1
) ELSE (
    CALL :FINISH
    EXIT
)
IF %POSTUNINSTALL_PS1_SUCCESS%=="TRUE" (
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

:PREUNINSTALL_CMD
IF EXIST "preuninstall.cmd" (
    cmd.exe /c preuninstall.cmd
    IF %ERRORLEVEL%==0 (
        set PREUNINSTALL_CMD_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME preuninstall.cmd succeeded."
        CALL :LOG
    ) ELSE (
        set PREUNINSTALL_CMD_SUCCESS="FALSE"
        set REMOVAL_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=2
        set MESSAGE="APPNAME preuninstall.cmd failed."
        CALL :LOG
    )
) ELSE (
    set PREUNINSTALL_CMD_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no preuninstall.cmd found."
    CALL :LOG
)
EXIT /B

:PREUNINSTALL_PS1
IF EXIST "preuninstall.ps1" (
    powershell.exe -ExecutionPolicy RemoteSigned -File .\preuninstall.ps1
    IF %ERRORLEVEL%==0 (
        set PREUNINSTALL_PS1_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME preuninstall.ps1 succeeded."
        CALL :LOG
    ) ELSE (
        set PREUNINSTALL_PS1_SUCCESS="FALSE"
        set REMOVAL_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=3
        set MESSAGE="APPNAME preuninstall.ps1 failed."
        CALL :LOG
    )
) ELSE (
    set PREUNINSTALL_PS1_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no preuninstall.ps1 found."
    CALL :LOG
)
EXIT /B

:UNINSTALL
cmd.exe /c UNINSTALLERCMD UNINSTALLERARGUMENTS
IF %ERRORLEVEL%==0 (
    set UNINSTALL_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME uninstallation succeeded."
    CALL :LOG
) ELSE (
    set UNINSTALL_SUCCESS="FALSE"
    set REMOVAL_SUCCESS="FALSE"
    set LEVEL="ERROR"
    set ID=4
    set MESSAGE="APPNAME uninstallation failed."
    CALL :LOG
)
EXIT /B

:POSTUNINSTALL_CMD
IF EXIST "postuninstall.cmd" (
    cmd.exe /c postuninstall.cmd
    IF %ERRORLEVEL%==0 (
        set POSTUNINSTALL_CMD_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME postuninstall.cmd succeeded."
    ) ELSE (
        set POSTUNINSTALL_CMD_SUCCESS="FALSE"
        set REMOVAL_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=6
        set MESSAGE="APPNAME postuninstall.cmd failed."
        CALL :LOG
    )
) ELSE (
    set POSTUNINSTALL_CMD_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no postuninstall.cmd found."
    CALL :LOG
)
EXIT /B

:POSTUNINSTALL_PS1
IF EXIST "postuninstall.ps1" (
    powershell.exe -ExecutionPolicy RemoteSigned -File .\postuninstall.ps1
    IF %ERRORLEVEL%==0 (
        set POSTUNINSTALL_PS1_SUCCESS="TRUE"
        set LEVEL="INFORMATION"
        set ID=1
        set MESSAGE="APPNAME postuninstall.ps1 succeeded."
    ) ELSE (
        set POSTUNINSTALL_PS1_SUCCESS="FALSE"
        set REMOVAL_SUCCESS="FALSE"
        set LEVEL="ERROR"
        set ID=7
        set MESSAGE="APPNAME postuninstall.ps1 failed."
        CALL :LOG
    )
) ELSE (
    set POSTUNINSTALL_PS1_SUCCESS="TRUE"
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME no postuninstall.ps1 found."
    CALL :LOG
)
EXIT /B

:REGISTRY
REG DELETE "KEYPATH" /v "APPNAME" /f /reg:64
set REGISTRY_SUCCESS="TRUE"
set LEVEL="INFORMATION"
set ID=1
set MESSAGE="APPNAME registry key deleted."
CALL :LOG
EXIT /B

:FINISH
IF %REMOVAL_SUCCESS%=="TRUE" (
    set LEVEL="INFORMATION"
    set ID=1
    set MESSAGE="APPNAME removal finished with success."
    CALL :LOG
    EXIT 0
) ELSE (
    set LEVEL="ERROR"
    set ID=%ID%
    set MESSAGE="APPNAME removal finished with errors."
    CALL :LOG
    EXIT %ID%
)
EXIT
