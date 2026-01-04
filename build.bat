@echo off
cls

odin build . -out:bin/ogewuln.exe -debug

if ERRORLEVEL 1 (
	echo --compile:fail
	exit /B 1
)
echo --compile:success

call "bin/ogewuln.exe"

exit /B 0
