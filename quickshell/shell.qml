import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Entrypoint: one Bar per monitor. A single timer keeps window classes fresh
// so the per-workspace app icons stay correct (lastIpcObject.class isn't reactive).
ShellRoot {
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Hyprland.refreshToplevels()
    }

    // Calendar alerts: run cal-notify every minute → swaync at 10/5/1 min before next event
    Process { id: calNotify; command: ["/home/vania/.config/quickshell/lib/cal-notify"] }
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: calNotify.running = true
    }

    Variants {
        // one bar per monitor, except the Corsair Xeneon Edge (it keeps its own dashboard)
        model: Quickshell.screens.filter(s => s.name !== "HDMI-A-2")
        Bar {
            required property var modelData
            screen: modelData
        }
    }
}
