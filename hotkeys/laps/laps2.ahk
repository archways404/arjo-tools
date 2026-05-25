#Requires AutoHotkey v2.0

F9:: {
    if !WinExist("LAPS UI") {
        MsgBox "LAPS UI is not open."
        return
    }
    controls := WinGetControlsHwnd("LAPS UI")
    output := ""
    for hwnd, v in controls {
        output .= ControlGetClassNN(hwnd) . "`n"
    }
    MsgBox output
}
