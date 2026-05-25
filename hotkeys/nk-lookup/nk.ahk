F6:: {
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    name := A_Clipboard
    if (name = "") {
        MsgBox "No text selected."
        return
    }
    Run 'pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\un024247\Gitprojects\arjo-tools\hotkeys\nk-lookup\net-user-lookup.ps1" -Query "' name '"'
}
