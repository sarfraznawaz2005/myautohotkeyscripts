; AutoHotkey v2 Script - PHP Code Runner
; Press Ctrl+Shift+Space to run selected PHP code
;
; TEST:
;
; <?php echo 'hello world!';
; echo 'hello world again!';
; $array = range('A', 'F'); print_r($array);

; Configuration - Set your PHP binary path here
PHP_BINARY_PATH := "php"

#SingleInstance Force

; Hotkey: Ctrl+Shift+Space
^+p:: {
    ; Get selected text
    selectedText := GetSelectedText()

    if (selectedText = "") {
        MsgBox("No text selected!", "PHP Runner", 48)
        return
    }

    ; Show context menu
    ShowContextMenu()
}

; Function to show context menu
ShowContextMenu() {
    ; Create context menu
    contextMenu := Menu()
    contextMenu.Add("Run with PHP", RunPHPCode)
    contextMenu.Add()  ; Separator
    contextMenu.Add("Cancel", (*) => "")

    ; Show menu at cursor position
    contextMenu.Show()
}

; Function to run PHP code
RunPHPCode(*) {
    ; Get selected text again
    selectedText := GetSelectedText()

    if (selectedText = "") {
        MsgBox("No text selected!", "PHP Runner", 48)
        return
    }

    ; Add PHP opening tags if not present
    phpCode := AddPHPTags(selectedText)

    ; Create temporary PHP file
    tempDir := A_Temp
    tempFile := tempDir . "\ahk_temp_php_" . A_TickCount . ".php"

    try {
        ; Write PHP code to temporary file
        FileAppend(phpCode, tempFile, "UTF-8-RAW")

        ; Run PHP code and capture output
        RunCommand(PHP_BINARY_PATH . " " . tempFile)

    } catch Error as err {
        MsgBox("Error creating temporary file: " . err.message, "PHP Runner Error", 16)
    }

    ; Clean up temporary file
    if (FileExist(tempFile)) {
        try {
            FileDelete(tempFile)
        }
    }
}

; Function to add PHP tags if missing
AddPHPTags(code) {
    trimmedCode := Trim(code)

    ; Check if code already starts with <?php or <?
    if (RegExMatch(trimmedCode, "^<\?(?:php)?")) {
        return trimmedCode
    }

    ; Add PHP opening tag
    return "<?php`n" . trimmedCode
}

; Function to run command and show output
RunCommand(command) {

	ShowProgress()

    tempOut := A_Temp . "\ahk_php_output_" . A_TickCount . ".txt"

    try {
        ; Construct the full command to be executed by cmd.exe
        ; This includes setting UTF-8, running the PHP command, and redirecting output
        fullCmdLine := "chcp 65001 > nul & " . command . " > " . Chr(34) . tempOut . Chr(34) . " 2>&1"

        ; Escape internal quotes for RunWait
        escapedFullCmdLine := StrReplace(fullCmdLine, "`"", "`"`"")

        ; Construct the final command string for RunWait
        finalRunCommand := A_ComSpec . " /c " . "`"" . escapedFullCmdLine . "`""

        ; Run the command hidden using A_ComSpec (cmd.exe)
        ; The /c switch tells cmd.exe to execute the string and then terminate
        RunWait(finalRunCommand, , "Hide")

        ; Read the output from the temporary file
        if (FileExist(tempOut)) {
            output := FileRead(tempOut, "UTF-8")

            if (Trim(output) = "") {
                output := "PHP code executed successfully with no output."
            }

            ; Show output in a custom GUI
            ShowOutput(output)
        } else {
            MsgBox("No output file created.", "PHP Runner", 48)
        }

    } catch Error as err {
        MsgBox("Error running PHP: " . err.message, "PHP Runner Error", 16)
    }
	finally {
        HideProgress()
    }


    ; Clean up temporary file
    if (FileExist(tempOut)) {
        try {
            FileDelete(tempOut)
        }
        catch Error as err {
            ; Log or handle error if file deletion fails
        }
    }
}

; Function to show PHP output
ShowOutput(output) {
    ; Create a professional GUI with modern styling
    outputGui := Gui("+Resize +MinSize500x350 +MaximizeBox", "PHP Code Output")
    outputGui.BackColor := "White"
    outputGui.MarginX := 20
    outputGui.MarginY := 20

    ; Add text control for output with professional styling - starting from top
    outputText := outputGui.Add("Edit", "xm ym W700 H420 ReadOnly VScroll HScroll", output)

    ; Set professional font styling
    outputText.SetFont("s12", "Consolas")  ; Larger, more readable font

    ; Add professional buttons with icons - positioned at bottom
    ; Reordered: Copy, Clear, Close (Close is now last)
    copyBtn := outputGui.Add("Button", "xm y+15 W140 H40", "📋 Copy")
    clearBtn := outputGui.Add("Button", "x+15 yp W100 H40", "🗑 Clear")
    closeBtn := outputGui.Add("Button", "x+15 yp W100 H40", "✖ Close")

    ; Style buttons professionally
    copyBtn.SetFont("s11", "Segoe UI")
    clearBtn.SetFont("s11", "Segoe UI")
    closeBtn.SetFont("s11", "Segoe UI")

    ; Store references for resizing
    outputGui.outputText := outputText
    outputGui.copyBtn := copyBtn
    outputGui.closeBtn := closeBtn
    outputGui.clearBtn := clearBtn

    ; Event handlers
    copyBtn.OnEvent("Click", CopyOutput)
    closeBtn.OnEvent("Click", (*) => outputGui.Destroy())
    clearBtn.OnEvent("Click", ClearOutput)

    ; Handle GUI events
    outputGui.OnEvent("Close", (*) => outputGui.Destroy())
    outputGui.OnEvent("Escape", (*) => outputGui.Destroy())
    outputGui.OnEvent("Size", GuiResize)

    ; Show the GUI with better initial size
    outputGui.Show("W740 H520")

    ; Function to handle copy button click
    CopyOutput(*) {
        A_Clipboard := output
        ; Update button text temporarily to show success
        copyBtn.Text := "✓ Copied!"
        copyBtn.Opt("+Disabled")
        SetTimer(ResetCopyButton, -1500)
    }

    ; Helper function to reset copy button
    ResetCopyButton() {
        copyBtn.Text := "📋 Copy Output"
        copyBtn.Opt("-Disabled")
    }

    ; Function to clear output
    ClearOutput(*) {
        outputText.Text := ""
        clearBtn.Text := "✓ Cleared"
        SetTimer(ResetClearButton, -1000)
    }

    ; Helper function to reset clear button
    ResetClearButton() {
        clearBtn.Text := "🗑 Clear"
    }

    ; Improved resize handler - simplified without header elements
    GuiResize(thisGui, minMax, width, height) {
        if (minMax = -1)  ; Minimized
            return

        try {
            ; Calculate margins and fixed heights
            margin := 20
            buttonHeight := 40
            buttonAreaHeight := 65  ; Space for buttons + margins

            ; Calculate new dimensions
            newContentW := width - (margin * 2)
            newTextH := height - buttonAreaHeight - (margin * 2)

            ; Ensure minimum sizes
            if (newTextH < 200)
                newTextH := 200
            if (newContentW < 400)
                newContentW := 400

            ; Resize text area (both width and height) - starts from top margin
            outputGui.outputText.Move(margin, margin, newContentW, newTextH)

            ; Position buttons at bottom (fixed relative to bottom)
            ; Reordered: Copy, Clear, Close
            buttonY := height - buttonAreaHeight
            outputGui.copyBtn.Move(margin, buttonY)
            outputGui.clearBtn.Move(margin + 155, buttonY)
            outputGui.closeBtn.Move(margin + 270, buttonY)

        } catch Error as err {
            ; Silently handle any resize errors
        }
    }
}
