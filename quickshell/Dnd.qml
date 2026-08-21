import Quickshell.Io
import QtQuick

// 🔔 / 🔕 "meeting mode" toggle. Click -> lib/dnd-mode {on|off}:
//   swaync DND on/off  — kills every notification banner (also screenshare privacy), plus
//   mutes Slack/Telegram audio so their "dings" go quiet too (a background watcher catches
//   their streams even when the apps were idle at click time).
// Sits next to IdleToggle and mirrors its chip styling (rose "active" instead of amber).
Rectangle {
    id: root
    property bool active: false
    property bool _pending: false     // a local toggle is in flight; don't let the poll clobber it
    readonly property string helper: "/home/vania/.config/quickshell/lib/dnd-mode"

    height: Theme.chipHeight
    width: label.width + 18
    radius: Theme.chipRadius
    color: active ? Theme.dndCol : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    function _read(text) {
        const s = ("" + text).trim().split("\n").pop().trim();
        if (s === "true" || s === "false")
            root.active = (s === "true");
    }
    function _apply(text) { root._pending = false; _read(text); }         // result of our own on/off
    function _poll(text)  { if (!root._pending) _read(text); }            // background reconcile

    // Fired on click; command (on/off) is set imperatively just before launch.
    Process { id: applyProc; stdout: StdioCollector { onStreamFinished: root._apply(text) } }

    // Read the real swaync DND state — at startup and on a light poll — so BOTH monitors'
    // buttons (and any external swaync-client / keybind toggle) stay in sync, not just the
    // bar that was clicked. `status` is a cheap `swaync-client -D`; no audio/watcher work.
    Process { id: stateProc; command: [root.helper, "status"]; stdout: StdioCollector { onStreamFinished: root._poll(text) } }
    Component.onCompleted: stateProc.running = true
    Timer { interval: 4000; running: true; repeat: true; onTriggered: stateProc.running = true }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.active ? "🔕 DND" : "🔔"
        color: root.active ? Theme.chipText : Theme.subtext
        font.pixelSize: Theme.fontSize
        font.bold: root.active
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.active = !root.active;                                   // optimistic: instant feedback
            root._pending = true;                                        // poll won't override until helper confirms
            applyProc.command = [root.helper, root.active ? "on" : "off"];
            applyProc.running = true;
        }
    }
}
