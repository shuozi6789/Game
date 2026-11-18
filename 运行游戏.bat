@echo off
rem Launch the HD2D RPG prototype (Godot 4.7.2).
rem Engine binary lives outside the project, see README.md.
cd /d "%~dp0"
if not exist "..\_tools\godot\Godot_v4.7.2-stable_win64.exe" (
  echo [ERROR] Godot engine not found at ..\_tools\godot\
  echo         Run the setup steps in README.md first.
  pause
  exit /b 1
)
start "" "..\_tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
