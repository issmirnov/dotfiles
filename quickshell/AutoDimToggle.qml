import QtQuick

// Click to pause / re-arm hexane-nightlight's auto-dim. State is the shared AutoDim
// singleton (the override marker). Mirrors IdleToggle's shape: highlighted when the
// notable (non-default) state is active — here that's `held` (a manual override).
Rectangle {
    id: root

    height: Theme.chipHeight
    width: label.width + 18
    radius: Theme.chipRadius
    color: AutoDim.active ? Theme.briCol : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: AutoDim.active ? "held" : "auto"
        color: AutoDim.active ? Theme.chipText : Theme.subtext
        font.pixelSize: Theme.fontSize
        font.bold: AutoDim.active
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AutoDim.active ? AutoDim.arm() : AutoDim.pause(-1)
    }
}
