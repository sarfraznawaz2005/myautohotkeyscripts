#Requires AutoHotkey v2.0+
#SingleInstance Force

; UpdateChecker.ahk
; Checks configured apps for updates based on a config file and prompts to install.
; Logging: errors.log and debug.log in script directory. Logs are deleted on startup.

; ---- Constants ----
CHECK_INTERVAL_MS := 60 * 60 * 1000  ; 1 hour
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
    if (app["name"] != "" || app["check_command"] != "" || app["install_command"] != "" || app["version"] != "")
      valid.Push(app)
  }
  return valid
}

MapToApp(m) {
  app := Map(
    "name", m.Has("name") ? m["name"] : "",
    "version_text", m.Has("version") ? m["version"] : "",
    "version", "",
    "check_command", m.Has("check_command") ? m["check_command"] : "",
    "install_command", m.Has("install_command") ? m["install_command"] : ""
  )
  app["version"] := ExtractVersionNumber(app["version_text"])
  return app
}

SaveAppsToConfig(apps, path) {
  out := ""
  for app in apps {
    out .= "[apps]`r`n"
    out .= Format("name={1}`r`n", app["name"])
    out .= Format("version={1}`r`n", app["version"])
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
      "version", "0.2.1",
      "check_command", "gemini --version",
      "install_command", "npm install -g @google/gemini-cli"
    ),
    Map(
      "name", "OpenAI Codex",
      "version", "0.25.0",
      "check_command", "codex --version",
      "install_command", "npm install -g @openai/codex"
    )
  ]
}

; ---- Update Logic ----
CheckAppUpdate(app) {
  if (app["name"] = "" || app["check_command"] = "") {
    return Map("updated", false, "hasUpdate", false, "message", "Invalid app config")
  }

  res := RunAndCapture(Format("cmd.exe /C {1}", app["check_command"]))
  if (res["code"] != 0) {
    return Map("updated", false, "hasUpdate", false, "message", "Check command failed", "ignored", true)
  }

  installed_text := Trim(res["out"])
  installed_ver := ExtractVersionNumber(installed_text)
  if (installed_ver = "") {
    return Map("updated", false, "hasUpdate", false, "message", "Installed version ignored", "ignored", true)
  }

  if (IsPreRelease(installed_text)) {
    return Map("updated", false, "hasUpdate", false, "message", "Installed is pre-release", "ignored", true)
  }

  latest := app["version"]  ; already numeric
  if (latest = "") {
    return Map("updated", false, "hasUpdate", false, "message", "No latest version in config", "ignored", true)
  }

  cmp := CompareVersions(installed_ver, latest)
  if (cmp < 0) {
    return Map("updated", false, "hasUpdate", true, "installed", installed_ver, "latest", latest)
  } else {
    return Map("updated", false, "hasUpdate", false, "installed", installed_ver, "latest", latest)
  }
}

InstallUpdate(app) {
  if (app["install_command"] = "") {
    return false
  }
  res := RunAndCapture(Format("cmd.exe /C {1}", app["install_command"]), true)
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
    changed := false
    for idx, app in apps {
      res := CheckAppUpdate(app)
      if res["hasUpdate"] {
        resp := MsgBox(Format("Update available for {1}.`nInstalled: {2}`nLatest: {3}`nInstall now?", app["name"], res["installed"], res["latest"]), "Update Available", 0x4) ; Yes/No
        if (resp = "Yes") {
          if InstallUpdate(app) {
            ; Re-check version after install to refresh
            res2 := RunAndCapture(Format("cmd.exe /C {1}", app["check_command"]))
            installed_after := ExtractVersionNumber(Trim(res2["out"]))
          }
        }
      }
      ; Normalize and persist numeric-only version back to config when needed
      if (app["version_text"] != "" && app["version_text"] != app["version"]) {
        changed := true
      }
    }
    if changed {
      SaveAppsToConfig(apps, CONFIG_FILE)
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
