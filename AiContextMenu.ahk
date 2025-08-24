; AiContextMenu.ahk
; --- Manual trigger: ` Backtick key ---
; AutoHotkey v2
; Shows a context menu automatically after you select text, built from AiContextMenu.ini
; Menu actions create a composed prompt and selected text, then show a small UI
; to Copy / Paste / optionally Send to a webhook (if configured).


; ---------- Paths & Globals ----------
global g_Config := {}
global g_Menu := Map()
global g_LastSelection := ""
global g_SuppressUntil := 0
global g_DebounceMs := 200
global g_SelCheckInProgress := false
global g_ConfigPath := A_ScriptDir "\AiContextMenu.ini"
global g_ChatHistoryFile := ""
global g_LastAction := {}
global g_DefaultActions := [
    Map("key","autocomplete","name","Autocomplete","shortcut","1","system_content","Continue the text intelligently, maintaining tone and context:"),
    Map("key","improve","name","Make It Better","shortcut","2","system_content","Improve clarity, flow, and style without changing meaning:"),
    Map("key","explain","name","Explain","shortcut","3","system_content","Explain the following text in simple terms:"),
    Map("key","summarize","name","Summarize","shortcut","4","system_content","Summarize the following text:"),
    Map("key","keypoints","name","List Key Points","shortcut","5","system_content","List the key points as concise bullets:")
]

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
            g_Menu.Add(title, OnActionChosen.Bind(a))
            g_MenuItemCount++
        }
    }

    g_Menu.Add() ; Existing separator
    customTitle := "&0. Custom"
    g_Menu.Add(customTitle, OnCustomActionChosen) ; New custom action
    ;g_Menu.Add() ; New separator for the custom action
    ;g_Menu.Add("Reload Config  (Ctrl+Alt+R)", ReloadConfig)
    ;g_Menu.Add("Exit", (*) => ExitApp())
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
    TrayTip("Configuration reloaded.", "SmartSelectMenu")
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
        MsgBox("No text selected.")
        return
    }
    maxLen := g_Config.Settings["max_input_length"]
    if (maxLen > 0 && StrLen(sel) > maxLen) {
        MsgBox("Selection exceeds max_input_length (" maxLen ").")
        return
    }
    g_LastAction   := action
    g_LastSelection := sel
    SendActionToWebhook(action, sel)
}

OnCustomActionChosen(*) {
    global g_Config, g_LastSelection, g_LastAction

    sel := "" ; Don't get selected text for custom actions

    ; Show custom prompt dialog
    customPrompt := ShowCustomPromptDialog()

    if (customPrompt == "")
        return

    ; Create a dummy action map for the custom prompt
    customAction := Map(
        "key", "custom_prompt",
        "name", "Custom Prompt",
        "shortcut", "",
        "system_content", customPrompt
    )

    g_LastAction := customAction
    g_LastSelection := sel
    SendActionToWebhook(customAction, sel)
}

ShowCustomPromptDialog() {
    result := ""

    ; Create custom dialog
    dlg := Gui("+AlwaysOnTop -MinimizeBox", "Custom AI Prompt")
    dlg.SetFont("s10", "Segoe UI")
    dlg.MarginX := 16
    dlg.MarginY := 16

    ; Add label and textarea
    dlg.Add("Text", "w400", "Enter Your Prompt")
    promptEdit := dlg.Add("Edit", "w600", "")

    ; Add buttons
    btnOK := dlg.Add("Button", "w80 h30", "OK")
    btnCancel := dlg.Add("Button", "x+10 yp w80 h30", "Cancel")

    ; Set default button
    btnOK.Opt("+Default")

    ; Event handlers
    btnOK.OnEvent("Click", (*) => (result := promptEdit.Text, dlg.Hide()))
    btnCancel.OnEvent("Click", (*) => (result := "", dlg.Hide()))
    dlg.OnEvent("Close", (*) => dlg.Hide())
    dlg.OnEvent("Escape", (*) => (result := "", dlg.Hide()))

    ; Show dialog and wait for user action
    dlg.Show()
    WinWaitClose(dlg.Hwnd)
    dlg.Destroy()

    return Trim(result)
}

InsertIntoTargetAndClose(dlg, editCtrl, target, *) {
    dlg.Hide()
    InsertIntoTarget(editCtrl.Value, target)
    dlg.Destroy()
}

ShowSimpleResponsePopup(title, body, retryCallback) {
    body := NormalizeWebhookText(body)

    dlg := Gui("+AlwaysOnTop -MinimizeBox", title)
    dlg.SetFont("s11", "Segoe UI")

    e := dlg.AddEdit("w800 r15 ReadOnly Wrap VScroll", body)

    e.GetPos(&ex, &ey, &ew, &eh)
    margin := 12
    y := ey + eh + 14
    btnW := Floor((800 - margin*5) / 4)
    x0 := ex + margin

    btnCopy   := dlg.AddButton(Format("x{} y{} w{}", x0 + 0*(btnW+margin), y, btnW), "📋 Copy")
    btnInsert := dlg.AddButton(Format("x{} y{} w{}", x0 + 1*(btnW+margin), y, btnW), "📥 Insert")
    btnRetry  := dlg.AddButton(Format("x{} y{} w{}", x0 + 2*(btnW+margin), y, btnW), "🔄 Try Again")
    btnClose  := dlg.AddButton(Format("x{} y{} w{}", x0 + 3*(btnW+margin), y, btnW), "✖ Close")
    
    btnClose.Opt("+Default")

    btnCopy.OnEvent("Click", (*) => (A_Clipboard := e.Value, Notify("Copied."), dlg.Destroy()))

	target := SnapshotTarget()
	btnInsert.OnEvent("Click", InsertIntoTargetAndClose.Bind(dlg, e, target))

    btnRetry.OnEvent("Click", (*) => ( dlg.Destroy(), retryCallback() ))
    btnClose.OnEvent("Click", (*) => dlg.Destroy())

    dlg.Show()
    btnClose.Focus()
}

CleanupChatSession(gui, *) {
    global g_ChatHistoryFile
    if (g_ChatHistoryFile != "" && FileExist(g_ChatHistoryFile)) {
        try FileDelete(g_ChatHistoryFile)
    }
    g_ChatHistoryFile := ""
    gui.Destroy()
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

ShowChatResponsePopup(title, body, retryCallback) {
    global g_ChatHistoryFile, g_LastSelection, g_LastAction
    
    if (g_ChatHistoryFile != "" && FileExist(g_ChatHistoryFile)) {
        try FileDelete(g_ChatHistoryFile)
    }
    
    g_ChatHistoryFile := A_Temp . "\AiChatHistory_" . A_TickCount . ".tmp"
    user_turn := "YOU: " . g_LastAction["system_content"]
    
    if (Trim(g_LastSelection) != "") {
        user_turn .= "`r`n" . g_LastSelection
    }
    
    initial_history := user_turn . "`r`n`r`n"
    initial_history .= "ASSISTANT: " . NormalizeWebhookText(body) . "`r`n`r`n"
    FileAppend(initial_history, g_ChatHistoryFile, "UTF-8")
    
    dlg := Gui("+AlwaysOnTop -MinimizeBox +Resize -MaximizeBox", title)
    dlg.SetFont("s11", "Segoe UI")
    chatDisplay := dlg.AddEdit("w800 r25 ReadOnly Wrap VScroll", initial_history)
    ControlSend("{End}",, chatDisplay)
    
    userInput := dlg.AddEdit("w800 y+10 h23", "")
    btnSend := dlg.AddButton("Hidden Default", "Send")
    
    ; Get user input position and dimensions
    userInput.GetPos(&ux, &uy, &uw, &uh)
    y := uy + uh + 14
    
    ; Button distribution calculations - use full window width
    numButtons := 4
    outer_margin := 10
    inner_gap := 5
    dlg.GetClientPos(,, &window_width, &window_height)
    total_width := window_width  ; Use full window width instead of input width
    available_width := total_width - (2 * outer_margin) - ((numButtons - 1) * inner_gap)
    btnW := available_width // numButtons  ; Integer division for equal button widths
    
    ; Create buttons with calculated positions and consistent height
    btnHeight := 28
    btnCopy   := dlg.AddButton(Format("x{} y{} w{} h{}", outer_margin + 0*(btnW+inner_gap), y, btnW, btnHeight), "📋 Copy")
    btnInsert := dlg.AddButton(Format("x{} y{} w{} h{}", outer_margin + 1*(btnW+inner_gap), y, btnW, btnHeight), "📥 Insert")
    btnRetry  := dlg.AddButton(Format("x{} y{} w{} h{}", outer_margin + 2*(btnW+inner_gap), y, btnW, btnHeight), "🔄 Try Again")
    btnClose  := dlg.AddButton(Format("x{} y{} w{} h{}", outer_margin + 3*(btnW+inner_gap), y, btnW, btnHeight), "✖ Close")
    
    btnClose.Opt("+Default")
    
    target := SnapshotTarget()
    btnSend.OnEvent("Click", SendFollowUpToWebhook.Bind(dlg, chatDisplay, userInput, g_LastAction))
    btnCopy.OnEvent("Click", (*) => (A_Clipboard := chatDisplay.Value, Notify("Copied."), CleanupChatSession(dlg)))
    btnInsert.OnEvent("Click", InsertLastResponse.Bind(dlg, target))
    btnRetry.OnEvent("Click", (*) => ( CleanupChatSession(dlg), retryCallback() ))
    btnClose.OnEvent("Click", (*) => CleanupChatSession(dlg))
    dlg.OnEvent("Close", (*) => CleanupChatSession(dlg))
    
    ; Handle window resize to redistribute buttons
    dlg.OnEvent("Size", ResizeHandler)
    
    ResizeHandler(GuiObj, MinMax, Width, Height) {
        if (MinMax == -1) ; Minimized
            return
            
        ; Resize chat display and user input
        chatDisplay.Move(,, Width - 20)
        userInput.Move(,, Width - 20)
        
        ; Recalculate button positions using full window width
        userInput.GetPos(&ux, &uy, &uw, &uh)
        new_y := uy + uh + 14
        
        new_available_width := Width - (2 * outer_margin) - ((numButtons - 1) * inner_gap)
        new_btnW := new_available_width // numButtons
        
        ; Update button positions and widths with consistent height
        btnCopy.Move(outer_margin + 0*(new_btnW+inner_gap), new_y, new_btnW, btnHeight)
        btnInsert.Move(outer_margin + 1*(new_btnW+inner_gap), new_y, new_btnW, btnHeight)
        btnRetry.Move(outer_margin + 2*(new_btnW+inner_gap), new_y, new_btnW, btnHeight)
        btnClose.Move(outer_margin + 3*(new_btnW+inner_gap), new_y, new_btnW, btnHeight)
    }
    
    dlg.Show()
    userInput.Focus()
    ControlSend("{End}",, chatDisplay)
}

SendActionToWebhook(action, sel) {
    global g_Config
    url     := Trim(g_Config.Webhook["url"], ' "')
    method  := g_Config.Webhook["method"]
    headers := g_Config.Webhook["headers"]

    if (!url) {
        Notify("Webhook URL missing (see [webhook] in AiContextMenu.ini).")
        return
    }

    payload := ""
    if (action["key"] = "custom_prompt") {
        payload := "You are a helpful assistant. Your answer must be simple text, no markdown, no html, just pure simple text. Answer the following user prompt.`r`n`r`nPROMPT: " . action["system_content"]
    } else {
        payload := "You are a helpful assistant. Your answer must be simple text, no markdown, no html, just pure simple text. Fulfill the user's request based on the following prompt and text.`r`n`r`nPROMPT: " . action["system_content"] . "`r`n`r`nTEXT:`r`n" . sel
    }

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

        if (action["key"] = "custom_prompt") {
            ShowChatResponsePopup(action["name"], out, retryCallback)
        } else {
            ShowSimpleResponsePopup(action["name"], out, retryCallback)
        }

        if g_Config.Settings["show_notification"]
            Notify("Done (" resp.status ").")
    } else {
        retryCallback := (*) => SendActionToWebhook(action, sel)
        ShowSimpleResponsePopup(action["name"] " — Error " resp.status, resp.text, retryCallback)
        Notify("Webhook error (" resp.status ").")
    }
}

Notify(msg) {
    ToolTip(msg, A_ScreenWidth-400, 30, 20)
    SetTimer(() => ToolTip("",,,20), -1500) ; auto-hide after 1.5s
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
        if !IsObject(headers)
            headers := Map()
        if !headers.Has("Content-Type")
            headers["Content-Type"] := "application/json; charset=utf-8"

        h := ComObject("WinHttp.WinHttpRequest.5.1")
        h.Open(method, url, false)           ; synchronous
        for k, v in headers
            h.SetRequestHeader(k, v)
        h.Send(body)

        return { status: h.Status, text: h.ResponseText }

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
    global gProgress
    if IsObject(gProgress)
        return
    g := Gui("+AlwaysOnTop -SysMenu +ToolWindow")
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 14, g.MarginY := 12
    g.Add("Text", "w260", msg)
    g.Title := "Working"
    g.Show("AutoSize Center")
    gProgress := g
}

HideProgress() {
    global gProgress
    if IsObject(gProgress) {
        try gProgress.Destroy()
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
    compact := RegExReplace(sel, "\s+", " ")
    return StrLen(Trim(compact)) >= minLen
}
