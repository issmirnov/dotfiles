pragma Singleton
import Quickshell
import QtQuick   // for the `color` value type

// Palette + metrics for the bar. Swap `variant` to reskin everything.
//   "pastel"  → Catppuccin-ish soft accents (default; user-approved)
//   "vivid"   → today's colorful waybar energy (kept as a one-line alternate)
Singleton {
    id: theme

    readonly property string variant: "pastel"
    readonly property bool _v: variant === "vivid"

    // --- surfaces ---
    readonly property color barBg:   _v ? "#0b0e15" : "#171429"
    readonly property color border:  _v ? "#222a42" : "#322b4d"
    readonly property color surface: _v ? "#232c46" : "#241f3a"
    readonly property color text:    _v ? "#dfe6f5" : "#e5dcf5"
    readonly property color subtext: _v ? "#9fb0d6" : "#b8a9e0"
    readonly property color chipText: _v ? "#141000" : "#241436"   // dark text on colored chips

    // --- workspaces ---
    readonly property color wsIdleBg:   _v ? "#232c46" : "#241f3a"
    readonly property color wsIdleText: _v ? "#9fb0d6" : "#b8a9e0"
    readonly property color wsActiveBg: _v ? "#f5c542" : "#c8a2f0"
    readonly property color wsActiveText: _v ? "#1a1600" : "#241436"
    readonly property color urgent:     _v ? "#e0743b" : "#f0a2b8"
    readonly property color wsHoverBg:  _v ? "#33405f" : "#372f57"

    // --- per-stat accents ---
    readonly property color volCol:  _v ? "#e0a43b" : "#f0c2a2"
    readonly property color briCol:  _v ? "#e0c53b" : "#f0e0a2"
    readonly property color netCol:  _v ? "#3f7bd6" : "#a2c8f0"
    readonly property color cpuCol:  _v ? "#3fae6a" : "#a2f0c8"
    readonly property color memCol:  _v ? "#8a5cf0" : "#c8a2f0"
    readonly property color tempCol: _v ? "#e0743b" : "#f0a2b8"
    readonly property color loadCol: _v ? "#5cc8d0" : "#a2e0dc"
    readonly property color trayCol: _v ? "#cdd7ee" : "#d7cef0"

    // --- metrics ---
    readonly property int barHeight:  46
    readonly property int barRadius:  22
    readonly property int chipRadius: 12
    readonly property int chipHeight: 32
    readonly property int gap:        9
    readonly property int marginTop:  8
    readonly property int marginSide: 10
    readonly property int fontSize:   16
    readonly property int iconSize:   22
}
