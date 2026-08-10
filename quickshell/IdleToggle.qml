import Quickshell.Wayland
import QtQuick

// Click to keep the system awake — holds a Wayland idle inhibitor while active.
// (Named IdleToggle, not IdleInhibitor, to avoid colliding with Quickshell's own type.)
//   🌙 auto  → idle behaves normally, screen may sleep/lock (hypridle in charge)
//   ☕ awake → idle inhibited, screen stays on
Rectangle {
    id: root
    property var barWindow          // the PanelWindow this bar lives in
    property bool active: false

    height: Theme.chipHeight
    width: label.width + 18
    radius: Theme.chipRadius
    // was Theme.accent (undefined → the "busted" unstyled AWAKE chip); awakeCol is a real warm amber
    color: active ? Theme.awakeCol : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    IdleInhibitor {
        window: root.barWindow
        enabled: root.active
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.active ? "☕ awake" : "🌙 auto"
        color: root.active ? Theme.chipText : Theme.subtext
        font.pixelSize: Theme.fontSize
        font.bold: root.active
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.active = !root.active
    }
}
