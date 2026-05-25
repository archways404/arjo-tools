#Requires AutoHotkey v2.0

F7:: {
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    name := A_Clipboard
    if (name = "") {
        MsgBox "No text selected."
        return
    }
    Run 'pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\un024247\Gitprojects\arjo-tools\hotkeys\lookup\ad-lookup.ps1" -Query "' name '"'
}
