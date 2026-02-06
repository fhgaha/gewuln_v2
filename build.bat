@echo off
cls

:: -o:none		//disable optimisations
:: `-vet` static analysis and additional checks at compile time to catch potential bugs and unsafe patterns in your code
odin build . -out:build/gewuln.exe -debug && (
	:: /S - Copies directories and subdirectories
    :: /D - Copies only source files newer than destination files
    :: /Y - Suppresses prompting to confirm you want to overwrite
    :: /I - Assumes destination is a folder if it doesn't exist
	xcopy "assets" "build\assets" /S /D /Y /I > nul && (
		call "build/gewuln.exe"
	) || (
		echo !!failed to copy
		pause
	)
)
