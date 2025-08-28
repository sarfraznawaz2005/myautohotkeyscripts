;#Warn ; Enable warnings to assist with common detecting common errors.
#Requires AutoHotkey v2.0
#SingleInstance Force

; ------------------------------------------------------------------------------------------
; Global Error Handler
; ------------------------------------------------------------------------------------------
OnError(ShowError)
ShowError(e, *) {
    MsgBox("An error occurred:`n`n"
        . "File: " e.File "`n"
        . "Line: " e.Line "`n"
        . "Message: " e.Message, "Script Error")
    return true ; Suppress default dialog
}

SetTitleMatchMode "Regex"
SetWorkingDir A_ScriptDir ; Ensure a consistant starting directory.

TraySetIcon("Icon.ico")
A_IconTip := "My Assistant"

; ------------------------------------------------------------------------------------------
; Include Our Scripts
; ------------------------------------------------------------------------------------------

#Include HotStrings.ahk
#Include EnvVariableRotator.ahk
#Include AiContextMenu.ahk
#Include PHPCodeRunner.ahk
#Include ShortCuts.ahk
#Include UpdateChecker.ahk
#Include dpi.ahk