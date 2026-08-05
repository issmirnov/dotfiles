import Quickshell.Io
import QtQuick

// Runs an i3blocks-style script on a timer and shows its output.
// Script emits up to 3 lines: full_text, short_text, color(#hex, optional).
// Reuses the existing ~/.dotfiles/i3/blocklets scripts verbatim (their logic + caching).
Rectangle {
    id: root
    property string exec                       // absolute path to the blocklet script
    property var args: []
    property string instance: ""               // -> BLOCK_INSTANCE (e.g. "claude", "codex")
    property int interval: 30000
    property bool flat: false                  // true = no chip background (for the center)
    property color textColor: Theme.subtext

    property string fullText: ""
    property string emittedColor: ""

    height: Theme.chipHeight
    width: t.width + (flat ? 0 : 18)
    radius: Theme.chipRadius
    color: flat ? "transparent" : Theme.surface
    visible: fullText !== ""

    Process {
        id: proc
        // `env VAR=val script` inherits qs's session env (HOME/PATH) and adds BLOCK_INSTANCE
        command: (root.instance !== ""
            ? ["/usr/bin/env", "BLOCK_INSTANCE=" + root.instance, root.exec]
            : [root.exec]).concat(root.args)
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = ("" + text).split("\n");
                root.fullText = (lines[0] || "").trim();
                const c = (lines[2] || "").trim();
                root.emittedColor = (c.charAt(0) === "#") ? c : "";
            }
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Text {
        id: t
        anchors.centerIn: parent
        text: root.fullText
        color: root.emittedColor !== "" ? root.emittedColor : root.textColor
        font.pixelSize: Theme.fontSize
    }
}
