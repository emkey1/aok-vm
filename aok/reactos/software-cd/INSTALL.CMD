@echo off
rem AOK VM: installs the programs on this CD one after another, with no questions and no network.
rem What each one did goes to C:\AOK-install.log.
set CD=%~dp0
set LOG=C:\AOK-install.log
set INNO=/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
echo Installing the programs on %CD% > %LOG%
echo Installing the programs on this CD. This takes a few minutes; windows may come and go.
echo.

call :run "7-Zip" "%CD%SETUP\7z2602.exe" /S
call :run "Notepad++" "%CD%SETUP\npp.6.9.Installer.exe" /S
call :run "SumatraPDF" "%CD%SETUP\SumatraPDF-3.1.2-install.exe" -s
call :run "AbiWord" "%CD%SETUP\abiword-setup-2.9.4.exe" /S
call :run "Media Player Classic" "%CD%SETUP\MPC-HC.1.7.13.x86.exe" %INNO%
call :msi "PuTTY" "%CD%SETUP\putty-0.83-installer.msi"
call :run "Mypal" "%CD%SETUP\mypal-29.3.0.win32.installer.exe" -ms
call :run "Tux Paint" "%CD%SETUP\tuxpaint-0.9.22-win32-installer.exe" %INNO%
call :run "LZDoom with Freedoom" "%CD%SETUP\lzdoom-installer.exe" /S
call :run "DOSBox" "%CD%SETUP\DOSBox0.74-3-win32-installer.exe" /S
call :msi "Python 3.4" "%CD%SETUP\python-3.4.4.msi" ALLUSERS=1
rem Mesa makes itself the OpenGL renderer: OpenGL 3.0 and Direct3D, which ReactOS draws through OpenGL.
call :run "Mesa 3D (OpenGL 3.0 on the CPU)" "%CD%SETUP\mesa3d_setup.exe" /S
call :copy "OpenTTD, with the OpenGFX graphics" "%CD%APPS\OpenTTD" "%ProgramFiles%\OpenTTD"
call :copy "Explorer++" "%CD%APPS\Explorer++" "%ProgramFiles%\Explorer++"
call :copy "The Powder Toy" "%CD%APPS\The Powder Toy" "%ProgramFiles%\The Powder Toy"
call :copy "Tiny C Compiler" "%CD%APPS\tcc" "C:\tcc"
echo Start menu entries for the last four
cscript //nologo "%CD%SHORTCUTS.VBS" >> %LOG% 2>&1
echo shortcuts: %errorlevel% >> %LOG%
rem Last, and not waited for: on ReactOS 0.4.16 its installer installs, then never exits.
call :nowait "WinSCP" "%CD%SETUP\winscp577setup.exe" %INNO%

echo Done >> %LOG%
echo.
echo Done. The programs are in the Start menu (Programs).
pause
goto :eof

:run
echo %~1
start "" /wait %2 %3 %4 %5 %6
echo %~1: %errorlevel% >> %LOG%
goto :eof

:nowait
echo %~1
start "" %2 %3 %4 %5 %6
echo %~1: started, not waited for >> %LOG%
goto :eof

:msi
echo %~1
start "" /wait msiexec /i %2 /qn %3
echo %~1: %errorlevel% >> %LOG%
goto :eof

:copy
echo %~1
xcopy /e /i /y /q %2 %3 > nul
echo %~1: %errorlevel% >> %LOG%
goto :eof
