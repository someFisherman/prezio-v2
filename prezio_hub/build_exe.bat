@echo off
echo Building PrezioHub.exe ...
pyinstaller --noconfirm --onefile --windowed --name "PrezioHub" --icon "prezio_hub.ico" --version-file "version_info.py" "prezio_hub.py"
if exist build rmdir /s /q build
if exist PrezioHub.spec del PrezioHub.spec
echo.
echo Done! PrezioHub.exe is in dist\
pause
