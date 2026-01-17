#Requires AutoHotkey v2.0+
#SingleInstance Force
;#Warn

; ---------- Configuration ----------
global INI_FILE_BRIGHTNESS := A_ScriptDir "\BrightnessCheck.ini"
global MIN_BRIGHTNESS := 50  ; Default fallback value

; ---------- Logging ----------
global LOG_DEBUG_BRIGHTNESS := A_ScriptDir "\debug.log"

try FileDelete(LOG_DEBUG_BRIGHTNESS)

LogDebugBrightness(msg) {
  ;FileAppend(Format("[{1}] DEBUG: {2}`r`n", A_Now, msg), LOG_DEBUG_BRIGHTNESS)
}

; ---------- Load Configuration ----------
LoadConfigurationBrightness() {
  global MIN_BRIGHTNESS, INI_FILE_BRIGHTNESS
  local exc

  try {
    ; Read brightness setting from INI file
    local iniBrightness := IniRead(INI_FILE_BRIGHTNESS, "Settings", "Brightness", "")
    if (iniBrightness != "") {
      MIN_BRIGHTNESS := Integer(iniBrightness)
      LogDebugBrightness("Loaded brightness from INI file: " MIN_BRIGHTNESS "%")
    } else {
      LogDebugBrightness("No brightness setting in INI file, using default: " MIN_BRIGHTNESS "%")
      ; Create INI file with default value
      IniWrite(String(MIN_BRIGHTNESS), INI_FILE_BRIGHTNESS, "Settings", "Brightness")
      LogDebugBrightness("Created INI file with default brightness value")
    }
  } catch as exc {
    LogDebugBrightness("Error loading configuration: " exc.Message)
    LogDebugBrightness("Using default brightness value: " MIN_BRIGHTNESS "%")
  }
}

; ---------- Main Function ----------
GetCurrentBrightnessBrightness() {
  local exc
  try {
    LogDebugBrightness("Attempting to get brightness via WMI...")

    ; WMI approach using COM objects
    local wmi := ComObject("WbemScripting.SWbemLocator")
    local service := wmi.ConnectServer(".", "root\WMI")

    ; Query WmiMonitorBrightness
    local brightnessQuery := service.ExecQuery("SELECT * FROM WmiMonitorBrightness")

    local brightness := 0
    local brightnessLevels := 0
    for brightnessItem in brightnessQuery {
      brightness := brightnessItem.CurrentBrightness
      brightnessLevels := brightnessItem.Levels
      LogDebugBrightness("Found brightness value: " brightness ", levels: " brightnessLevels)
      break
    }

    ; Convert to percentage if levels are available
    if (brightnessLevels > 0) {
      brightness := Round((brightness / (brightnessLevels - 1)) * 100)
      LogDebugBrightness("Converted brightness to percentage: " brightness "%")
    }

    if (brightness = 0) {
      LogDebugBrightness("No brightness found via WmiMonitorBrightness, trying alternative...")

      ; Alternative: Check if this is a laptop with built-in display
      local brightnessQuery2 := service.ExecQuery("SELECT * FROM WmiMonitorBrightness WHERE Active = TRUE")
      for brightnessItem2 in brightnessQuery2 {
        brightness := brightnessItem2.CurrentBrightness
        brightnessLevels := brightnessItem2.Levels
        if (brightnessLevels > 0) {
          brightness := Round((brightness / (brightnessLevels - 1)) * 100)
        }
        LogDebugBrightness("Found brightness via Active filter: " brightness "%")
        break
      }
    }

    return brightness
  } catch as exc {
    LogDebugBrightness("Error getting brightness: " exc.Message)
    return -1
  }
}

; ---------- Set Brightness Function ----------
SetBrightness(targetBrightness) {
  local exc
  try {
    LogDebugBrightness("Attempting to set brightness to " targetBrightness "% via WMI...")

    ; WMI approach using COM objects
    local wmi := ComObject("WbemScripting.SWbemLocator")
    local service := wmi.ConnectServer(".", "root\WMI")

    ; Get brightness levels first
    local brightnessQuery := service.ExecQuery("SELECT * FROM WmiMonitorBrightness")
    local brightnessLevels := 0

    for brightnessItem in brightnessQuery {
      brightnessLevels := brightnessItem.Levels
      LogDebugBrightness("Monitor brightness levels: " brightnessLevels)
      break
    }

    ; Convert percentage to monitor value if levels available
    local brightnessValue := targetBrightness
    if (brightnessLevels > 0) {
      brightnessValue := Round((targetBrightness / 100) * (brightnessLevels - 1))
      LogDebugBrightness("Converted " targetBrightness "% to monitor value: " brightnessValue)
    }

    ; Query WmiMonitorBrightnessMethods
    local methodsQuery := service.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")

    for methodItem in methodsQuery {
      ; WmiSetBrightness(Timeout, Brightness) - Note: Timeout comes first!
      ; Timeout is in seconds
      methodItem.WmiSetBrightness(10, brightnessValue)
      LogDebugBrightness("WMI brightness set to " brightnessValue)

      ; Wait for the change to take effect
      Sleep(500)

      ; Verify the change was applied
      local currentAfterSet := GetCurrentBrightnessBrightness()
      LogDebugBrightness("Brightness after WMI set: " currentAfterSet "%")

      if (currentAfterSet = targetBrightness) {
        return true
      }

      LogDebugBrightness("WMI method did not set brightness correctly, trying PowerShell...")

      ; Fallback: Try using PowerShell with Get-WmiObject
      ; Note: WmiSetBrightness(Timeout, Brightness)
      local psCommand := Format('(Get-WmiObject -Namespace root\wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(5, {1})', brightnessValue)
      local psResult := RunWait("powershell.exe -Command " psCommand, , "Hide")

      Sleep(500)

      ; Verify PowerShell result
      local currentAfterPS := GetCurrentBrightnessBrightness()
      LogDebugBrightness("Brightness after PowerShell set: " currentAfterPS "%")

      return (currentAfterPS = targetBrightness)
    }

    LogDebugBrightness("No brightness methods found")
    return false
  } catch as exc {
    LogDebugBrightness("Error setting brightness: " exc.Message)
    return false
  }
}

; ---------- Main Execution ----------
try {
  LogDebugBrightness("Script started")

  ; Load configuration from INI file
  LoadConfigurationBrightness()

  brightness := GetCurrentBrightnessBrightness()

  if (brightness >= 0 && brightness <= 100) {
    LogDebugBrightness("Current brightness: " brightness "%")

    ; Check if brightness is NOT equal to target value
    if (brightness != MIN_BRIGHTNESS) {
      LogDebugBrightness("Brightness " brightness "% is not equal to target " MIN_BRIGHTNESS "%, adjusting...")

      success := SetBrightness(MIN_BRIGHTNESS)
      if (success) {
        LogDebugBrightness("Successfully set brightness to " MIN_BRIGHTNESS "%")
        ; Show native notification
        TrayTip("Brightness Adjusted", "Brightness was " brightness "% -> Set to " MIN_BRIGHTNESS "%")
        ; Wait for notification to be visible
        Sleep(2000)
      } else {
        LogDebugBrightness("Failed to adjust brightness")
        MsgBox("Failed to adjust brightness from " brightness "% to " MIN_BRIGHTNESS "%", "Error", "Icon!")
      }
    } else {
      LogDebugBrightness("Brightness " brightness "% equals target " MIN_BRIGHTNESS "%, no adjustment needed")
      ; No notification when brightness already matches target
    }
  } else {
    LogDebugBrightness("Failed to get valid brightness value")
    MsgBox("Unable to detect screen brightness. Make sure your display supports brightness control.", "Error", "Icon!")
  }

  LogDebugBrightness("Script completed successfully")
} catch as exc {
  LogDebugBrightness("Script error: " exc.Message)
  MsgBox("An error occurred: " exc.Message, "Error", "Icon!")
}

; ---------- Cleanup ----------
;ExitApp
