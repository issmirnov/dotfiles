import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

// Per-monitor workspace pills: number + icons of the windows on that workspace.
// Click switches to the workspace via HyprlandWorkspace.activate() (correct on Lua Hyprland).
Flow {
    id: root
    property var barScreen
    readonly property var hlMonitor: barScreen ? Hyprland.monitorFor(barScreen) : null

    // Two decks tall; pills wrap top-row-first. Width budget stops short of the
    // centered clock (top) / calendar (bottom) so pills never slide under them —
    // constrained by the WIDER centered cluster (the calendar). TUNE `wsBudget`.
    property int wsBudget: Math.max(220, (parent ? parent.width : 1200) / 2 - 420)
    height: Theme.barHeight
    width: wsBudget
    spacing: 0            // vertical row-gap = deck-cell padding only; horizontal pill gap baked into cell width below

    Repeater {
        model: Hyprland.workspaces.values
            // Regular workspaces on this monitor only. Special workspaces (the
            // SUPER+C scratchpad) are surfaced by the dedicated badge below — not
            // as a normal pill — so exclude them here to avoid a duplicate label.
            .filter(w => w.monitor === root.hlMonitor && !String(w.name).startsWith("special:"))
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

        Item {
            id: cell
            required property var modelData
            implicitWidth: pill.width + Theme.gap   // trailing gap = horizontal pill spacing (Flow spacing is 0)
            height: Theme.deckHeight            // deck-tall band; pill vCentered → sits on the deck center

            Rectangle {
            id: pill
            readonly property var ws: cell.modelData
            readonly property bool focused: ws.focused
            anchors.verticalCenter: parent.verticalCenter

            height: Theme.chipHeight
            width: inner.width + 16
            radius: height / 2
            // Urgent no longer recolors the pill — the leading dot in the Row flags it.
            color: focused ? Theme.wsActiveBg
                 : ma.containsMouse ? Theme.wsHoverBg
                 : Theme.wsIdleBg
            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: 4

                // Urgent badge: soft-red leading dot. It reserves its own slot in the
                // Row (only while urgent), so it sits at the pill's start with real
                // padding (pill edge + Row spacing) and never overlaps the label.
                Rectangle {
                    id: urgentDot
                    visible: pill.ws.urgent
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: width / 2
                    color: Theme.urgentDot
                    border.width: 1
                    border.color: Theme.barBg   // thin ring so it reads on a light focused pill too
                }

                Text {
                    text: pill.ws.name
                    // Colour follows focus only (urgent keeps the pill's normal bg, so
                    // active-text here would be unreadable); bold stays as the urgent cue.
                    color: pill.focused ? Theme.wsActiveText : Theme.wsIdleText
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
                            if (c.indexOf("nemo") !== -1)                 // Nemo file manager (Adwaita theme has no 'nemo' icon; .desktop uses system-file-manager)
                                return "file:///usr/share/icons/hicolor/scalable/apps/nemo.svg";
                            if (c.indexOf("foot") === 0)                  // foot terminal (class 'foot'/'footclient'; icon only in hicolor, not the active Adwaita theme nor /usr/share/pixmaps, so it isn't resolved natively the way Alacritty is)
                                return "file:///usr/share/icons/hicolor/scalable/apps/foot.svg";
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
                            color: pill.focused ? Theme.wsActiveText : Theme.wsIdleText
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

    // Special-workspace badge (the SUPER+C Claude scratchpad). A monitor's
    // special workspace is a SEPARATE overlay from its active workspace, so none
    // of the pills above light up when it's showing — this surfaces the drop-down
    // in the bar. Purple, to match the scratchpad's frame. Click hides it.
    Rectangle {
        id: special
        readonly property var mon: root.hlMonitor
        readonly property string specialName:
            (mon && mon.lastIpcObject && mon.lastIpcObject.specialWorkspace)
                ? String(mon.lastIpcObject.specialWorkspace.name || "") : ""
        visible: specialName !== ""
        height: Theme.chipHeight
        width: specialRow.width + 16
        radius: height / 2
        // Orange for the tiling stash, red for the Claude scratch — matches the bar so
        // it's obvious which overlay is up (mauve fallback for any other special).
        color: special.specialName === "special:stash" ? Theme.stashBadge
             : special.specialName === "special:scratch" ? Theme.scratchBadge
             : "#cba6f7"

        Row {
            id: specialRow
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: "◆ " + special.specialName.replace("special:", "")
                color: "#241436"
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Click the badge to dismiss whatever special is up: the stash toggles itself,
            // the Claude scratch goes through its hypr-scratch show/hide/spawn manager.
            onClicked: {
                if (special.specialName === "special:stash")
                    Quickshell.execDetached(["/usr/bin/hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.toggle_special(\"stash\"))"]);
                else
                    Quickshell.execDetached(["/home/vania/.dotfiles/hypr/scripts/hypr-scratch"]);
            }
        }
    }

    // activespecial doesn't change the active workspace, so the monitor's cached
    // ipc object can go stale — refresh it so the badge above tracks the toggle.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "activespecial" || n === "activespecialv2")
                Hyprland.refreshMonitors();
        }
    }
}
