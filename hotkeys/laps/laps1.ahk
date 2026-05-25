F8:: {
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    pcName := A_Clipboard
    if (pcName = "") {
        MsgBox "No text selected."
        return
    }

    Run 'pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\un024247\Gitprojects\arjo-tools\hotkeys\laps\laps-launch.ps1"'

    WinWait "LAPS UI", , 15
    if !WinExist("LAPS UI") {
        MsgBox "LAPS UI did not open."
        return
    }
    WinActivate "LAPS UI"
    Sleep 800

    ; Type PC name into computer name field
    ControlSetText pcName, "WindowsForms10.EDIT.app.0.141b42a_r17_ad11", "LAPS UI"
    Sleep 200

    ; Click Search
    ControlClick "WindowsForms10.BUTTON.app.0.141b42a_r17_ad11", "LAPS UI"
    Sleep 1500

    ; Click Set
    ControlClick "WindowsForms10.BUTTON.app.0.141b42a_r17_ad12", "LAPS UI"
    Sleep 500

    ; Get password from Password field (second edit)
    pass := ControlGetText("WindowsForms10.EDIT.app.0.141b42a_r17_ad12", "LAPS UI")
    A_Clipboard := pass

    ; Close LAPS UI
    ControlClick "WindowsForms10.BUTTON.app.0.141b42a_r17_ad13", "LAPS UI"

    MsgBox "Password copied to clipboard:`n`n" pass
}
