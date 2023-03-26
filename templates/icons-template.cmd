@ECHO OFF

FOR %%I IN (DESKTOPICONS) DO (
    IF EXIST %%I (
        del /q %%I
    )
)
