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
global LOG_AQ_DEBUG := A_ScriptDir "\airdebug.log"
global AQ_CONFIG_FILE := A_ScriptDir "\airquality.ini"
global AQ_CONFIG

; ---------- Logging ----------
try FileDelete(LOG_AQ_DEBUG)

LogAQDebug(msg) {
    ;FileAppend(Format("[{1}] DEBUG: {2}`r`n", A_Now, msg), LOG_AQ_DEBUG)
}

LogAQDebug("Script started")

; Configuration loader
LoadAQConfig() {
    try {
        global AQ_CONFIG
        AQ_CONFIG := Map()

        ; API settings
        AQ_CONFIG["api_url"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "api_url")
        AQ_CONFIG["check_interval_hours"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "check_interval_hours")

        ; Labels
        AQ_CONFIG["label_good"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_good")
        AQ_CONFIG["label_moderate"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_moderate")
        AQ_CONFIG["label_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_unhealthy")
        AQ_CONFIG["label_cautious"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_cautious")
        AQ_CONFIG["label_very_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_very_unhealthy")
        AQ_CONFIG["label_hazardous"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "label_hazardous")

        ; Statements
        AQ_CONFIG["statement_good"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_good")
        AQ_CONFIG["statement_moderate"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_moderate")
        AQ_CONFIG["statement_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_unhealthy")
        AQ_CONFIG["statement_cautious"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_cautious")
        AQ_CONFIG["statement_very_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_very_unhealthy")
        AQ_CONFIG["statement_hazardous"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "statement_hazardous")

        ; Icons
        AQ_CONFIG["icon_good"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_good")
        AQ_CONFIG["icon_moderate"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_moderate")
        AQ_CONFIG["icon_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_unhealthy")
        AQ_CONFIG["icon_cautious"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_cautious")
        AQ_CONFIG["icon_very_unhealthy"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_very_unhealthy")
        AQ_CONFIG["icon_hazardous"] := IniRead(AQ_CONFIG_FILE, "AirQuality", "icon_hazardous")

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
    checkAQInterval := Integer(AQ_CONFIG["check_interval_hours"]) * 3600000  ; Convert hours to milliseconds
    SetTimer(CheckAirQuality, checkAQInterval)
    LogAQDebug("Timer set for every " . AQ_CONFIG["check_interval_hours"] . " hour(s)")

    LogAQDebug("Air Quality Checker started successfully")

} catch as ex {
    LogAQDebug("Startup failed: " . ex.Message)
    ExitApp
}

; Function to get AQI level information
GetAQILevel(aqi) {
    if (aqi <= 50) {
        return Map(
            "level", AQ_CONFIG["label_good"],
            "statement", AQ_CONFIG["statement_good"],
            "icon", AQ_CONFIG["icon_good"]
        )
    } else if (aqi <= 100) {
        return Map(
            "level", AQ_CONFIG["label_moderate"],
            "statement", AQ_CONFIG["statement_moderate"],
            "icon", AQ_CONFIG["icon_moderate"]
        )
    } else if (aqi <= 150) {
        return Map(
            "level", AQ_CONFIG["label_unhealthy"],
            "statement", AQ_CONFIG["statement_unhealthy"],
            "icon", AQ_CONFIG["icon_unhealthy"]
        )
    } else if (aqi <= 200) {
        return Map(
            "level", AQ_CONFIG["label_cautious"],
            "statement", AQ_CONFIG["statement_cautious"],
            "icon", AQ_CONFIG["icon_cautious"]
        )
    } else if (aqi <= 300) {
        return Map(
            "level", AQ_CONFIG["label_very_unhealthy"],
            "statement", AQ_CONFIG["statement_very_unhealthy"],
            "icon", AQ_CONFIG["icon_very_unhealthy"]
        )
    } else {
        return Map(
            "level", AQ_CONFIG["label_hazardous"],
            "statement", AQ_CONFIG["statement_hazardous"],
            "icon", AQ_CONFIG["icon_hazardous"]
        )
    }
}

; Function to show native Windows notification
ShowAQNotification(aqi, levelInfo) {
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
ShowAQErrorNotification(message) {
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
        api_url := AQ_CONFIG["api_url"]
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
                ShowAQNotification(currentAqi, levelInfo)
            } else {
                LogAQDebug("AQI value not found in API response")
                ; Show error notification
                ShowAQErrorNotification("Failed to parse AQI from API response")
            }
        } else {
            LogAQDebug("API request failed with status: " . whr.Status)
            ShowAQErrorNotification("Failed to fetch air quality data from API")
        }
    } catch as ex {
        LogAQDebug("Error in CheckAirQuality: " . ex.Message)
        ShowAQErrorNotification("Error checking air quality: " . ex.Message)
    }
}

; Also check on script startup
; CheckAirQuality()

LogAQDebug("Script setup completed")