Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = dir

Set sc1 = sh.CreateShortcut(fso.BuildPath(dir, "Visual Studio Code.lnk"))
sh.Run Chr(34) & sc1.TargetPath & Chr(34) & " " & sc1.Arguments, 0, False

Set sc2 = sh.CreateShortcut(fso.BuildPath(dir, "codeopen-cli.lnk"))
sh.Run Chr(34) & sc2.TargetPath & Chr(34) & " " & sc2.Arguments, 1, False