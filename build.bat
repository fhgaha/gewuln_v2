@echo off
cls

:: -o:none		//disable optimisations
:: `-vet` static analysis and additional checks at compile time to catch potential bugs and unsafe patterns in your code
odin build . -out:bin/gewuln.exe -debug -o:none -vet

if ERRORLEVEL 1 (
	echo --compile:fail
	exit /B 1
)
echo --compile:success

call "bin/gewuln.exe"

exit /B 0
