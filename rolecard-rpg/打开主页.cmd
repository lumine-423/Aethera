@echo off
setlocal
set "GODOT_HOME_SAMPLE=D:\Godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_HOME_SAMPLE%" set "GODOT_HOME_SAMPLE=D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
start "" "%GODOT_HOME_SAMPLE%" --path "%~dp0" res://scenes/home.tscn
