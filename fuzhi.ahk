#Requires AutoHotkey v2.0
#SingleInstance Force

#HotIf WinActive("ahk_exe chrome.exe") || WinActive("ahk_exe msedge.exe") || WinActive("ahk_exe firefox.exe")

$^c::{
    oldClip := ClipboardAll()
    A_Clipboard := ""
    Send "^c"

    if ClipWait(1) {
        text := A_Clipboard
        if (text != "")
            A_Clipboard := text
    } else {
        A_Clipboard := oldClip
    }
}

#HotIf
