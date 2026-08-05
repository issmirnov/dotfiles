import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick

// Default sink volume chip.
//   left-click  → open a draggable volume-slider popup
//   scroll      → nudge volume ±5%
//   right-click → toggle mute
Rectangle {
    id: audio
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var av: sink ? sink.audio : null

    height: Theme.chipHeight
    width: t.width + 16
    radius: Theme.chipRadius
    color: Theme.volCol

    // required to keep the sink's live audio data bound
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    Text {
        id: t
        anchors.centerIn: parent
        color: Theme.chipText
        font.pixelSize: Theme.fontSize
        text: audio.av
            ? (audio.av.muted ? "muted" : "VOL " + Math.round(audio.av.volume * 100) + "%")
            : "—"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onWheel: (wheel) => {
            if (!audio.av) return;
            const step = 0.05;
            const dir = wheel.angleDelta.y > 0 ? 1 : -1;
            audio.av.volume = Math.max(0, Math.min(1, audio.av.volume + dir * step));
            if (audio.av.muted && audio.av.volume > 0) audio.av.muted = false;
        }
        onClicked: (m) => {
            if (m.button === Qt.RightButton) {
                if (audio.av) audio.av.muted = !audio.av.muted;
            } else {
                popup.visible = !popup.visible;
            }
        }
    }

    // ---- slider popup (opens below the chip; click-away dismisses) ----
    PopupWindow {
        id: popup
        anchor.item: audio
        // drop down from the chip's bottom-right corner, expanding down-left so a
        // right-edge chip stays fully on-screen (rect defaults to the chip's bounds)
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: 260
        implicitHeight: 52                    // 6px transparent gap + 46 body
        visible: false
        color: "transparent"

        // dismiss when the user clicks anywhere outside the popup (Hyprland)
        HyprlandFocusGrab {
            windows: [popup]
            active: popup.visible
            onCleared: popup.visible = false
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6              // the see-through gap
            radius: Theme.chipRadius
            color: Theme.barBg

            Row {
                id: row
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // mute toggle (text pill — glyph-safe)
                Rectangle {
                    id: mutePill
                    readonly property bool muted: !!(audio.av && audio.av.muted)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: mt.width + 16
                    radius: 13
                    color: muted ? Theme.volCol : Theme.surface
                    Text {
                        id: mt
                        anchors.centerIn: parent
                        text: mutePill.muted ? "muted" : "mute"
                        color: mutePill.muted ? Theme.chipText : Theme.text
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (audio.av) audio.av.muted = !audio.av.muted
                    }
                }

                // slider (click / drag to set volume)
                Item {
                    id: slider
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.width - mutePill.width - pct.width - row.spacing * 2
                    height: parent.height
                    readonly property real vol: audio.av ? audio.av.volume : 0

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: 4
                        color: Theme.surface
                        Rectangle {
                            width: Math.max(0, Math.min(1, slider.vol)) * parent.width
                            height: parent.height
                            radius: 4
                            color: (audio.av && audio.av.muted) ? Theme.subtext : Theme.volCol
                        }
                    }
                    Rectangle {   // handle
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(1, slider.vol)) * track.width - width / 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        function apply(mx) {
                            if (!audio.av) return;
                            const v = Math.max(0, Math.min(1, mx / width));
                            audio.av.volume = v;
                            if (audio.av.muted && v > 0) audio.av.muted = false;
                        }
                        onPressed: (m) => apply(m.x)
                        onPositionChanged: (m) => { if (pressed) apply(m.x); }
                    }
                }

                // live percentage
                Text {
                    id: pct
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: audio.av ? Math.round(audio.av.volume * 100) + "%" : "—"
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
