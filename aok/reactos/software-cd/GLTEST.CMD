@echo off
rem AOK VM: gl-test.sh's CD. With ReactOS's own OpenGL, then with Mesa's llvmpipe installed silently: wglgears
rem (renderer and frame rates to C:\gl-N.txt) and, when its installer is on the CD, LZDoom (its console to
rem C:\lz-N.txt), each for a while and then closed; the rest to C:\AOK-gl.log.
set CD=%~dp0
set LOG=C:\AOK-gl.log
copy /y "%CD%wglgears.exe" C:\ > nul
echo GL test > %LOG%
set LZ=
if exist "%CD%lzdoom-installer.exe" call :lzinstall
call :run 1
start "" /wait "%CD%mesa3d_setup.exe" /S
echo mesa3d_setup: %errorlevel% >> %LOG%
reg query "HKCU\Software\ReactOS\OpenGL" >> %LOG% 2>&1
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers" /s >> %LOG% 2>&1
call :run 2
echo Done >> %LOG%
goto :eof

:lzinstall
start "" /wait "%CD%lzdoom-installer.exe" /S
echo lzdoom-installer: %errorlevel% >> %LOG%
for /f "delims=" %%f in ('dir /s /b "%ProgramFiles%\lzdoom.exe"') do set LZ=%%f
echo lzdoom: %LZ% >> %LOG%
goto :eof

:run
echo wglgears %1 >> %LOG%
start "" cmd /c "C:\wglgears.exe -info > C:\gl-%1.txt 2>&1"
timeout /t 45 /nobreak > nul
taskkill /im wglgears.exe >> %LOG% 2>&1
timeout /t 5 /nobreak > nul
if "%LZ%"=="" goto :eof
echo lzdoom %1 >> %LOG%
start "" "%LZ%" -iwad freedoom2.wad +logfile C:\lz-%1.txt
timeout /t 75 /nobreak > nul
taskkill /f /im lzdoom.exe >> %LOG% 2>&1
timeout /t 5 /nobreak > nul
goto :eof
