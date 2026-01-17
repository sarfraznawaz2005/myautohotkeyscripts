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
        . "Message: " e.Message, "Script Error", "Iconx")
    return true ; Suppress default dialog
}

SetTitleMatchMode "Regex"
SetWorkingDir A_ScriptDir ; Ensure a consistant starting directory.

TraySetIcon("Icon.ico")
A_IconTip := "My Assistant"

; --- Tray Menu ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Check Air Quality Index", (*) => CheckAirQuality())
A_TrayMenu.Add("Fix My Screen DPI", (*) => fixMyDPI())
A_TrayMenu.Add()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())

; ------------------------------------------------------------------------------------------
; Include Our Scripts
; ------------------------------------------------------------------------------------------

#Include BrightnessCheck.ahk
#Include HotStrings.ahk
#Include EnvVariableRotator.ahk
#Include AiContextMenu.ahk
#Include PHPCodeRunner.ahk
#Include ShortCuts.ahk
#Include AirQuality.ahk
#Include UpdateChecker.ahk
#Include dpi.ahk


