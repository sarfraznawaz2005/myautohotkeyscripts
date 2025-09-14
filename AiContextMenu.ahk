; AiContextMenu.ahk
; --- Manual trigger: ` Backtick key ---
; AutoHotkey v2
; Shows a context menu automatically after you select text, built from AiContextMenu.ini
; Menu actions create a composed prompt and selected text, then show a small UI
; to Copy / Paste / optionally Send to a webhook (if configured).

#SingleInstance Force

; ---------- Paths & Globals ----------
global g_Config := {}
global g_Menu := Map()
global g_LastSelection := ""
global g_SuppressUntil := 0
global g_DebounceMs := 200
global g_SelCheckInProgress := false
global g_ConfigPath := A_ScriptDir "\AiContextMenu.ini"
global g_ChatHistoryFile := ""
global g_active_popup_dlg := ""  ; For simple response popup
global g_active_chat_dlg := ""   ; For chat popup
global g_active_notification := ""  ; For custom notifications
global g_LastAction := {}
global g_DefaultActions := [
    Map("key","autocomplete","name","Autocomplete","shortcut","1","system_content","Continue the text intelligently, maintaining tone and context:"),
    Map("key","improve","name","Make It Better","shortcut","2","system_content","Improve clarity, flow, and style without changing meaning:"),
    Map("key","explain","name","Explain","shortcut","3","system_content","Explain the following text in simple terms:"),
    Map("key","summarize","name","Summarize","shortcut","4","system_content","Summarize the following text:"),
    Map("key","keypoints","name","List Key Points","shortcut","5","system_content","List the key points as concise bullets:")
]

; ---------- UI Styling Variables ----------
global g_UI := Map()
g_UI["PrimaryColor"] := "0x4285F4"     ; Google blue
g_UI["SecondaryColor"] := "0x34A853"  ; Google green
g_UI["AccentColor"] := "0xEA4335"     ; Google red
g_UI["WarningColor"] := "0xFBBC05"    ; Google yellow
g_UI["BackgroundColor"] := "0xF8F9FA"
g_UI["TextColor"] := "0x202124"
g_UI["BorderColor"] := "0xDADCE0"
g_UI["ButtonPrimary"] := "0x4285F4"
g_UI["ButtonSecondary"] := "0xF1F3F4"
g_UI["ButtonDanger"] := "0xEA4335"
g_UI["UserMessageColor"] := "0xE8F0FE"
g_UI["AssistantMessageColor"] := "0xF8F9FA"
g_UI["Font"] := "Segoe UI"
g_UI["FontSize"] := "s10"

; Global variables for chat dialog message handling
global g_CurrentChatDlg := ""
global g_CurrentUserInput := ""
global g_CurrentBtnSend := ""
global gSpinnerTimer := ""  ; For progress dialog spinner timer

; ---------- Startup ----------

; --- guaranteed startup init ---
;SetTimer Init, -10   ; Call Init once, after the script finishes loading

Init() {
    LoadConfig()
    BuildMenu()
}

Init()


; ---------- Triggers ----------

^+right:: {
    TryPopupAfterSelection()
}

; ---------- Core ----------
TryPopupAfterSelection() {
	/*
    global g_SuppressUntil, g_DebounceMs
    ; Debounce rapid events
    if (A_TickCount < g_SuppressUntil)
        return
    SetTimer(ShowIfSelectionChanged, -g_DebounceMs)
    g_SuppressUntil := A_TickCount + g_DebounceMs
    */
    ShowPopupMenuAtCaret()
}

ShowIfSelectionChanged() {
    global g_LastSelection
    sel := GetSelectedText()
    if (!sel)
        return

    g_LastSelection := sel
    ShowPopupMenuAtCaret()
}

ShowPopupMenuAtCaret() {
    global g_LastTarget, g_MenuItemCount, g_Menu
    if (g_MenuItemCount = 0)
        BuildMenu()
    g_LastTarget := SnapshotTarget()
    MouseGetPos &mx, &my
    g_Menu.Show(mx, my)
}

global g_MenuItemCount := 0

BuildMenu() {
    global g_Config, g_Menu, g_MenuItemCount, g_MenuActions
    g_Menu := Menu()
    g_MenuItemCount := 0
    g_MenuActions := Map() ; Store actions for hotkey access

    ; count defensively
    count := 0
    for _ in g_Config.Actions
        count++

    ; fallback if empty
    if (count = 0) {
        global g_DefaultActions
        g_Config.Actions := g_DefaultActions.Clone()
        for _ in g_Config.Actions
            count++
    }

    ; add items with numbers
    itemNumber := 1
    for action in g_Config.Actions {
        a := action  ; capture for Bind()
        title := Trim(a["name"])

        ; Add number prefix to menu item
        numberedTitle := "&" . itemNumber . ". " . title
        
        ; Add icon based on action type
        iconChar := ""
        actionName := StrLower(a["name"])
        if (InStr(actionName, "complete") || InStr(actionName, "write") || InStr(actionName, "auto")) {
            iconChar := "✍ "
        } else if (InStr(actionName, "improve") || InStr(actionName, "better") || InStr(actionName, "enhance")) {
            iconChar := "✨ "
        } else if (InStr(actionName, "explain")) {
            iconChar := "❓ "
        } else if (InStr(actionName, "summarize") || InStr(actionName, "brief")) {
            iconChar := "📋 "
        } else if (InStr(actionName, "key") || InStr(actionName, "point")) {
            iconChar := "🔑 "
        } else if (InStr(actionName, "translate")) {
            iconChar := "🌐 "
        } else if (InStr(actionName, "grammar") || InStr(actionName, "spelling") || InStr(actionName, "fix")) {
            iconChar := "🔧 "
        } else if (InStr(actionName, "answer") || InStr(actionName, "question")) {
            iconChar := "❓ "
        } else if (InStr(actionName, "detailed") || InStr(actionName, "detail")) {
            iconChar := "📋 "
        } else {
            iconChar := "⚡ "
        }
        
        numberedTitle := iconChar . numberedTitle
        g_Menu.Add(numberedTitle, OnActionChosen.Bind(a))

        ; Store action for hotkey access
        g_MenuActions[itemNumber] := a

        g_MenuItemCount++
        itemNumber++

        ; Limit to 9 numbered items for single-digit hotkeys
        if (itemNumber > 9)
            break
    }

    ; Continue adding remaining items without numbers if any
    if (itemNumber <= count) {
        for i, action in g_Config.Actions {
            if (i < itemNumber) ; Skip already processed items
                continue
            a := action
            title := Trim(a["name"])
            
            ; Add icon based on action type
            iconChar := ""
            actionName := StrLower(a["name"])
            if (InStr(actionName, "complete") || InStr(actionName, "write") || InStr(actionName, "auto")) {
                iconChar := "✍ "
            } else if (InStr(actionName, "improve") || InStr(actionName, "better") || InStr(actionName, "enhance")) {
                iconChar := "✨ "
            } else if (InStr(actionName, "explain")) {
                iconChar := "❓ "
            } else if (InStr(actionName, "summarize") || InStr(actionName, "brief")) {
                iconChar := "📋 "
            } else if (InStr(actionName, "key") || InStr(actionName, "point")) {
                iconChar := "🔑 "
            } else if (InStr(actionName, "translate")) {
                iconChar := "🌐 "
            } else if (InStr(actionName, "grammar") || InStr(actionName, "spelling") || InStr(actionName, "fix")) {
                iconChar := "🔧 "
            } else if (InStr(actionName, "answer") || InStr(actionName, "question")) {
                iconChar := "❓ "
            } else if (InStr(actionName, "detailed") || InStr(actionName, "detail")) {
                iconChar := "📋 "
            } else {
                iconChar := "⚡ "
            }
            
            titledTitle := iconChar . title
            g_Menu.Add(titledTitle, OnActionChosen.Bind(a))
            g_MenuItemCount++
        }
    }

    g_Menu.Add() ; Existing separator
    customTitle := "💬 &0. Chat"
    g_Menu.Add(customTitle, OnChatChosen) ; New chat action
}

; Handle numeric hotkeys when menu is shown
; Add this function to handle the numeric key presses
HandleMenuHotkey(key) {
    global g_MenuActions
    if (g_MenuActions.Has(key)) {
        ; Close the menu first
        g_Menu.Close()
        ; Execute the action
        OnActionChosen(g_MenuActions[key])
    }
}

ReloadConfig(*) {
    LoadConfig()
    BuildMenu()
    Notify("Configuration reloaded.", "success")
}

LoadConfig() {
    global g_Config, g_DefaultActions, g_ConfigPath

    cfg := Map()
    cfg.Settings := Map("show_notification", true, "max_input_length", 0)
    cfg.Webhook  := Map("enabled", false, "url", "", "method", "POST")
    cfg.Actions  := []

    if !FileExist(g_ConfigPath) {
        cfg.Actions := g_DefaultActions.Clone()
        WriteSampleConfig(g_ConfigPath, cfg)
        g_Config := cfg
        return
    }

    ; --- read whole file, normalize, strip BOM ---
    txt := FileRead(g_ConfigPath, "UTF-8")
    txt := RegExReplace(txt, "^\x{FEFF}")        ; remove BOM if present
    txt := StrReplace(txt, "`r", "")             ; normalize newlines to `n

    ; --- settings ---
    show := IniRead(g_ConfigPath, "settings", "show_notification", "on")
    cfg.Settings["show_notification"] := (StrLower(show) != "off")
    maxLen := IniRead(g_ConfigPath, "settings", "max_input_length", "0")
    cfg.Settings["max_input_length"] := Integer(maxLen)

    ; --- webhook (optional) ---
    if (RegExMatch(txt, "mi)^\s*\[webhook\]\s*$")) {
		whEnabled := IniRead(g_ConfigPath, "webhook", "enabled", "off")
		cfg.Webhook["enabled"] := (StrLower(whEnabled) = "on")

		url := IniRead(g_ConfigPath, "webhook", "url", "")
		url := Trim(url, ' "')          ;
		cfg.Webhook["url"] := url

		cfg.Webhook["method"] := IniRead(g_ConfigPath, "webhook", "method", "POST")

		secStart := RegExMatch(txt, "mi)^\s*\[webhook\]\s*$")
		sec := SubStr(txt, secStart)

		nextSecPos := RegExMatch(sec, "m)^\s*\[", , 2) ; second match in this string
		if (nextSecPos)
			sec := SubStr(sec, 1, nextSecPos - 1)


        ; collect header_* keys (case-insensitive)
        cfg.Webhook["headers"] := Map()
        ; scan keys inside [webhook]
		for , line in StrSplit(sec, "`n") {
			if RegExMatch(line, 'i)^\s*header_([^=\s]+)\s*=\s*(.*)$', &m) {
				headerName  := m[1]
				headerValue := Trim(m[2], ' "' . A_Tab)
				cfg.Webhook["headers"][headerName] := headerValue
			}
		}


    }

    ; --- actions: find any [prompt_*] (case-insensitive) ---
    pushed := 0
    pos := 1
    while (pos := RegExMatch(txt, "mi)^\s*\[(prompt_[^]\r\n]+)\]\s*$", &m, pos)) {
        secName := m[1]                  ; exact section name like prompt_summarize
        pos := pos + StrLen(m[0])        ; advance

        name := IniRead(g_ConfigPath, secName, "name", "")
        sys  := IniRead(g_ConfigPath, secName, "system_content", "")
        sc   := IniRead(g_ConfigPath, secName, "shortcut", "")

        if (name != "" && sys != "") {
            cfg.Actions.Push(Map(
                "key", secName,
                "name", name,
                "shortcut", sc,
                "system_content", sys
            ))
            pushed++
        }
    }

    if (pushed = 0) {
        ; hard fallback if nothing was picked up
        cfg.Actions := g_DefaultActions.Clone()
    }

    g_Config := cfg
}

WriteSampleConfig(path, cfg) {
    content := []
    content.Push("[settings]")
    content.Push("show_notification=on")
    content.Push("max_input_length=0")
    content.Push("")
    content.Push("; Optional webhook to send composed prompt + text")
    content.Push("[webhook]")
    content.Push("enabled=off")
    content.Push("url=")
    content.Push("method=POST")
    content.Push("; Example custom headers:")
    content.Push("; header_Authorization=Bearer YOUR_TOKEN")
    content.Push("")

    for action in cfg.Actions {
        content.Push("[" action["key"] "]")
        content.Push("name=" action["name"])
        content.Push("shortcut=" action["shortcut"])
        content.Push('system_content=' action["system_content"])
        content.Push("")
    }
    FileDelete(path)
    FileAppend(Trim(content.Join("`r`n"), "`r`n") "`r`n", path, "UTF-8")
}

; Called from menu (we bind the action when creating items)
OnActionChosen(action, *) {
    global g_Config, g_LastAction, g_LastSelection

    sel := GetSelectedText()
    if (!sel) {
        Notify("No text selected.", "warning")
        return
    }
    maxLen := g_Config.Settings["max_input_length"]
    if (maxLen > 0 && StrLen(sel) > maxLen) {
        Notify("Selection exceeds max_input_length (" maxLen ").", "error")
        return
    }
    g_LastAction   := action
    g_LastSelection := sel
    SendActionToWebhook(action, sel)
}

OnChatChosen(*) {
    global g_active_chat_dlg
    
    ; If a chat dialog is already open, focus it instead of creating a new one
    if (IsObject(g_active_chat_dlg) && g_active_chat_dlg.hwnd) {
        try {
            g_active_chat_dlg.Show()
            return
        } catch {
            ; If there's an error showing the existing dialog, continue to create a new one
        }
    }
    
    sel := GetSelectedText()

    if (Trim(sel) != "") {
        SendInitialChatMessage(sel)
    } else {
        ShowChatResponsePopup("Chat", "", (*) => OnChatChosen(), true)
    }
}

SendInitialChatMessage(user_message) {
    global g_Config, g_LastAction, g_LastSelection, g_active_chat_dlg
    
    ; If a chat dialog is already open, focus it instead of creating a new one
    if (IsObject(g_active_chat_dlg) && g_active_chat_dlg.hwnd) {
        try {
            g_active_chat_dlg.Show()
            return
        } catch {
            ; If there's an error showing the existing dialog, continue to create a new one
        }
    }

    url     := Trim(g_Config.Webhook["url"], ' "')
    method  := g_Config.Webhook["method"]
    headers := g_Config.Webhook["headers"]

    if (!url) {
        Notify("Webhook URL missing (see [webhook] in AiContextMenu.ini).", "error")
        return
    }

    payload := "You are a helpful assistant. Your answer must be simple text, no markdown, no html, just pure simple text. Respond to the user's message.`r`n`r`nUSER MESSAGE: " . user_message

    json := '{'
        . '"contents":[{"parts":[{"text":"' . JsonEscape(payload) . '"}]}]'
        . '}'

    if (!headers.Has("Content-Type"))
        headers["Content-Type"] := "application/json; charset=utf-8"

	ApiKey := EnvGet("GEMINI_API_KEY")
	url := url . ApiKey

    resp := HttpSend(url, method, json, headers)

    g_LastAction := Map("system_content", user_message)
    g_LastSelection := ""

    if (resp.status >= 200 && resp.status < 300) {
        out := ExtractGeminiText(resp.text)
        if (!out)
            out := resp.text
        
        retryCallback := (*) => SendInitialChatMessage(user_message)
        ShowChatResponsePopup("Chat", out, retryCallback)

    } else {
        retryCallback := (*) => SendInitialChatMessage(user_message)
        ShowChatResponsePopup("Chat - Error " . resp.status, resp.text, retryCallback)
    }
}

InsertIntoTargetAndClose(dlg, editCtrl, target, *) {
    dlg.Hide()
    InsertIntoTarget(editCtrl.Value, target)
    dlg.Destroy()
}

ShowSimpleResponsePopup(title, body, retryCallback) {
    global g_active_popup_dlg, g_UI
    if (IsObject(g_active_popup_dlg)) {
        try g_active_popup_dlg.Destroy()
    }

    body := NormalizeWebhookText(body)

    dlg := Gui("+AlwaysOnTop -MinimizeBox +Border", title)
    g_active_popup_dlg := dlg
    dlg.SetFont(g_UI["FontSize"], g_UI["Font"])
    
    ; Set background color
    dlg.BackColor := g_UI["BackgroundColor"]

    e := dlg.AddEdit("w800 r15 ReadOnly Wrap VScroll", body)
    ; Style the edit control
    e.Opt("+Border")
    e.SetFont("s10", g_UI["Font"])

    e.GetPos(&ex, &ey, &ew, &eh)
    margin := 15
    y := ey + eh + 20
    btnW := Floor((800 - margin*5) / 4)
    x0 := ex + margin

    ; Create buttons with improved styling
    btnCopy   := dlg.AddButton(Format("x{} y{} w{} Background{}", x0 + 0*(btnW+margin), y, btnW, g_UI["ButtonSecondary"]), "📋 Copy")
    btnInsert := dlg.AddButton(Format("x{} y{} w{} Background{}", x0 + 1*(btnW+margin), y, btnW, g_UI["ButtonPrimary"]), "📥 Insert")
    btnRetry  := dlg.AddButton(Format("x{} y{} w{} Background{}", x0 + 2*(btnW+margin), y, btnW, g_UI["WarningColor"]), "🔄 Try Again")
    btnClose  := dlg.AddButton(Format("x{} y{} w{} Background{}", x0 + 3*(btnW+margin), y, btnW, g_UI["ButtonSecondary"]), "✖ Close")
    
    ; Make Insert the default action as it's most likely what users want
    btnInsert.Opt("+Default")

    destroy_and_clear := (*) => (g_active_popup_dlg := "", dlg.Destroy())

    btnCopy.OnEvent("Click", (*) => (A_Clipboard := e.Value, Notify("Copied."), destroy_and_clear()))

	target := SnapshotTarget()
	btnInsert.OnEvent("Click", InsertIntoTargetAndClose.Bind(dlg, e, target))

    btnRetry.OnEvent("Click", (*) => ( destroy_and_clear(), retryCallback() ))
    btnClose.OnEvent("Click", destroy_and_clear)

    dlg.OnEvent("Close", (*) => (g_active_popup_dlg := ""))
    dlg.OnEvent("Escape", destroy_and_clear)

    dlg.Show("w830")
    btnInsert.Focus()
}

CleanupChatSession(gui, *) {
    global g_ChatHistoryFile, g_active_chat_dlg
    if (g_ChatHistoryFile != "" && FileExist(g_ChatHistoryFile)) {
        try FileDelete(g_ChatHistoryFile)
    }
    g_ChatHistoryFile := ""
    g_active_chat_dlg := ""
    gui.Destroy()
}

; Global message handler for chat dialogs
Global_WM_KEYDOWN(wParam, lParam, msg, hwnd) {
    ; This will be dynamically set when a chat dialog is created
    global g_CurrentChatDlg, g_CurrentUserInput, g_CurrentBtnSend
    
    ; Check if key pressed inside our userInput control
    if (IsObject(g_CurrentUserInput) && hwnd && hwnd = g_CurrentUserInput.Hwnd && wParam = 13) { ; Enter key
        ; Check if the dialog still exists
        if (IsObject(g_CurrentChatDlg) && g_CurrentChatDlg.hwnd) {
            ; Additional check to ensure the control is still valid
            try {
                ; Simulate button click
                SendMessage(0x00F5, 0, 0, g_CurrentBtnSend.hwnd) ; BM_CLICK message
            } catch {
                ; If control is destroyed, silently ignore
                return 0
            }
        }
        return 0 ; block Enter from making newline
    }
}

SendFollowUpToWebhook(gui, chatDisplay, userInput, action, *) {
    global g_Config, g_ChatHistoryFile

    userMsg := userInput.Value
    if (Trim(userMsg) = "")
        return

    userInput.Value := "" ; Clear input field

    history_update := "YOU: " . userMsg . "`r`n`r`n"
    FileAppend(history_update, g_ChatHistoryFile, "UTF-8")
    full_history_so_far := FileRead(g_ChatHistoryFile, "UTF-8")
    chatDisplay.Value := full_history_so_far
    SendMessage(0x0115, 7, 0, chatDisplay.Hwnd)  ; WM_VSCROLL, SB_BOTTOM

    url     := Trim(g_Config.Webhook["url"], ' "')
    method  := g_Config.Webhook["method"]
    headers := g_Config.Webhook["headers"]

    if (!url) {
        MsgBox("Webhook URL missing.")
        return
    }

    payload := "You are a helpful assistant. Your answer must be simple text, no markdown, no html, just pure simple text. Continue the conversation naturally based on the CHAT HISTORY below. The last message is from the user.`r`n`r`n--- CHAT HISTORY:`r`n" . full_history_so_far . "`r`n`r`nVERY IMPORTANT: If you cannot find the answer in the CHAT HISTORY, answer from your own knowledge."

    json := '{'
        . '"contents":[{"parts":[{"text":"' . JsonEscape(payload) . '"}]}]'
        . '}'

    if (!headers.Has("Content-Type"))
        headers["Content-Type"] := "application/json; charset=utf-8"

	ApiKey := EnvGet("GEMINI_API_KEY")
	url := url . ApiKey

    resp := HttpSend(url, method, json, headers)

    if (resp.status >= 200 && resp.status < 300) {
        out := ExtractGeminiText(resp.text)
        if (!out)
            out := resp.text
        
        assistant_response := "ASSISTANT: " . NormalizeWebhookText(out) . "`r`n`r`n"
        FileAppend(assistant_response, g_ChatHistoryFile, "UTF-8")
        chatDisplay.Value := FileRead(g_ChatHistoryFile, "UTF-8")
        SendMessage(0x0115, 7, 0, chatDisplay.Hwnd)  ; WM_VSCROLL, SB_BOTTOM
    } else {
        error_msg := "ASSISTANT: [ERROR " . resp.status . "]`r`n" . resp.text . "`r`n`r`n"
        FileAppend(error_msg, g_ChatHistoryFile, "UTF-8")
        chatDisplay.Value := FileRead(g_ChatHistoryFile, "UTF-8")
        SendMessage(0x0115, 7, 0, chatDisplay.Hwnd)  ; WM_VSCROLL, SB_BOTTOM
    }
    
    ; Return focus to the input field
    try userInput.Focus()
}

InsertLastResponse(dlg, target, *) {
    global g_ChatHistoryFile
    full_text := FileRead(g_ChatHistoryFile, "UTF-8")
    last_response := ""
    if RegExMatch(full_text, "s)ASSISTANT: (.*)$", &m) {
        last_response := Trim(m[1])
    }
    if (last_response != "") {
        InsertIntoTarget(last_response, target)
    }
    CleanupChatSession(dlg)
}

ShowChatResponsePopup(title, body, retryCallback, isNewChat := false) {
    global g_active_chat_dlg, g_CurrentChatDlg, g_CurrentUserInput, g_CurrentBtnSend, g_UI
    ; If a dialog is already open, destroy it first
    if (IsObject(g_active_chat_dlg)) {
        try {
            ; Unregister the message handler before destroying
            OnMessage(0x100, Global_WM_KEYDOWN, 0)
            g_active_chat_dlg.Destroy()
        } catch {
            ; Ignore any errors during destruction
        }
    }

    global g_ChatHistoryFile, g_LastSelection, g_LastAction
    
    if (g_ChatHistoryFile != "" && FileExist(g_ChatHistoryFile)) {
        try FileDelete(g_ChatHistoryFile)
    }
    
    g_ChatHistoryFile := A_Temp . "\AiChatHistory_" . A_TickCount . ".tmp"
    initial_history := ""

    if (!isNewChat) {
        user_turn := "YOU: " . g_LastAction["system_content"]
        
        if (Trim(g_LastSelection) != "") {
            user_turn .= "`r`n" . g_LastSelection
        }
        
        initial_history := user_turn . "`r`n`r`n"
        initial_history .= "ASSISTANT: " . NormalizeWebhookText(body) . "`r`n`r`n"
        FileAppend(initial_history, g_ChatHistoryFile, "UTF-8")
    } else {
        FileAppend("", g_ChatHistoryFile, "UTF-8")
    }
    
    dlg := Gui("+Resize +Border", title)
    g_active_chat_dlg := dlg
    g_CurrentChatDlg := dlg  ; For message handler
    dlg.SetFont(g_UI["FontSize"], g_UI["Font"])
    dlg.BackColor := g_UI["BackgroundColor"]
    
    chatDisplay := dlg.AddEdit("w800 r25 ReadOnly Wrap VScroll", initial_history)
    chatDisplay.SetFont("s10", g_UI["Font"])
    ; Add a subtle border to the chat display
    chatDisplay.Opt("+Border")
    ControlSend("{End}",, chatDisplay)
    
    ; Add placeholder text to the input field
    userInput := dlg.AddEdit("w800 y+10 h25 Multi -VScroll -Wrap", "")
    userInput.SetFont("s10", g_UI["Font"])
    g_CurrentUserInput := userInput  ; For message handler
    
    ; Add visible Send button
    btnSend := dlg.AddButton("yp-1 x+10 w80 Default Background" g_UI["ButtonPrimary"], "Send")
    g_CurrentBtnSend := btnSend  ; For message handler
    
    ; Hook WM_KEYDOWN (0x100)
    OnMessage(0x100, Global_WM_KEYDOWN)
    
    ; Get user input position and dimensions
    userInput.GetPos(&ux, &uy, &uw, &uh)
    y := uy + uh + 15
    
    ; Button settings
    outer_margin := 15
    btnW := 100
    btnH := 30
    
    dlg.GetClientPos(,, &window_width, &window_height)

    ; Create buttons with improved styling
    btnCopy   := dlg.AddButton(Format("x{} y{} w{} h{} Background{}", outer_margin, y, btnW, btnH, g_UI["ButtonSecondary"]), "📋 Copy")
    btnCopyLast := dlg.AddButton(Format("x{} y{} w{} h{} Background{}", outer_margin + btnW + 10, y, btnW, btnH, g_UI["ButtonSecondary"]), "📋 Copy Last")
    btnClose  := dlg.AddButton(Format("x{} y{} w{} h{} Background{}", window_width - btnW - outer_margin, y, btnW, btnH, g_UI["ButtonSecondary"]), "✖ Close")
    
    target := SnapshotTarget()
    btnSend.OnEvent("Click", SendFollowUpToWebhook.Bind(dlg, chatDisplay, userInput, g_LastAction))
    btnCopy.OnEvent("Click", (*) => (A_Clipboard := chatDisplay.Value, Notify("Copied.")))
    btnCopyLast.OnEvent("Click", (*) => CopyLastMessage(chatDisplay))
    
    cleanup_and_close := (*) => (g_active_chat_dlg := "", OnMessage(0x100, Global_WM_KEYDOWN, 0), CleanupChatSession(dlg))
    btnClose.OnEvent("Click", cleanup_and_close)
    dlg.OnEvent("Close", (*) => (g_active_chat_dlg := "", OnMessage(0x100, Global_WM_KEYDOWN, 0)))
    dlg.OnEvent("Escape", cleanup_and_close)
    
    ; Handle window resize to redistribute buttons
    dlg.OnEvent("Size", ResizeHandler)
    
    ResizeHandler(GuiObj, MinMax, Width, Height) {
        if (MinMax == -1) ; Minimized
            return
            
        ; --- Vertical Resizing ---
        userInput.GetPos(,,,&uh)
        btnCopy.GetPos(,,,&bh)
        
        ; Calculate total height of controls below the main chat display
        fixed_v_space := 10 + uh + 15 + bh + 20 ; gap-above-input + input-h + gap-above-buttons + button-h + bottom-margin
        new_chat_height := Height - fixed_v_space
        
        if (new_chat_height < 50) ; Prevent display from becoming too small
            new_chat_height := 50

        ; Resize chat display and move controls below it
        chatDisplay.Move(,, Width - 30, new_chat_height)
        
        chatDisplay.GetPos(&cdX, &cdY, &cdW, &cdH)
        userInput.Move(15, cdY + cdH + 10, Width - 125)
        btnSend.Move(Width - 95, cdY + cdH + 10, 80, 25)

        ; --- Horizontal Button Repositioning ---
        userInput.GetPos(&ux, &uy, &uw, &uh)
        new_button_y := uy + uh + 15
        btnCopy.GetPos(,,&btnW,)
        
        btnCopy.Move(outer_margin, new_button_y)
        btnCopyLast.Move(outer_margin + btnW + 10, new_button_y)
        btnClose.Move(Width - btnW - outer_margin, new_button_y)
    }
    
    dlg.Show("w830 h500")
    userInput.Focus()
    ControlSend("{End}",, chatDisplay)
}

CopyLastMessage(chatDisplay) {
    global g_ChatHistoryFile
    ; Read the chat history file
    full_text := FileRead(g_ChatHistoryFile, "UTF-8")
    
    ; Extract the last assistant message (without the "ASSISTANT: " prefix)
    last_response := ""
    
    ; Split the text by message delimiters to get individual messages
    messages := StrSplit(full_text, "`r`n`r`n")
    
    ; Go through messages backwards to find the last assistant message
    i := messages.Length
    while (i >= 1) {
        message := messages[i]
        if (InStr(message, "ASSISTANT: ") == 1) {
            ; Found the last assistant message, extract content after the prefix
            last_response := Trim(SubStr(message, 12))  ; Remove "ASSISTANT: " prefix (11 chars)
            break
        }
        i--
    }
    
    if (last_response != "") {
        A_Clipboard := last_response
        Notify("Last message copied.")
    } else {
        Notify("No assistant message found.", "warning")
    }
}

SendActionToWebhook(action, sel) {
    global g_Config
    url     := Trim(g_Config.Webhook["url"], ' "')
    method  := g_Config.Webhook["method"]
    headers := g_Config.Webhook["headers"]

    if (!url) {
        Notify("Webhook URL missing (see [webhook] in AiContextMenu.ini).", "error")
        return
    }

    payload := "You are a helpful assistant. Your answer must be simple text, no markdown, no html, just pure simple text. Fulfill the user's request based on the following prompt and text.`r`n`r`nPROMPT: " . action["system_content"] . "`r`n`r`nTEXT:`r`n" . sel

    json := '{'
        . '"contents":[{"parts":[{"text":"' . JsonEscape(payload) . '"}]}]'
        . '}'

    if (!headers.Has("Content-Type"))
        headers["Content-Type"] := "application/json; charset=utf-8"

	ApiKey := EnvGet("GEMINI_API_KEY")
	url := url . ApiKey

    resp := HttpSend(url, method, json, headers)

    if (resp.status >= 200 && resp.status < 300) {
        out := ExtractGeminiText(resp.text)
        if (!out)
            out := resp.text
        
        retryCallback := (*) => SendActionToWebhook(action, sel)

        ShowSimpleResponsePopup(action["name"], out, retryCallback)

        if g_Config.Settings["show_notification"]
            Notify("Done (" resp.status ").", "success")
    } else {
        retryCallback := (*) => SendActionToWebhook(action, sel)
        ShowSimpleResponsePopup(action["name"] " — Error " resp.status, resp.text, retryCallback)
        Notify("Webhook error (" resp.status ").", "error")
    }
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')  ; Fixed: was '"' should be '\"'
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    s := StrReplace(s, "`b", "\b")  ; Added: backspace
    s := StrReplace(s, "`f", "\f")  ; Added: form feed
    return s
}

JsonUnescape(s) {
    s := StrReplace(s, '\"', '"')  ; Fixed: was '"' should be '\"'
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\t", "`t")
    s := StrReplace(s, "\b", "`b")  ; Added: backspace
    s := StrReplace(s, "\f", "`f")  ; Added: form feed
    s := StrReplace(s, "\\", "\")
    while RegExMatch(s, "\\u([0-9A-Fa-f]{4})", &m) {
        code := Integer("0x" m[1])
        s := StrReplace(s, m[0], Chr(code))
    }
    return s
}

ExtractGeminiText(json) {
    if RegExMatch(json, '"text"\s*:\s*"((?:\\.|[^"\\])*)"', &m) {
        txt := m[1]
        return JsonUnescape(txt)
    }
    return ""
}

NormalizeWebhookText(s) {
    s := StrReplace(s, "\r\n", "`r`n")
    s := StrReplace(s, "\n",   "`n")
    s := StrReplace(s, "\r",   "`r")
    s := StrReplace(s, "`t",   "`t")
    s := StrReplace(s, '"',   '"')
    return s
}

HttpSend(url, method, body, headers) {
    ShowProgress()
    try {
        ; Try using MSXML2.XMLHTTP for better async support
        try {
            xhr := ComObject("MSXML2.XMLHTTP")
            isMSXML := true
        } catch {
            ; Fallback to WinHttp.WinHttpRequest
            xhr := ComObject("WinHttp.WinHttpRequest.5.1")
            isMSXML := false
        }
        
        if (isMSXML) {
            ; MSXML2.XMLHTTP approach
            xhr.open(method, url, true)  ; asynchronous
            for k, v in headers
                xhr.setRequestHeader(k, v)
            xhr.send(body)
            
            ; Wait for response while allowing GUI to update
            while xhr.readyState != 4
                Sleep 50
                
            return { status: xhr.status, text: xhr.responseText }
        } else {
            ; WinHttp.WinHttpRequest approach with periodic GUI updates
            xhr.Open(method, url, false)  ; synchronous
            for k, v in headers
                xhr.SetRequestHeader(k, v)
            
            ; Send the request in a separate thread-like approach
            xhr.Send(body)
            
            ; While waiting for response, periodically yield to allow GUI updates
            startTime := A_TickCount
            while xhr.Status = 0 {  ; Status 0 means still loading
                try {
                    ; Try to access status to trigger update
                    tempStatus := xhr.Status
                } catch {
                    ; Ignore errors during loading
                }
                Sleep 50  ; Yield to allow GUI updates
                
                ; Timeout after 30 seconds
                if (A_TickCount - startTime > 30000)
                    break
            }
            
            return { status: xhr.Status, text: xhr.ResponseText }
        }
    } catch as e {
        throw e
    } finally {
        HideProgress()
    }
}

SnapshotTarget() {
    try {
        winHwnd := WinGetID("A")
        ctrl    := ControlGetFocus("ahk_id " winHwnd)
        try ctrlHwnd := ControlGetHwnd(ctrl, "ahk_id " winHwnd)
        return Map("winHwnd", winHwnd, "ctrl", ctrl, "ctrlHwnd", ctrlHwnd)
    } catch {
        winHwnd := 0, ctrl := "", ctrlHwnd := 0
    }
}

InsertIntoTarget(text, target) {
    clip := ClipboardAll()
    A_Clipboard := text
    Sleep 40
    if (target && target.Has("winHwnd") && target["winHwnd"]) {
        WinActivate "ahk_id " target["winHwnd"]
        if (target["ctrl"])
            ControlFocus target["ctrl"], "ahk_id " target["winHwnd"]
        Sleep 150
    }
    Send "^v"
    Sleep 40
    A_Clipboard := clip
}


global gProgress := 0

ShowProgress(msg := "Please wait...") {
    global gProgress, g_UI
    if IsObject(gProgress)
        return
    g := Gui("+AlwaysOnTop -SysMenu +ToolWindow -Caption +Border")
    g.SetFont("s10 bold", g_UI["Font"])
    g.MarginX := 1, g.MarginY := 1
    
    ; Use our styled border color
    g.BackColor := g_UI["BorderColor"]
    
    ; Create a panel with our background color
    bgPanel := g.Add("Text", "w250 h25 Background" g_UI["BackgroundColor"], "")
    
    ; Add text on top, centered both horizontally and vertically
    txt := g.Add("Text", "xp+1 yp+1 w248 h23 Center Background" g_UI["BackgroundColor"], msg)
    txt.Opt("+0x200")  ; SS_CENTERIMAGE for vertical centering
    
    ; Add a progress bar instead of character spinner
    progress := g.Add("Progress", "xp yp+25 w248 h20 Background" g_UI["BackgroundColor"], 0)
    
    ; Simple animation for the progress bar
    global gProgressCtrl := progress
    global gProgressValue := 0
    
    ; Create a bound function for the timer
    boundFunc := UpdateProgressBar.Bind(progress)
    SetTimer(boundFunc, 100)
    global gSpinnerTimer := boundFunc  ; Store the timer reference
    
    ; Create a bound function for the timer
    boundFunc := UpdateProgressBar.Bind(progress)
    SetTimer(boundFunc, 100)
    global gSpinnerTimer := boundFunc  ; Store the timer reference
    
    g.Title := "Working"
    g.Show("AutoSize Center")
    gProgress := g
}

UpdateProgressBar(progress) {
    global gProgressValue
    ; Check if the control still exists before updating
    try {
        if (IsObject(progress) && progress.hwnd) {
            gProgressValue := Mod(gProgressValue + 10, 101)  ; Cycle from 0 to 100
            progress.Value := gProgressValue
        }
    } catch {
        ; Ignore errors if the control is destroyed
    }
}

HideProgress() {
    global gProgress, gSpinnerTimer
    if IsObject(gProgress) {
        try {
            SetTimer(gSpinnerTimer, 0)  ; Stop the progress timer
            gProgress.Destroy()
        }
        gProgress := 0
    }
}

GetSelectedText(maxWait := 0.25) {
    saved := ClipboardAll()
    try {
        A_Clipboard := ""
        Send "^c"
        if !ClipWait(maxWait)
            return ""
        return A_clipboard
    } finally {
        A_Clipboard := saved
    }
}

HasMeaningfulSelection(minLen := 10) {
    sel := GetSelectedText()
    compact := RegExReplace(sel, "\\s+", " ")
    return StrLen(Trim(compact)) >= minLen
}

Notify(msg, type := "info") {
    global g_UI, g_active_notification
    
    ; Destroy any existing notification
    if (IsObject(g_active_notification)) {
        try g_active_notification.Destroy()
    }
    
    ; Create notification dialog
    dlg := Gui("+AlwaysOnTop +ToolWindow -SysMenu +Border")
    dlg.SetFont(g_UI["FontSize"], g_UI["Font"])
    
    ; Set colors based on notification type
    bgColor := g_UI["BackgroundColor"]
    if (type = "error") {
        bgColor := g_UI["AccentColor"]
    } else if (type = "warning") {
        bgColor := g_UI["WarningColor"]
    } else if (type = "success") {
        bgColor := g_UI["SecondaryColor"]
    }
    
    dlg.BackColor := bgColor
    
    ; Add message text
    txt := dlg.Add("Text", "Background" bgColor, msg)
    txt.SetFont("s10", g_UI["Font"])
    
    ; Calculate position (top-right corner)
    dlg.GetClientPos(,, &width, &height)
    x := A_ScreenWidth - width - 20
    y := 30
    
    ; Show the notification
    dlg.Show("x" x " y" y " NoActivate")
    g_active_notification := dlg
    
    ; Auto-hide after 2 seconds
    timerCallback := NotificationTimer.Bind()
    SetTimer(timerCallback, -2000)
}

NotificationTimer(*) {
    global g_active_notification
    if (IsObject(g_active_notification)) {
        try {
            g_active_notification.Destroy()
        }
        g_active_notification := ""
    }
}
