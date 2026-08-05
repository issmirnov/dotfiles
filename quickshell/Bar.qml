import Quickshell
import QtQuick

// One floating, rounded bar for a single monitor. Pure layout — data lives in the modules.
PanelWindow {
    id: bar

    // TODO: exclude the Xeneon Edge (HDMI-A-2) once rendering is confirmed — a `visible`
    // binding on `screen` caused a binding loop, so gate at the model level in shell.qml.
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    margins { top: Theme.marginTop; left: Theme.marginSide; right: Theme.marginSide }
    exclusiveZone: Theme.barHeight + Theme.marginTop
    color: "transparent"   // transparent window; the rounded Rectangle below is the visible bar

    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.barBg
        // NOTE: intentionally NO `border` — a Rectangle border on a transparent Quickshell
        // window triggers QTBUG-137166 ("hole in my window") and blanks the entire bar.

        // left — workspaces (clickable, with live window icons)
        Workspaces {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            barScreen: bar.screen
        }

        // center — clock
        Clock { anchors.centerIn: parent }

        // right — audio, stats, tray
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap
            Audio {}
            Stats {}
            SysTray {}
        }
    }
}
