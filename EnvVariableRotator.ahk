; ENVIRONMENT VARIABLE ROTATIONS SCRIPT
; See EnvVariableRotator.ini

EnvironmentVariableRotator.Start(A_ScriptDir "\EnvVariableRotator.ini")

class EnvironmentVariableRotator {
    ; --- PUBLIC METHOD: Call this from your main script to start the rotator ---
    static Start(ini_path) {
        if not FileExist(ini_path) {
            ;MsgBox("Rotation INI file not found: " . ini_path, "Rotation Script Error", 48)
            return
        }

        local rotator_app := EnvironmentVariableRotator(ini_path)
        rotator_app.Run()
    }

    ; --- INTERNAL PROPERTIES AND METHODS (DO NOT CALL DIRECTLY) ---
    __New(ini_path) {
        this.ini_path := ini_path
    }

    Run() {
        local ini_content := FileRead(this.ini_path, "CP0")
        local sections := []
        Loop Parse ini_content, "`n", "`r" {
            if RegExMatch(A_LoopField, "^\s*\[([^\]]+)\]\s*$", &m)
                sections.Push(m[1])
        }

        local rotators_started := 0
        for _, section in sections {
            local task := EnvironmentVariableRotator.RotatorTask(section, this.ini_path)
            if (task.LoadFromIni()) {
                task.Start()
                rotators_started++
            }
        }

        if (rotators_started = 0) {
            ;MsgBox("No valid rotator configurations found in " . this.ini_path, "Script Info", 64)
        }
    }

    ; --- NESTED CLASS: Handles the logic for a single environment variable ---
    class RotatorTask {
        __New(env_var, ini_path) {
            this.env_var := env_var
            this.ini_path := ini_path
            this.interval := 0
            this.notify := 0
            this.values := []
            this.current_index := 1
        }

        LoadFromIni() {
            try {
                this.interval := IniRead(this.ini_path, this.env_var, "interval", 0)
                this.notify := IniRead(this.ini_path, this.env_var, "notify", 0)

                local i := 1
                loop {
                    local value := IniRead(this.ini_path, this.env_var, i, "")
                    if (value = "")
                        break
                    this.values.Push(value)
                    i++
                }
                return this.values.Length > 0 && this.interval > 0
            } catch as e {
                ;this.Log("Error loading configuration: " . e.Message)
                return false
            }
        }

        Start() {
            this.Rotate()
            SetTimer(this.Rotate.Bind(this), this.interval * 60 * 1000)
            ;this.Log("Timer started. Interval: " . this.interval . " minutes.")
        }

        Rotate() {
            local value_to_set := this.values[this.current_index]

            try {

                EnvSet(this.env_var, value_to_set)
                RegWrite(value_to_set, "REG_SZ", "HKEY_CURRENT_USER\Environment", this.env_var)
                ;this.Log("Set " . this.env_var . " in registry.")

                try {
                    ; inform apps that environment variable was changed!
                    DllCall("SendMessageTimeout", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0, "Ptr", "Environment", "UInt", 2, "UInt", 1000, "Ptr", 0)
                } catch as e {
                    this.Log("EnvironmentVariableRotator: Non-critical error broadcasting environment change.")
                }

                if (this.notify) {
                    TrayTip(this.env_var . " set to: " . value_to_set, "Environment Variable Rotated", 1)
                    SetTimer(() => TrayTip(), -5000)
                }
            } catch as e {
                ;this.Log("Failed to set environment variable: " . e.Message)
                TrayTip("Rotation Failed", "Could not set " . this.env_var, 3)
                SetTimer(() => TrayTip(), -5000)
            }
            this.current_index := (this.current_index >= this.values.Length) ? 1 : this.current_index + 1
        }

        Log(message) {
            OutputDebug("[" . this.env_var . "] " . message . "`n")
        }
    }
}