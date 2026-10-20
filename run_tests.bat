@echo off
rem Runs every test: Python sim checks, then the Godot suite.
rem Set GODOT to your Godot *console* exe once, e.g.
rem   setx GODOT "C:\Tools\Godot\Godot_v4.5-stable_win64_console.exe"
rem Output is also saved to tests\last_run.txt.
rem The window waits for a key at the end. Pass --no-pause to skip that.
setlocal
cd /d "%~dp0"
if "%GODOT%"=="" set "GODOT=godot"

call :run > tests\last_run.txt 2>&1
set "RC=%errorlevel%"
type tests\last_run.txt
if not "%~1"=="--no-pause" pause
exit /b %RC%

:run
echo Godot exe: %GODOT%
echo.
echo == Python: sim, tables, golden shots
python tests\test_sim.py || goto :fail
echo.
echo == Godot: ball model, rules, playback, controls
"%GODOT%" --headless --path . --script res://tests/godot_tests.gd || goto :fail
echo.
echo ALL TESTS PASSED
exit /b 0

:fail
echo.
echo TESTS FAILED
exit /b 1
