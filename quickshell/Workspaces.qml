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
            // Sort by LABEL: numeric-labelled workspaces first (by value), then
            // any word-labelled one pushed to the end — including a renamed
            // numbered workspace (e.g. workspace "2" renamed to "pinley"), which
            // groups with the named spaces rather than staying in slot 2.
            // Within the word group, sort by DESCENDING id: Hyprland gives
            // move-script named spaces increasingly-negative ids, so new ones
            // still append at the end and existing ones don't reshuffle.
            .sort((a, b) => {
                const aNum = /^[0-9]+$/.test(a.name), bNum = /^[0-9]+$/.test(b.name);
                if (aNum !== bNum) return aNum ? -1 : 1;
                if (aNum) return Number(a.name) - Number(b.name);
                return b.id - a.id;
            })

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
                        // Explicit icons for windows whose class isn't itself a valid icon-theme
                        // name. heuristicLookup is a no-op in this Quickshell build, so the class
                        // must equal an icon name or the pill falls back to the neutral dot.
                        // Substring match keeps this robust to per-app class quirks (hashes, case).
                        readonly property string overrideIcon: {
                            const c = cls.toLowerCase();
                            if (c.indexOf("runelite") !== -1)             // OSRS / RuneLite
                                return "file:///usr/share/pixmaps/runelite.png";
                            if (c.indexOf("org.telegram.desktop") !== -1) // Telegram (per-account hash suffix)
                                return "file:///usr/share/icons/hicolor/256x256/apps/org.telegram.desktop.png";
                            if (c.indexOf("webcord") !== -1)              // Discord via WebCord (class WebCord)
                                return "file:///usr/share/icons/hicolor/512x512/apps/webcord.png";
                            if (c.indexOf("signal") !== -1)               // Signal (icon file: signal-desktop)
                                return "file:///usr/share/icons/hicolor/256x256/apps/signal-desktop.png";
                            if (c.indexOf("zapzap") !== -1)               // WhatsApp via ZapZap
                                return "file:///usr/share/icons/hicolor/scalable/apps/com.rtosta.zapzap.svg";
                            if (c.indexOf("obsidian") !== -1)             // Obsidian (class md.Obsidian)
                                return "file:///usr/share/icons/hicolor/512x512/apps/obsidian.png";
                            if (c.indexOf("code") === 0)                  // VS Code / code-oss (icon file: vscode)
                                return "file:///usr/share/pixmaps/vscode.png";
                            if (c.indexOf("cursor") !== -1)               // Cursor editor
                                return "file:///usr/share/pixmaps/co.anysphere.cursor.png";
                            if (c.indexOf("zoom") !== -1)                 // Zoom (icon file: Zoom, capital)
                                return "file:///usr/share/pixmaps/Zoom.png";
                            return "";
                        }
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
