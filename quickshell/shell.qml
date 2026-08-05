import Quickshell
import Quickshell.Hyprland
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

    Variants {
        // one bar per monitor, except the Corsair Xeneon Edge (it keeps its own dashboard)
        model: Quickshell.screens.filter(s => s.name !== "HDMI-A-2")
        Bar {
            required property var modelData
            screen: modelData
        }
    }
}
