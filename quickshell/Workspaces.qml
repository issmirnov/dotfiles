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
        model: Hyprland.workspaces.values
            .filter(w => w.monitor === root.hlMonitor)
            .sort((a, b) => a.id - b.id)

        Rectangle {
            id: pill
            required property var modelData
            readonly property var ws: modelData
            readonly property bool focused: ws.focused

            height: Theme.chipHeight
            width: inner.width + 16
            radius: height / 2
            color: ws.urgent ? Theme.urgent
                 : focused ? Theme.wsActiveBg
                 : ma.containsMouse ? Theme.wsHoverBg
                 : Theme.wsIdleBg
            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: pill.ws.name
                    color: (pill.focused || pill.ws.urgent) ? Theme.wsActiveText : Theme.wsIdleText
                    font.pixelSize: Theme.fontSize
                    font.bold: pill.focused || pill.ws.urgent
                }

                Repeater {
                    model: pill.ws.toplevels ? pill.ws.toplevels.values : []
                    Item {
                        id: ic
                        required property var modelData
                        readonly property string cls: modelData.lastIpcObject ? (modelData.lastIpcObject.class || "") : ""
                        // Explicit icon for windows whose class doesn't resolve via the icon theme.
                        // OSRS / RuneLite: class net-runelite-client-RuneLite, no theme match under Adwaita.
                        readonly property string overrideIcon: cls.toLowerCase().indexOf("runelite") !== -1
                            ? "file:///usr/share/pixmaps/runelite.png" : ""
                        readonly property var entry: cls ? DesktopEntries.heuristicLookup(cls) : null
                        readonly property string iconName: entry && entry.icon ? entry.icon : cls
                        readonly property bool haveIcon: overrideIcon !== "" || (iconName !== "" && Quickshell.hasThemeIcon(iconName))
                        width: Theme.iconSize
                        height: Theme.iconSize
                        IconImage {          // real app icon when the theme has it
                            visible: ic.haveIcon
                            anchors.fill: parent
                            source: ic.overrideIcon !== "" ? ic.overrideIcon
                                  : (ic.haveIcon ? Quickshell.iconPath(ic.iconName) : "")
                        }
                        Rectangle {          // neutral dot placeholder otherwise (no broken icons)
                            visible: !ic.haveIcon
                            anchors.centerIn: parent
                            width: parent.width * 0.45
                            height: width
                            radius: width / 2
                            color: (pill.focused || pill.ws.urgent) ? Theme.wsActiveText : Theme.wsIdleText
                            opacity: 0.55
                        }
                    }
                }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pill.ws.activate()
            }
        }
    }
}
