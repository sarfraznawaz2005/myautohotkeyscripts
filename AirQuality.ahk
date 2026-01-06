#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent(true)

;--------------------------------------------
; API: https://aqicn.org/scale
;--------------------------------------------

/* Sample Config

[AirQuality]
; API URL for fetching air quality data
api_url=https://api.waqi.info/feed/here/?token=962358b3ed1b05a8e26ad3132dc84838c393130f

; Check interval in hours (e.g., 1 = every 1 hour, 3 = every 3 hours)
check_interval_hours=1

; Custom labels for air quality levels
label_good=Good
label_moderate=Moderate
label_unhealthy=Unhealthy
label_cautious=Cautious
label_very_unhealthy=Very Unhealthy
label_hazardous=Hazardous

; Custom cautionary statements
statement_good=All is Well
statement_moderate=All is Well
statement_unhealthy=Unhealthy Condition
statement_cautious=Avoid prolonged outdoor
statement_very_unhealthy=Avoid going outdoor, keep windows closed!
statement_hazardous=Avoid going outdoor, wear a mask and keep windows closed!

; Notification icons: info, warning, error
icon_good=info
icon_moderate=info
icon_unhealthy=warning
icon_cautious=warning
icon_very_unhealthy=error
icon_hazardous=error

*/


; ---------- Global Variables ----------
global LOG_DEBUG := A_ScriptDir "\airdebug.log"
global CONFIG_FILE := A_ScriptDir "\airquality.ini"
global CONFIG

; ---------- Logging ----------
try FileDelete(LOG_DEBUG)

LogAQDebug(msg) {
    ;FileAppend(Format("[{1}] DEBUG: {2}`r`n", A_Now, msg), LOG_DEBUG)
}

LogAQDebug("Script started")

; Configuration loader
LoadAQConfig() {
    try {
        global CONFIG
        CONFIG := Map()

        ; API settings
        CONFIG["api_url"] := IniRead(CONFIG_FILE, "AirQuality", "api_url")
        CONFIG["check_interval_hours"] := IniRead(CONFIG_FILE, "AirQuality", "check_interval_hours")

        ; Labels
        CONFIG["label_good"] := IniRead(CONFIG_FILE, "AirQuality", "label_good")
        CONFIG["label_moderate"] := IniRead(CONFIG_FILE, "AirQuality", "label_moderate")
        CONFIG["label_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "label_unhealthy")
        CONFIG["label_cautious"] := IniRead(CONFIG_FILE, "AirQuality", "label_cautious")
        CONFIG["label_very_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "label_very_unhealthy")
        CONFIG["label_hazardous"] := IniRead(CONFIG_FILE, "AirQuality", "label_hazardous")

        ; Statements
        CONFIG["statement_good"] := IniRead(CONFIG_FILE, "AirQuality", "statement_good")
        CONFIG["statement_moderate"] := IniRead(CONFIG_FILE, "AirQuality", "statement_moderate")
        CONFIG["statement_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "statement_unhealthy")
        CONFIG["statement_cautious"] := IniRead(CONFIG_FILE, "AirQuality", "statement_cautious")
        CONFIG["statement_very_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "statement_very_unhealthy")
        CONFIG["statement_hazardous"] := IniRead(CONFIG_FILE, "AirQuality", "statement_hazardous")

        ; Icons
        CONFIG["icon_good"] := IniRead(CONFIG_FILE, "AirQuality", "icon_good")
        CONFIG["icon_moderate"] := IniRead(CONFIG_FILE, "AirQuality", "icon_moderate")
        CONFIG["icon_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "icon_unhealthy")
        CONFIG["icon_cautious"] := IniRead(CONFIG_FILE, "AirQuality", "icon_cautious")
        CONFIG["icon_very_unhealthy"] := IniRead(CONFIG_FILE, "AirQuality", "icon_very_unhealthy")
        CONFIG["icon_hazardous"] := IniRead(CONFIG_FILE, "AirQuality", "icon_hazardous")

        LogAQDebug("Configuration loaded")
        return true
    } catch as ex {
        LogAQDebug("Failed to load configuration: " . ex.Message)
        return false
    }
}

; ---------- Auto-execute Section ----------
try {
    LogAQDebug("Air Quality Checker starting up")

    if (!LoadAQConfig()) {
        LogAQDebug("Failed to load configuration, exiting")
        ExitApp
    }

    ; Set up timer for periodic checks
    checkInterval := Integer(CONFIG["check_interval_hours"]) * 3600000  ; Convert hours to milliseconds
    SetTimer(CheckAirQuality, checkInterval)
    LogAQDebug("Timer set for every " . CONFIG["check_interval_hours"] . " hour(s)")

    LogAQDebug("Air Quality Checker started successfully")

} catch as ex {
    LogAQDebug("Startup failed: " . ex.Message)
    ExitApp
}

; Function to get AQI level information
GetAQILevel(aqi) {
    if (aqi <= 50) {
        return Map(
            "level", CONFIG["label_good"],
            "statement", CONFIG["statement_good"],
            "icon", CONFIG["icon_good"]
        )
    } else if (aqi <= 100) {
        return Map(
            "level", CONFIG["label_moderate"],
            "statement", CONFIG["statement_moderate"],
            "icon", CONFIG["icon_moderate"]
        )
    } else if (aqi <= 150) {
        return Map(
            "level", CONFIG["label_unhealthy"],
            "statement", CONFIG["statement_unhealthy"],
            "icon", CONFIG["icon_unhealthy"]
        )
    } else if (aqi <= 200) {
        return Map(
            "level", CONFIG["label_cautious"],
            "statement", CONFIG["statement_cautious"],
            "icon", CONFIG["icon_cautious"]
        )
    } else if (aqi <= 300) {
        return Map(
            "level", CONFIG["label_very_unhealthy"],
            "statement", CONFIG["statement_very_unhealthy"],
            "icon", CONFIG["icon_very_unhealthy"]
        )
    } else {
        return Map(
            "level", CONFIG["label_hazardous"],
            "statement", CONFIG["statement_hazardous"],
            "icon", CONFIG["icon_hazardous"]
        )
    }
}

; Function to show native Windows notification
ShowNotification(aqi, levelInfo) {
    try {
        LogAQDebug("Showing Windows notification for AQI: " . aqi . ", Level: " . levelInfo["level"])

        ; TrayTip options: 1=Info, 2=Warning, 3=Error
        iconType := (levelInfo["icon"] = "error") ? 3 : (levelInfo["icon"] = "warning") ? 2 : 1

        statement := levelInfo["statement"]
        title := aqi . " - " . levelInfo["level"]

        TrayTip(statement, title, iconType)

        LogAQDebug("Windows notification displayed successfully")

    } catch as ex {
        LogAQDebug("Failed to show Windows notification: " . ex.Message)
    }
}

; Function to show error notifications using Windows notifications
ShowErrorNotification(message) {
    try {
        LogAQDebug("Showing error notification: " . message)

        TrayTip("Air Quality Error", message, 3)  ; 3 = Error icon

    } catch as ex {
        LogAQDebug("Failed to show error notification: " . ex.Message)
    }
}


; Function to check air quality periodically
CheckAirQuality() {
    LogAQDebug("Checking air quality")

    try {
        api_url := CONFIG["api_url"]
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", api_url, false)
        whr.Send()

        if (whr.Status == 200) {
            responseText := whr.ResponseText
            aqiMatch := RegExMatch(responseText, '"aqi":(\d+)', &match)
            if (aqiMatch) {
                currentAqi := Integer(match[1])
                LogAQDebug("Current AQI: " . currentAqi)

                levelInfo := GetAQILevel(currentAqi)
                ShowNotification(currentAqi, levelInfo)
            } else {
                LogAQDebug("AQI value not found in API response")
                ; Show error notification
                ShowErrorNotification("Failed to parse AQI from API response")
            }
        } else {
            LogAQDebug("API request failed with status: " . whr.Status)
            ShowErrorNotification("Failed to fetch air quality data from API")
        }
    } catch as ex {
        LogAQDebug("Error in CheckAirQuality: " . ex.Message)
        ShowErrorNotification("Error checking air quality: " . ex.Message)
    }
}

; test
;CheckAirQuality()

LogAQDebug("Script setup completed")