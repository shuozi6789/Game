@echo off
rem Open the project in the Godot editor.
cd /d "%~dp0"
if not exist "..\_tools\godot\Godot_v4.7.2-stable_win64.exe" (
  echo [ERROR] Godot engine not found at ..\_tools\godot\
  pause
  exit /b 1
)
start "" "..\_tools\godot\Godot_v4.7.2-stable_win64.exe" -e --path "%~dp0."
