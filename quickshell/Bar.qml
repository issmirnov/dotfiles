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

        // ---- TOP DECK: workspaces (row 1, overlaid below) · clock · live stats ----
        Item {
            id: topDeck
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: Theme.deckHeight

            // center — local date/time + a few timezones (ZAG·PRG·KYV)
            Clock {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            // right — AI usage (Claude/Codex), brightness, audio, stats, idle-inhibitor
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.gap
                // One chip per Anthropic account so each carries its own color (sl can be
                // red while ig stays green). `claude:<name>` renders + colors that account
                // solo; a bare "claude" would bundle both under the single worst color.
                // Each usage chip drops down a 5h + weekly meter popup on click (UsageChip.qml).
                UsageChip { instance: "claude:claude-smirnovlabs" }
                UsageChip { instance: "claude:claude_isgmirnov" }
                UsageChip { instance: "codex" }
                Brightness {}
                AutoDimToggle {}
                Audio {}
                Stats {}
                IdleToggle { barWindow: bar }
            }
        }

        // ---- BOTTOM DECK: overflow workspaces (row 2, overlaid below) · world-clock + calendar · tray ----
        Item {
            id: bottomDeck
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: Theme.deckHeight

            // center — world clock + calendar chips (glanceable, not urgent)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.gap * 2
                Blocklet {
                    flat: true
                    exec: "/home/vania/.dotfiles/i3/blocklets/worldclock"
                    interval: 30000
                }
                Blocklet {                       // happening now (mint; hides when nothing is on)
                    flat: true
                    exec: "/home/vania/.config/quickshell/lib/cal-next"
                    args: ["current"]
                    interval: 60000
                }
                Blocklet {                       // next up (countdown to start)
                    flat: true
                    exec: "/home/vania/.config/quickshell/lib/cal-next"
                    interval: 60000
                }
            }

            // right — system tray
            SysTray {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ---- WORKSPACES: overlay the left of BOTH decks. Declared last so its pill
        // MouseAreas sit on top (the transparent decks above have no MouseArea, but
        // this keeps click priority unambiguous). Wraps top-row-first (see Workspaces.qml).
        Workspaces {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 12
            barScreen: bar.screen
        }
    }
}
