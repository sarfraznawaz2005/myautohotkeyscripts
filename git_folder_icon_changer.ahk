#Requires AutoHotkey v2.0+
#SingleInstance Force

/*
global LOG_DEBUG := A_ScriptDir "\debug.log"

try FileDelete(LOG_DEBUG)

LogDebug(msg) {
    FileAppend(Format("[{1}] DEBUG: {2}`r`n", A_Now, msg), LOG_DEBUG)
}
*/

; Copy git.ico to AppData if not exists
if !FileExist(A_AppData "\git.ico") {
    try FileCopy(A_ScriptDir "\git.ico", A_AppData "\git.ico")
    catch {
        ;LogDebug("Failed to copy git.ico to AppData")
    }
}

global lastFolder := ""

CheckExplorer() {
    global lastFolder
    try {
        hwnd := WinExist("A")
        if WinGetClass(hwnd) == "CabinetWClass" {
            explorer := ComObject("Shell.Application")
            for window in explorer.Windows {
                if window.HWND == hwnd {
                    currentFolder := window.Document.Folder.Self.Path
                    if currentFolder != lastFolder {
                        ;LogDebug("Folder changed to: " . currentFolder)
                        ScanGitRepos(currentFolder)
                        lastFolder := currentFolder
                    }
                    break
                }
            }
        }
    } catch as e {
        ;LogDebug("Error in CheckExplorer: " . e.Message)
    }
}

ScanGitRepos(folder) {
    try {
        Loop Files, folder "\*", "D" {
            dir := A_LoopFileFullPath
            if DirExist(dir "\.git") {
                isDirty := IsGitDirty(dir)
                if isDirty {
                    SetDirtyIcon(dir)
                } else {
                    ResetIcon(dir)
                }
            }
        }
    } catch as e {
        ;LogDebug("Error in ScanGitRepos: " . e.Message)
    }
}

IsGitDirty(repoPath) {
    try {
        tempFile := A_Temp "\git_status_temp.txt"
        RunWait(A_ComSpec ' /c cd /d "' repoPath '" && git status --porcelain > "' tempFile '"', , "Hide")
        if FileExist(tempFile) {
            content := FileRead(tempFile)
            FileDelete(tempFile)
            return StrLen(content) > 0
        }
    } catch as e {
        ;LogDebug("Error checking git status for " repoPath ": " . e.Message)
    }
    return false
}

SetDirtyIcon(folder) {
    try {
        iniPath := folder "\desktop.ini"
        IniWrite("%APPDATA%\\git.ico", iniPath, ".ShellClassInfo", "IconResource")
        FileSetAttrib("+H +S", iniPath)
        FileSetAttrib("+R", folder)
        ;LogDebug("Set dirty icon for: " . folder)
    } catch as e {
        ;LogDebug("Error setting dirty icon for " folder ": " . e.Message)
    }
}

ResetIcon(folder) {
    try {
        iniPath := folder "\desktop.ini"
        IniDelete(iniPath, ".ShellClassInfo", "IconResource")
        FileSetAttrib("-R", folder)
        ;LogDebug("Reset icon for: " . folder)
    } catch as e {
        ;LogDebug("Error resetting icon for " folder ": " . e.Message)
    }
}

SetTimer(CheckExplorer, 1000)

;LogDebug("Script started")
