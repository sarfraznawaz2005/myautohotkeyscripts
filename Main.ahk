;#Warn ; Enable warnings to assist with common detecting common errors.
#Requires AutoHotkey v2.0
#SingleInstance Force

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
#Include StartStopAIVideoGenApp.ahk
