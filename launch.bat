::hides the command prompts, making the terminal window flash less noticeably.
@echo off
::`cd /d` changes the current directory to that exact path
::"%~dp0" - path to the folder containing the batch file
cd /d "%~dp0"
::start	- Launches a program in a new, separate process.
::"" - This is a title placeholder for the new window (left empty).
::cmd /c - Opens a new Command Prompt and tells it to execute a command.
start "" cmd /c "code -r . & exit"
