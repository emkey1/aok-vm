' AOK VM: Start menu entries for the programs INSTALL.CMD copies (they come as zips, with no installer).
Set sh = CreateObject("WScript.Shell")
progs = sh.SpecialFolders("AllUsersPrograms")
pf = sh.ExpandEnvironmentStrings("%ProgramFiles%")

Sub Lnk(name, target, args, dir)
    Set l = sh.CreateShortcut(progs & "\" & name & ".lnk")
    l.TargetPath = target
    l.Arguments = args
    l.WorkingDirectory = dir
    l.Save
    WScript.Echo "shortcut: " & name
End Sub

Lnk "OpenTTD", pf & "\OpenTTD\openttd.exe", "", pf & "\OpenTTD"
Lnk "Explorer++", pf & "\Explorer++\Explorer++.exe", "", pf & "\Explorer++"
Lnk "The Powder Toy", pf & "\The Powder Toy\Powder.exe", "", pf & "\The Powder Toy"
Lnk "Tiny C Compiler prompt", sh.ExpandEnvironmentStrings("%ComSpec%"), "/k path C:\tcc;%PATH%", sh.ExpandEnvironmentStrings("%USERPROFILE%")
