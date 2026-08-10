import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// A Claude/Codex usage chip: shows the ai_usage blocklet text + color (like Blocklet.qml)
// and drops down a read-only popup with 5h + weekly meter bars, reset countdowns and the
// weekly pace token. Popup mechanics (anchor, focus-grab dismiss, on-demand detail gated
// on visibility) are cloned from StatChip.qml; detail JSON comes from `ai_usage __detail`.
Rectangle {
    id: chip
    property string exec: "/home/vania/.dotfiles/i3/blocklets/ai_usage"
    property string instance: ""            // -> BLOCK_INSTANCE ("claude:<acct>" | "codex")
    property int interval: 60000

    property string fullText: ""
    property string emittedColor: ""
    property var detail: ({})               // parsed `ai_usage __detail` JSON: {title, windows:[…]}

    height: Theme.chipHeight
    width: t.width + 18
    radius: Theme.chipRadius
    color: Theme.surface
    visible: fullText !== ""

    // ---- chip text + color: run the blocklet on a timer (mirrors Blocklet.qml) ----
    Process {
        id: proc
        command: ["/usr/bin/env", "BLOCK_INSTANCE=" + chip.instance, chip.exec]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = ("" + text).split("\n");
                chip.fullText = (lines[0] || "").trim();
                const c = (lines[2] || "").trim();
                chip.emittedColor = (c.charAt(0) === "#") ? c : "";
            }
        }
    }
    Timer {
        interval: chip.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Text {
        id: t
        anchors.centerIn: parent
        text: chip.fullText
        color: chip.emittedColor !== "" ? chip.emittedColor : Theme.subtext
        font.pixelSize: Theme.fontSize
    }

    // ---- on-demand detail JSON — only runs while the popup is open ----
    Process {
        id: detailProc
        command: ["/usr/bin/env", "BLOCK_INSTANCE=" + chip.instance, chip.exec, "__detail"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(text);
                    if (o)
                        chip.detail = o;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: popup.visible
        triggeredOnStart: true
        onTriggered: detailProc.running = true
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    PopupWindow {
        id: popup
        anchor.item: chip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: 300
        implicitHeight: body.implicitHeight + 30    // 6 gap + 12 top + 12 bottom inner margins
        visible: false
        color: "transparent"

        // click-away dismiss — imperative arming copied from Audio.qml/StatChip.qml
        HyprlandFocusGrab {
            id: grab
            windows: [popup]
            onCleared: popup.visible = false
        }
        Connections {
            target: popup
            function onVisibleChanged() {
                if (popup.visible)
                    grabArm.restart();
                else {
                    grabArm.stop();
                    grab.active = false;
                }
            }
        }
        Timer { id: grabArm; interval: 150; onTriggered: grab.active = popup.visible }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6                    // the see-through gap under the bar
            radius: Theme.chipRadius
            color: Theme.barBg

            Column {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 12

                Text {
                    width: parent.width
                    text: chip.detail.title || chip.fullText
                    color: chip.emittedColor !== "" ? chip.emittedColor : Theme.text
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Repeater {
                    model: chip.detail.windows || []
                    UsageMeter {
                        width: body.width
                        label: modelData.label
                        pct: modelData.pct
                        reset: modelData.reset_s
                        pace: modelData.pace || ""
                    }
                }

                Text {
                    visible: !(chip.detail.windows && chip.detail.windows.length)
                    text: "no usage data"
                    color: Theme.subtext
                    font.pixelSize: 13
                }
            }
        }
    }
}
