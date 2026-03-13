@echo off
title Prezio PC Recorder
echo.
echo ====================================
echo   Prezio PC Recorder wird gestartet
echo ====================================
echo.
echo Installiere Abhaengigkeiten falls noetig...
pip install pyserial -q
echo.
python prezio_recorder.py
pause
