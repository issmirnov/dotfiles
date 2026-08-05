import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

// Per-monitor workspace pills: number + icons of the windows on that workspace.
// Click switches to the workspace via HyprlandWorkspace.activate() (correct on Lua Hyprland).
Row {
    id: root
    property var barScreen
    readonly property var hlMonitor: barScreen ? Hyprland.monitorFor(barScreen) : null

    height: Theme.chipHeight
    spacing: Theme.gap

    Repeater {
        model: Hyprland.workspaces.values.filter(w => w.monitor === root.hlMonitor)

        Rectangle {
            id: pill
            required property var modelData
            readonly property var ws: modelData
            readonly property bool focused: ws.focused

            height: Theme.chipHeight
            width: inner.width + 16
            radius: height / 2
            color: ws.urgent ? Theme.urgent : (focused ? Theme.wsActiveBg : Theme.wsIdleBg)

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: pill.ws.name
                    color: pill.focused ? Theme.wsActiveText : Theme.wsIdleText
                    font.pixelSize: Theme.fontSize
                    font.bold: pill.focused
                }

                Repeater {
                    model: pill.ws.toplevels ? pill.ws.toplevels.values : []
                    IconImage {
                        required property var modelData
                        readonly property string cls: modelData.lastIpcObject ? (modelData.lastIpcObject.class || "") : ""
                        readonly property var entry: cls ? DesktopEntries.heuristicLookup(cls) : null
                        implicitSize: Theme.iconSize
                        source: Quickshell.iconPath(entry ? entry.icon : (cls || "application-x-executable"), "application-x-executable")
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: pill.ws.activate()
            }
        }
    }
}
