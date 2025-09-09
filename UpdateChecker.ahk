#Requires AutoHotkey v2.0+
#Warn VarUnset, Off
#SingleInstance Force

; UpdateChecker.ahk
; Checks configured apps for updates based on a config file and prompts to install.

; ---- Constants ----
CONFIG_FILE := A_ScriptDir "\UpdateChecker.ini"

; ---- Utilities ----
; Run command and capture stdout/stderr + exit code with timeout
RunAndCapture(cmd, showWindow := false, timeout_ms := 30000) {
  try {
    if (showWindow) {
        ; Run through cmd.exe to ensure PATH is available
        fullCmd := "cmd.exe /c " cmd
        Run(fullCmd, , "Max")
        return Map("code", 0, "out", "", "err", "")
    } else {
      stdoutFile := A_Temp "\" A_Now "_stdout.tmp"
      stderrFile := A_Temp "\" A_Now "_stderr.tmp"
      fullCmd := "cmd.exe /c " cmd " 1> `"" stdoutFile "`" 2> `"" stderrFile "`" "
      pid := 0
      Run(fullCmd, , "Hide", &pid)
        if (pid == 0) {
          FileDelete(stdoutFile)
          FileDelete(stderrFile)
          return Map("code", -1, "out", "", "err", "Failed to launch command")
        }
        ; Wait for process to finish with timeout
        startTime := A_TickCount
        Loop {
          try {
            if !ProcessExist(pid) {
              Sleep(200) ; Wait a bit for file handles to be released
              exitCode := 0 ; Assume success if process ended
              break
            }
          } catch as e {
            ; If ProcessExist fails, assume process ended
            Sleep(200)
            exitCode := 0
            break
          }
          if (A_TickCount - startTime > timeout_ms) {
            try ProcessClose(pid)
            exitCode := -2
            break
          }
          Sleep(100)
        }
        if (exitCode == -2) {
          FileDelete(stdoutFile)
          FileDelete(stderrFile)
          return Map("code", -2, "out", "", "err", "Command timed out after " . timeout_ms . "ms")
        }
      stdout := FileRead(stdoutFile)
      stderr := FileRead(stderrFile)
      try FileDelete(stdoutFile)
      try FileDelete(stderrFile)
        return Map("code", exitCode, "out", stdout, "err", stderr)
    }
  } catch as e {
    return Map("code", -1, "out", "", "err", e.Message)
  }
}

; Extract version string like 1.2.3 or 1.2.3-alpha, handling common prefixes
; Examples accepted: "codex-cli 0.25.0", "version: 1.2.3", "v1.2.3", "crush version v0.7.6", "1.2.3-alpha"
; Examples ignored: "foo-1.2.3"
ExtractVersionNumber(text) {
  ; Remove common prefixes (case insensitive)
  text := RegExReplace(text, "^(?i)(v|version|ver)[:\s]*", "")
  ; Try to match version patterns including pre-release, preferring longer matches
  local m := ""

  ; Find all version-like patterns and return the longest one
  versions := []
  while RegExMatch(text, "(\d+(?:\.\d+)+(?:-[a-zA-Z0-9]+(?:\.\d+)*)?)", &m, versions.Length ? versions[versions.Length].Pos + versions[versions.Length].Len : 1) {
    versions.Push({match: m[1], pos: m.Pos, len: m.Len})
  }

  ; Return the longest version found
  if (versions.Length > 0) {
    longest := ""
    for v in versions {
      if (StrLen(v.match) > StrLen(longest)) {
        longest := v.match
      }
    }
    return longest
  }

  ; Fallback: simple pattern match
  if RegExMatch(text, "(\d+(?:\.\d+)+)", &m) {
    return m[1]
  }

  return ""
}

; Detect pre-release markers in text
IsPreRelease(text) {
  if !IsSet(text) || (text == "") {
    return false
  }
  lower := StrLower(text)
  return InStr(lower, "alpha") || InStr(lower, "beta") || InStr(lower, "preview") || InStr(lower, "rc")
}

; Parse version into main and pre-release parts
ParseVersion(ver) {
  ; Remove build metadata
  ver := RegExReplace(ver, "\+.*$", "")
  ; Split into main and pre
  if InStr(ver, "-") {
    parts := StrSplit(ver, "-", , 2)
    main := parts[1]
    pre := parts[2]
  } else {
    main := ver
    pre := ""
  }
  ; Split main into numbers
  mainParts := StrSplit(main, ".")
  nums := []
  for p in mainParts {
    nums.Push(IsInteger(p) ? Integer(p) : 0)
  }
  return {nums: nums, pre: pre}
}

; Compare semantic versions (full semver support with pre-release). Returns -1,0,1
CompareVersions(a, b) {
  if (a == b) {
    return 0
  }
  if (a == "" && b != "") {
    return -1
  }
  if (b == "" && a != "") {
    return 1
  }
  pa := ParseVersion(a)
  pb := ParseVersion(b)
  ; Compare main version
  maxLen := Max(pa.nums.Length, pb.nums.Length)
  Loop maxLen {
    ai := (A_Index <= pa.nums.Length) ? pa.nums[A_Index] : 0
    bi := (A_Index <= pb.nums.Length) ? pb.nums[A_Index] : 0
    if (ai < bi)
      return -1
    if (ai > bi)
      return 1
  }
  ; Main equal, compare pre
  if (pa.pre == "" && pb.pre != "")
    return 1
  if (pb.pre == "" && pa.pre != "")
    return -1
  if (pa.pre == pb.pre)
    return 0
  ; Compare pre lexicographically
  return (pa.pre < pb.pre) ? -1 : 1
}

; ---- Config Handling ----
; Custom simple parser for [settings] and repeated [apps] blocks with key=value lines.
LoadUpdateCheckerConfig(path) {
  apps := []
  settings := Map("check_interval_hours", 5)
  cur := Map()
  inSettings := false
  inApps := false
  try {
    if !FileExist(path) {
      out := "[settings]`r`ncheck_interval_hours=5`r`n`r`n"
      for app in CreateDefaultApps() {
        out .= "[apps]`r`n"
        out .= Format("name={1}`r`n", app["name"])
        out .= Format("current_version_command={1}`r`n", app["current_version_command"])
        out .= Format("check_command={1}`r`n", app["check_command"])
        out .= Format("install_command={1}`r`n`r`n", app["install_command"])
      }
      FileAppend(out, path, "UTF-8")
    }
    content := FileRead(path, "UTF-8")
    ; Repair older files that accidentally stored literal \r\n sequences
    content := StrReplace(content, "\r\n", "`r`n")
  } catch as e {
    return Map("apps", apps, "settings", settings)
  }

  Loop Parse content, "`n", "`r" {
    line := Trim(A_LoopField)
    if (line = "" || SubStr(line, 1, 1) = ";")
      continue
    if (line == "[settings]") {
      inSettings := true
      inApps := false
      continue
    }
    if (line == "[apps]") {
      inApps := true
      inSettings := false
      if (cur.Count) {
        apps.Push(MapToApp(cur))
        cur := Map()
      }
      continue
    }
    if inSettings {
      pos := InStr(line, "=")
      if (pos > 0) {
        key := Trim(SubStr(line, 1, pos - 1))
        val := Trim(SubStr(line, pos + 1))
        if (key == "check_interval_hours" && IsInteger(val)) {
          settings[key] := Integer(val)
        }
      }
    } else if inApps {
      pos := InStr(line, "=")
      if (pos > 0) {
        key := Trim(SubStr(line, 1, pos - 1))
        val := Trim(SubStr(line, pos + 1))
        cur[key] := val
      }
    }
  }
  if (cur.Count) {
    apps.Push(MapToApp(cur))
  }
  ; Filter out invalid entries
  valid := []
  for app in apps {
    if ValidateApp(app)
      valid.Push(app)
  }
  return Map("apps", valid, "settings", settings)
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

; Validate app config for basic safety and completeness
ValidateApp(app) {
  if (Type(app["name"]) != "String" || app["name"] == "") {
    return false
  }
  if (Type(app["current_version_command"]) != "String" || app["current_version_command"] == "") {
    return false
  }
  if (Type(app["check_command"]) != "String" || app["check_command"] == "") {
    return false
  }
  if (Type(app["install_command"]) != "String") {
    return false ; install can be empty
  }
  ; Basic safety check: avoid commands with dangerous patterns
  dangerous := ["rm ", "del ", "format ", "shutdown"]
  for pat in dangerous {
    if InStr(app["current_version_command"], pat) || InStr(app["check_command"], pat) || InStr(app["install_command"], pat)
      return false
  }
  return true
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
  ; Use atomic write with temporary file
  tempPath := path ".tmp"
  try {
    FileAppend(out, tempPath, "UTF-8")
    FileMove(tempPath, path, 1) ; Overwrite existing
  } catch as e {
    ; Clean up temp file if move failed
    try {
      FileDelete(tempPath)
    } catch {
    }
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

InstallUpdate(app) {
  if (app["install_command"] == "") {
    return false
  }
  res := RunAndCapture(app["install_command"], true)
  if (res["code"] != 0) {
    return false
  }
  return true
}

; ---- UI / Orchestration ----
ShowUpdateGUI(appName, installedVer, latestVer) {
  result := MsgBox(Format("App: {1}`n`nInstalled:  {2}`nAvailable: {3}`n`nDo you want to install?", appName, installedVer, latestVer), "Update Available", "YesNo")
  return (result == "Yes") ? "Yes" : "No"
}
CheckNow(*) {
  try {
    config := LoadUpdateCheckerConfig(CONFIG_FILE)
    apps := config["apps"]
    if (apps.Length == 0) {
      MsgBox("No apps configured.")
      return
    }
    ; Parallel run current_version
    currentPids := Map()
    currentTempFiles := Map()
    for app in apps {
      stdoutFile := A_Temp "\" A_Now "_" StrReplace(app["name"], " ", "_") "_stdout.tmp"
      stderrFile := A_Temp "\" A_Now "_" StrReplace(app["name"], " ", "_") "_stderr.tmp"
      fullCmd := "cmd.exe /c " app["current_version_command"] " 1> `"" stdoutFile "`" 2> `"" stderrFile "`" "
      pid := 0
      Run(fullCmd, , "Hide", &pid)
      currentPids[app["name"]] := pid
      currentTempFiles[app["name"]] := {stdout: stdoutFile, stderr: stderrFile}
    }
    ; Wait for all current_version
    Loop {
      allDone := true
      for name, pid in currentPids {
        if ProcessExist(pid) {
          allDone := false
          break
        }
      }
      if allDone
        break
      Sleep(100)
    }
    ; Read current outputs
    currentOutputs := Map()
    for name, files in currentTempFiles {
      stdout := FileRead(files.stdout)
      stderr := FileRead(files.stderr)
      currentOutputs[name] := {out: Trim(stdout), err: Trim(stderr)}
      FileDelete(files.stdout)
      FileDelete(files.stderr)
    }
    ; Parallel run check_command
    checkPids := Map()
    checkTempFiles := Map()
    for app in apps {
      stdoutFile := A_Temp "\" A_Now "_" StrReplace(app["name"], " ", "_") "_check_stdout.tmp"
      stderrFile := A_Temp "\" A_Now "_" StrReplace(app["name"], " ", "_") "_check_stderr.tmp"
      fullCmd := "cmd.exe /c " app["check_command"] " 1> `"" stdoutFile "`" 2> `"" stderrFile "`" "
      pid := 0
      Run(fullCmd, , "Hide", &pid)
      checkPids[app["name"]] := pid
      checkTempFiles[app["name"]] := {stdout: stdoutFile, stderr: stderrFile}
    }
    ; Wait for all check
    Loop {
      allDone := true
      for name, pid in checkPids {
        if ProcessExist(pid) {
          allDone := false
          break
        }
      }
      if allDone
        break
      Sleep(100)
    }
    ; Read check outputs
    checkOutputs := Map()
    for name, files in checkTempFiles {
      stdout := FileRead(files.stdout)
      stderr := FileRead(files.stderr)
      checkOutputs[name] := {out: Trim(stdout), err: Trim(stderr)}
      FileDelete(files.stdout)
      FileDelete(files.stderr)
    }
    ; Process each app
    for app in apps {
      name := app["name"]
      res_current := currentOutputs[name]
      if (res_current.err != "") {
        TrayTip("Update check failed for " . name, "Current version command failed: " . res_current.err, 3)
        continue
      }
      installed_text := res_current.out
      installed_ver := ExtractVersionNumber(installed_text)
      if (installed_ver == "") {
        TrayTip("Update check failed for " . name, "Installed version not found in output: '" . installed_text . "'", 3)
        continue
      }
      if (IsPreRelease(installed_text)) {
        TrayTip("Update check failed for " . name, "Installed version is pre-release: '" . installed_text . "'", 3)
        continue
      }
      res_latest := checkOutputs[name]
      if (res_latest.err != "") {
        TrayTip("Update check failed for " . name, "Check command failed for latest version: " . res_latest.err, 3)
        continue
      }
      latest_text := res_latest.out
      latest_ver := ExtractVersionNumber(latest_text)
      if (latest_ver == "") {
        TrayTip("Update check failed for " . name, "Latest version not found in output: '" . latest_text . "'", 3)
        continue
      }
      if (IsPreRelease(latest_text)) {
        TrayTip("Update check failed for " . name, "Latest version is pre-release: '" . latest_text . "'", 3)
        continue
      }
      cmp := CompareVersions(installed_ver, latest_ver)
      if (cmp < 0) {
        resp := ShowUpdateGUI(name, installed_ver, latest_ver)
        if (resp == "Yes") {
          if !InstallUpdate(app) {
            TrayTip("Update failed for " . name, "Installation command failed", 3)
          }
        }
      }
    }
  } catch as e {
    TrayTip("Update checker error", e.Message, 3)
  }
}

; ---- Main ----
try {
  config := LoadUpdateCheckerConfig(CONFIG_FILE)
  settings := config["settings"]
  CHECK_INTERVAL_MS := settings["check_interval_hours"] * 60 * 60 * 1000
  SetTimer(CheckNow, CHECK_INTERVAL_MS)
} catch as e {
}

; Check at startup too
CheckNow()