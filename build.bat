@echo off
cls

::-o:none		//disable optimisations
odin build . -out:bin/gewuln.exe -debug -o:none

if ERRORLEVEL 1 (
	echo --compile:fail
	exit /B 1
)
echo --compile:success

call "bin/gewuln.exe"

exit /B 0
