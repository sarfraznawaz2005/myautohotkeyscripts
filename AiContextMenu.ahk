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
    ;if HasMeaningfulSelection(10) {
        TryPopupAfterSelection()
    ;}
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
    while (pos := RegExMatch(txt, "mi)^\s*\[(prompt_[^\]\r\n]+)\]\s*$", &m, pos)) {
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

InsertIntoTargetAndClose(dlg, editCtrl, target, *) {
    dlg.Hide()
    InsertIntoTarget(editCtrl.Value, target)
    dlg.Destroy()
}


ShowResponsePopup(title, body, retryCallback) {
    body := NormalizeWebhookText(body)

    dlg := Gui("+AlwaysOnTop -MinimizeBox", title)
    dlg.SetFont("s10", "Segoe UI")

    ; Response text (wrapped)
    e := dlg.AddEdit("w800 r25 ReadOnly Wrap VScroll", body)

    ; Compute positions from the edit control
    e.GetPos(&ex, &ey, &ew, &eh)
    margin := 12
    y := ey + eh + 14
    btnW := Floor((ew - margin*5) / 4)          ; 4 buttons, 5 gaps (L + 3 between + R)
    x0 := ex + margin


    ; 4 evenly spaced buttons
    btnCopy   := dlg.AddButton(Format("x{} y{} w{}", x0 + 0*(btnW+margin), y, btnW), "📋 Copy")
    btnInsert := dlg.AddButton(Format("x{} y{} w{}", x0 + 1*(btnW+margin), y, btnW), "📥 Insert")
    btnRetry  := dlg.AddButton(Format("x{} y{} w{}", x0 + 2*(btnW+margin), y, btnW), "🔄 Try Again")
    btnClose  := dlg.AddButton(Format("x{} y{} w{}", x0 + 3*(btnW+margin), y, btnW), "✖ Close")

    ; Wire up actions
    btnCopy.OnEvent("Click", (*) => (A_Clipboard := e.Value, Notify("Copied."), dlg.Destroy()))

    ; Capture the target now so Insert pastes into the app behind the popup
	target := SnapshotTarget()
	btnInsert.OnEvent("Click", InsertIntoTargetAndClose.Bind(dlg, e, target))

    btnRetry.OnEvent("Click", (*) => ( dlg.Destroy(), retryCallback() ))
    btnClose.OnEvent("Click", (*) => dlg.Destroy())

    dlg.Show()
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

    ; Compose one text block: system prompt + selected text
    payload := "Note: Your answer must be simple text, no markdown, no html, just pure simple text.`r`n`r`n" action["system_content"] "`r`n`r`n---`r`nTEXT:`r`n" sel

    json := '{'
        . '"contents":[{"parts":[{"text":"' . JsonEscape(payload) . '"}]}]'
        . '}'

    if (!headers.Has("Content-Type"))
        headers["Content-Type"] := "application/json; charset=utf-8"

	; add api key from environment variable
	ApiKey := EnvGet("GEMINI_API_KEY")
	
	url := url . ApiKey

    resp := HttpSend(url, method, json, headers)

    if (resp.status >= 200 && resp.status < 300) {
        out := ExtractGeminiText(resp.text)
        if (!out)
            out := resp.text
        ShowResponsePopup(action["name"], out, (*) => SendActionToWebhook(action, sel))
        if g_Config.Settings["show_notification"]
            Notify("Done (" resp.status ").")
    } else {
        ShowResponsePopup(action["name"] " — Error " resp.status, resp.text, (*) => SendActionToWebhook(action, sel))
        Notify("Webhook error (" resp.status ").")
    }
}


; Called from menu (we bind the action when creating items)
OnActionChosen(action, *) {
    global g_Config, g_LastAction, g_LastSelected

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
    g_LastSelected := sel
    SendActionToWebhook(action, sel)
}


OnCustomActionChosen(*) {
    global g_Config, g_LastSelection

    sel := GetSelectedText()

    ;if (!sel) {
    ;    Notify("No text selected.")
    ;    return
    ;}

    maxLen := g_Config.Settings["max_input_length"]
    if (maxLen > 0 && StrLen(sel) > maxLen) {
        MsgBox("Selection exceeds max_input_length (" maxLen ").")
        return
    }

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


Notify(msg) {
    ToolTip(msg, A_ScreenWidth-400, 30, 20)
    SetTimer(() => ToolTip("",,,20), -1500) ; auto-hide after 1.5s
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

JsonUnescape(s) {
    ; Basic escapes
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, "\\n", "`n")
    s := StrReplace(s, "\\r", "`r")
    s := StrReplace(s, "\\t", "`t")
    s := StrReplace(s, "\\\\", "\")

    ; Decode \uXXXX escapes (BMP only). Good enough for <, >, & and most symbols.
    while RegExMatch(s, "\\u([0-9A-Fa-f]{4})", &m) {
        code := Integer("0x" m[1])
        s := StrReplace(s, m[0], Chr(code))
    }
    return s
}

ExtractGeminiText(json) {
    if RegExMatch(json, '"text"\s*:\s*"((?:\\.|[^"])*)"', &m) {
        txt := m[1]
        return JsonUnescape(txt)
    }
    return ""
}

NormalizeWebhookText(s) {
    s := StrReplace(s, "\r\n", "`r`n")
    s := StrReplace(s, "\n",   "`n")
    s := StrReplace(s, "\r",   "`r")
    s := StrReplace(s, "\t",   "`t")
    s := StrReplace(s, '\"',   '"')
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
        ; Optional: MsgBox "Request failed:`n" e.Message
        throw e
    } finally {
        HideProgress()
    }
}


; Capture the current window & focused control so we can paste back into it later
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
        Sleep 150    ; give focus time to move to the target app
    }
    Send "^v"
    Sleep 40
    A_Clipboard := clip
}

; ----- v2 progress window -----
global gProgress := 0

ShowProgress(msg := "Please wait...") {
    global gProgress
    if IsObject(gProgress)  ; already showing
        return
    g := Gui("+AlwaysOnTop -SysMenu +ToolWindow")
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

; ---- Selection helpers (v2) ----
GetSelectedText(maxWait := 0.25) {
    saved := ClipboardAll()        ; v2: use function, not A_ClipboardAll
    try {
        A_Clipboard := ""          ; clear to detect a fresh copy
        Send("^c")
        if !ClipWait(maxWait)      ; wait for clipboard to receive content
            return ""
        return A_clipboard
    } finally {
        A_Clipboard := saved       ; always restore original clipboard
    }
}


HasMeaningfulSelection(minLen := 10) {
    sel := GetSelectedText()
    ; collapse whitespace to avoid accidental long runs of spaces/newlines
    compact := RegExReplace(sel, "\s+", " ")
    return StrLen(Trim(compact)) >= minLen
}




