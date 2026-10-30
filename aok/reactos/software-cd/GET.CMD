@echo off
rem AOK VM: "Get Programs" on ReactOS's desktop. Downloads the programs of the AOK programs CD (SOFTWARE.md) from
rem their makers' own sites with GETFILE.EXE, each checked against the SHA-1 in FILES.TXT, unpacks the four that
rem come as zips with 7-Zip, then installs them all with INSTALL.CMD, as the CD does. Needs the network once.
rem Downloads are kept here and not fetched again, so a second run continues where the first stopped. Log:
rem C:\AOK-get.log.
setlocal enabledelayedexpansion
title Get Programs
set HERE=%~dp0
set LOG=C:\AOK-get.log
echo Get Programs
echo.
echo This downloads 18 free, open-source programs (about 180 MB) from their makers'
echo own sites and installs them: 7-Zip, Notepad++, SumatraPDF, AbiWord, Media
echo Player Classic, PuTTY, WinSCP, the Mypal web browser, Tux Paint, LZDoom with
echo Freedoom, OpenTTD, DOSBox, Python, Explorer++, The Powder Toy, Tiny C Compiler
echo and Mesa's OpenGL. %HERE%README.TXT says more.
echo.
echo It needs the network, and takes a while. Press a key to start, or close this
echo window to leave it.
pause > nul
echo Getting the programs > %LOG%
md "%HERE%SETUP" 2> nul
md "%HERE%ZIPS" 2> nul
set FAILED=
for /f "usebackq eol=# tokens=1-4*" %%a in ("%HERE%FILES.TXT") do (
    set "KIND=%%a"
    set "SHA=%%b"
    set "NAME=%%c"
    set "URL=%%d"
    call :get
)
if defined FAILED (
    echo.
    echo Could not get:!FAILED!
    echo Is the network up? Run Get Programs again to try those again; what it has
    echo already is kept. C:\AOK-get.log says more.
    echo Could not get:!FAILED! >> %LOG%
    pause
    exit /b 1
)

echo.
echo Unpacking
start "" /wait "%HERE%SETUP\7z2602.exe" /S
for /f "usebackq eol=# tokens=1-4*" %%a in ("%HERE%FILES.TXT") do (
    if "%%a"=="zip" (
        "%ProgramFiles%\7-Zip\7z.exe" x -y -o"%HERE%APPS\%%e" "%HERE%ZIPS\%%c" > nul
        echo unpacked %%c: !errorlevel! >> %LOG%
    )
)
echo.
call "%HERE%INSTALL.CMD"
goto :eof

rem :get: NAME (KIND setup or zip) from URL, unless it is here already with the SHA-1 SHA (GETFILE.EXE, getfile.c)
:get
if "%KIND%"=="zip" (set "F=%HERE%ZIPS\%NAME%") else (set "F=%HERE%SETUP\%NAME%")
echo %NAME%
"%HERE%GETFILE.EXE" "!URL!" "!F!" %SHA%
if errorlevel 1 (
    set "FAILED=!FAILED! %NAME%"
    echo could not get %NAME% >> %LOG%
) else (
    echo have %NAME% >> %LOG%
)
goto :eof
