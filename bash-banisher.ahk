#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Config ─────────────────────────────────────────────────────────────────
TARGET_MONITOR := 2    ; monitor to banish bash windows to (1 = primary)
WIN_W          := 900  ; banished window width
WIN_H          := 400  ; banished window height
POLL_MS        := 300  ; how often to check for new windows (ms)
; ───────────────────────────────────────────────────────────────────────────

gHandled := Map()
gMon     := false

InitMonitor() {
    global gMon
    try {
        MonitorGet(TARGET_MONITOR, &L, &T, &R, &B)
        gMon := {x: L, y: T}
        return true
    }
    return false
}

BashBanisher() {
    global gMon, gHandled
    if !gMon && !InitMonitor()
        return

    for hwnd in WinGetList("ahk_exe bash.exe") {
        if gHandled.Has(hwnd)
            continue
        gHandled[hwnd] := true
        ; Move to target monitor first, then push to back so it never steals focus
        WinMove(gMon.x, gMon.y, WIN_W, WIN_H, "ahk_id " hwnd)
        WinMoveBottom("ahk_id " hwnd)
    }

    ; Prune closed windows from the tracking map
    dead := []
    for hwnd in gHandled
        if !WinExist("ahk_id " hwnd)
            dead.Push(hwnd)
    for h in dead
        gHandled.Delete(h)
}

InitMonitor()
SetTimer(BashBanisher, POLL_MS)
