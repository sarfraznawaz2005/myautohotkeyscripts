#Requires AutoHotkey v2.0+
#SingleInstance Force

; UpdateChecker.ahk
; Checks configured apps for updates based on a config file and prompts to install.
; Logging: errors.log and debug.log in script directory. Logs are deleted on startup.

; ---- Constants ----
CHECK_INTERVAL_MS := 5 * 60 * 60 * 1000 ; 5 hours
CONFIG_FILE := A_ScriptDir "\UpdateChecker.ini"

Timestamp() {
  return A_Now
}

; ---- Utilities ----
; Run command and capture stdout/stderr + exit code
RunAndCapture(cmd, showWindow := false) {
  try {
    shell := ComObject("WScript.Shell")
    windowStyle := showWindow ? 1 : 0
    cmdSwitch := showWindow ? "/k" : "/c"
    
    if (showWindow) {
        fullCmd := "cmd.exe " cmdSwitch " " cmd
        exitCode := shell.Run(fullCmd, windowStyle, false) ; don't wait
        return Map("code", exitCode, "out", "", "err", "")
    } else {
        stdoutFile := A_Temp "\" A_Now "_stdout.tmp"
        stderrFile := A_Temp "\" A_Now "_stderr.tmp"
        fullCmd := "cmd.exe " cmdSwitch " " cmd " 1> " stdoutFile " 2> " stderrFile
        exitCode := shell.Run(fullCmd, windowStyle, true) ; wait
        stdout := FileRead(stdoutFile)
        stderr := FileRead(stderrFile)
        FileDelete(stdoutFile)
        FileDelete(stderrFile)
        return Map("code", exitCode, "out", stdout, "err", stderr)
    }
  } catch as e {
    return Map("code", -1, "out", "", "err", e.Message)
  }
}

; Extract numeric version like 1.2.3 only when not attached to letters or hyphen
; Examples accepted: "codex-cli 0.25.0", "version: 1.2.3"
; Examples ignored: "v1.2.3", "1.2.3-foo", "foo-1.2.3"
ExtractVersionNumber(text) {
  local m := ""
  if RegExMatch(text, "(?<![A-Za-z0-9_-])(\d+(?:\.\d+)*)(?![A-Za-z0-9_-])", &m) {
    return m[1]
  }
  return ""
}

; Detect pre-release markers in text
IsPreRelease(text) {
  if !IsSet(text) || (text = "")
    return false
  lower := StrLower(text)
  return InStr(lower, "alpha") || InStr(lower, "beta") || InStr(lower, "preview") || InStr(lower, "rc")
}

; Compare semantic-ish versions (numeric components only). Returns -1,0,1
CompareVersions(a, b) {
  if (a = b)
    return 0
  pa := StrSplit(a, ".")
  pb := StrSplit(b, ".")
  maxLen := Max(pa.Length, pb.Length)
  Loop maxLen {
    ai := (A_Index <= pa.Length) ? Integer(pa[A_Index]) : 0
    bi := (A_Index <= pb.Length) ? Integer(pb[A_Index]) : 0
    if (ai < bi)
      return -1
    if (ai > bi)
      return 1
  }
  return 0
}

; ---- Config Handling ----
; Custom simple parser for repeated [apps] blocks with key=value lines.
LoadAppsFromConfig(path) {
  apps := []
  cur := Map()
  try {
    if !FileExist(path) {
      SaveAppsToConfig(CreateDefaultApps(), path)
    }
    content := FileRead(path, "UTF-8")
    ; Repair older files that accidentally stored literal \r\n sequences
    content := StrReplace(content, "\r\n", "`r`n")
  } catch as e {
    return apps
  }

  Loop Parse content, "`n", "`r" {
    line := Trim(A_LoopField)
    if (line = "" || SubStr(line, 1, 1) = ";")
      continue
    if (line = "[apps]") {
      if (cur.Count) {
        apps.Push(MapToApp(cur))
        cur := Map()
      }
      continue
    }
    pos := InStr(line, "=")
    if (pos > 0) {
      key := Trim(SubStr(line, 1, pos - 1))
      val := Trim(SubStr(line, pos + 1))
      cur[key] := val
    }
  }
  if (cur.Count) {
    apps.Push(MapToApp(cur))
  }
  ; Filter out completely empty entries
  valid := []
  for app in apps {
    if (app["name"] != "" || app["current_version_command"] != "" || app["check_command"] != "" || app["install_command"] != "")
      valid.Push(app)
  }
  return valid
}

MapToApp(m) {
  app := Map(
    "name", m.Has("name") ? m["name"] : "",
    "current_version_command", m.Has("current_version_command") ? m["current_version_command"] : "",
    "check_command", m.Has("check_command") ? m["check_command"] : "",
    "install_command", m.Has("install_command") ? m["install_command"] : ""
  )
  return app
}

SaveAppsToConfig(apps, path) {
  out := ""
  for app in apps {
    out .= "[apps]`r`n"
    out .= Format("name={1}`r`n", app["name"])
    out .= Format("current_version_command={1}`r`n", app["current_version_command"])
    out .= Format("check_command={1}`r`n", app["check_command"])
    out .= Format("install_command={1}`r`n`r`n", app["install_command"])
  }
  try {
    FileDelete(path)
  } catch {
  }
  try {
    FileAppend(out, path, "UTF-8")
  } catch as e {
  }
}

CreateDefaultApps() {
  return [
    Map(
      "name", "Gemini CLI",
      "current_version_command", "gemini --version",
      "check_command", "npm show @google/gemini-cli version",
      "install_command", "npm install -g @google/gemini-cli"
    ),
    Map(
      "name", "OpenAI Codex",
      "current_version_command", "codex --version",
      "check_command", "npm show @openai/codex version",
      "install_command", "npm install -g @openai/codex"
    )
  ]
}

; ---- Update Logic ----
CheckAppUpdate(app) {
  if (app["name"] = "" || app["check_command"] = "" || app["current_version_command"] = "") {
    return Map("updated", false, "hasUpdate", false, "message", "Invalid app config")
  }

  ; Get currently installed version
  res_current := RunAndCapture(app["current_version_command"])
  if (res_current["code"] != 0) {
    return Map("updated", false, "hasUpdate", false, "message", "Current version command failed", "ignored", true)
  }
  installed_text := Trim(res_current["out"])
  installed_ver := ExtractVersionNumber(installed_text)
  if (installed_ver = "") {
    return Map("updated", false, "hasUpdate", false, "message", "Installed version not found or ignored", "ignored", true)
  }
  if (IsPreRelease(installed_text)) {
    return Map("updated", false, "hasUpdate", false, "message", "Installed is pre-release", "ignored", true)
  }

  ; Get latest available version
  res_latest := RunAndCapture(app["check_command"])
  if (res_latest["code"] != 0) {
    return Map("updated", false, "hasUpdate", false, "message", "Check command failed for latest version", "ignored", true)
  }
  latest_text := Trim(res_latest["out"])
  latest_ver := ExtractVersionNumber(latest_text)
  if (latest_ver = "") {
    return Map("updated", false, "hasUpdate", false, "message", "Latest version not found or ignored", "ignored", true)
  }
  if (IsPreRelease(latest_text)) {
    return Map("updated", false, "hasUpdate", false, "message", "Latest is pre-release", "ignored", true)
  }

  cmp := CompareVersions(installed_ver, latest_ver)
  if (cmp < 0) {
    return Map("updated", false, "hasUpdate", true, "installed", installed_ver, "latest", latest_ver)
  } else {
    return Map("updated", false, "hasUpdate", false, "installed", installed_ver, "latest", latest_ver)
  }
}

InstallUpdate(app) {
  if (app["install_command"] = "") {
    return false
  }
  res := RunAndCapture(app["install_command"], true)
  if (res["code"] != 0) {
    return false
  }
  return true
}

; ---- UI / Orchestration ----
CheckNow(*) {
  try {
    apps := LoadAppsFromConfig(CONFIG_FILE)
    if (apps.Length = 0) {
      MsgBox("No apps configured.")
      return
    }
    for idx, app in apps {
      res := CheckAppUpdate(app)
      if res["hasUpdate"] {
        message := Format("Update available for {1}.`nInstalled: {2}`nLatest: {3}`nInstall now?", app["name"], res["installed"], res["latest"])
        resp := MsgBox(message, "Update Available", 0x4) ; Yes/No
        if (resp = "Yes") {
          InstallUpdate(app)
        }
      }
    }
  } catch as e {
  }
}

; ---- Main ----
try {
  apps := LoadAppsFromConfig(CONFIG_FILE)
  SetTimer(CheckNow, CHECK_INTERVAL_MS)
} catch as e {
}

; Check at startup too
CheckNow()