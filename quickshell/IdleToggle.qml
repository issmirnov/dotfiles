import Quickshell.Wayland
import QtQuick

// Click to keep the system awake — holds a Wayland idle inhibitor while active.
// (Named IdleToggle, not IdleInhibitor, to avoid colliding with Quickshell's own type.)
Rectangle {
    id: root
    property var barWindow          // the PanelWindow this bar lives in
    property bool active: false

    height: Theme.chipHeight
    width: label.width + 18
    radius: Theme.chipRadius
    color: active ? Theme.accent : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    IdleInhibitor {
        window: root.barWindow
        enabled: root.active
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.active ? "AWAKE" : "auto"
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
