@echo off
cls

:: -o:none		//disable optimisations
:: `-vet` static analysis and additional checks at compile time to catch potential bugs and unsafe patterns in your code
odin build . -out:build/gewuln.exe -debug || (
	echo !!odin build failed
	exit /b 1
)

:: /S - Copies directories and subdirectories
:: /D - Copies only source files newer than destination files
:: /Y - Suppresses prompting to confirm you want to overwrite
:: /I - Assumes destination is a folder if it doesn't exist
xcopy "assets" "build\assets" /S /D /Y /I > nul 2>&1 || (
	echo !!failed to copy assets to build\assets
	exit /b 1
)

call "build/gewuln.exe"
