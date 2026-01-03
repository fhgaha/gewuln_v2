@echo off
cls

odin build . -out:bin/main.exe

if ERRORLEVEL 1 (
	@REM echo --compile:fail
	exit /B 1
)
@REM echo --compile:success

call "bin/main.exe"

exit /B 0
