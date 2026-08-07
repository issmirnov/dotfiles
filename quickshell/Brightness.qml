import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Backlight-brightness chip for BOTH Dell U3225QEs (DDC/CI via ddcutil).
//   left-click → open a draggable brightness slider
//   scroll     → nudge ±5%
// Unlike Audio (a live Pipewire binding), brightness has no push source and each
// `ddcutil setvcp` is ~50-100ms over I2C. So the UI value is live, but writes are
// self-throttling: at most one write in flight, and when it finishes we re-issue
// if the slider moved on — converging to the final value without flooding the bus.
// Shares VCP 0x10 with hexane-nightlight, which re-asserts its scheduled value
// during the sunrise/sunset ramps.
Rectangle {
    id: bri

    property int value: 100       // live UI value, 0..100
    property int applied: -1      // last value written to the panels
    property int _writing: -1     // value of the in-flight write
    property bool dragging: false
    property bool _lastSeeded: false   // ignore the FileView's initial load; startup getvcp is the seed

    height: Theme.chipHeight
    width: t.width + 16
    radius: Theme.chipRadius
    color: Theme.briCol

    Text {
        id: t
        anchors.centerIn: parent
        color: Theme.chipText
        font.pixelSize: Theme.fontSize
        text: "BRI " + bri.value + "%"
    }

    // ---- DDC I/O ----
    // write both panels in parallel; the command re-reads bri.value at spawn time
    Process {
        id: writeProc
        command: ["sh", "-c",
            "ddcutil --sn DP7HGJ4 setvcp 10 " + bri.value +
            " & ddcutil --sn 6P7HGJ4 setvcp 10 " + bri.value + " & wait"]
        onRunningChanged: {
            if (running) return;                        // just started
            bri.applied = bri._writing;                 // finished
            if (bri.value !== bri.applied) bri._kick();  // moved during the write → catch up
        }
    }

    // seed the current brightness (read DP-1; both panels are kept in sync)
    Process {
        id: readProc
        command: ["ddcutil", "--sn", "DP7HGJ4", "getvcp", "0x10"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (bri.dragging) return;               // don't stomp an active drag
                const m = ("" + text).match(/current value\s*=\s*(\d+)/);
                if (m) { bri.value = parseInt(m[1]); bri.applied = bri.value; }
            }
        }
    }
    // follow nightlight's ramps live: when ARMED and not dragging, adopt the value it
    // wrote to DP-1. Event-driven (inotify) — no polling. HELD → ignore (user's value wins).
    FileView {
        id: lastFile
        path: "/home/vania/.cache/hexane-nightlight/last"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!bri._lastSeeded) { bri._lastSeeded = true; return; }   // ignore initial load
            if (AutoDim.active || bri.dragging) return;                 // HELD or dragging → keep our value
            const m = ("" + lastFile.text()).match(/"DP7HGJ4"\s*:\s*(\d+)/);
            if (m) bri._follow(parseInt(m[1]));
        }
    }
    Component.onCompleted: readProc.running = true

    // when auto-dim re-arms (marker cleared by the toggle or nightlight), re-read the
    // panel so the slider snaps to whatever nightlight just applied — race-free.
    Connections {
        target: AutoDim
        function onActiveChanged() {
            if (!AutoDim.active) readProc.running = true;
        }
    }

    function _kick() {
        if (writeProc.running || bri.value === bri.applied) return;
        bri._writing = bri.value;
        writeProc.running = true;
    }
    function set(v) {
        bri.value = Math.max(0, Math.min(100, Math.round(v)));
        bri._kick();
    }
    // adopt an external (nightlight) value without writing DDC or marking an override
    function _follow(v) {
        bri.value = Math.max(0, Math.min(100, v));
        bri.applied = bri.value;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onWheel: (wheel) => { bri.set(bri.value + (wheel.angleDelta.y > 0 ? 5 : -5)); AutoDim.pause(bri.value); }
        onClicked: {
            if (!popup.visible) readProc.running = true;   // refresh to truth on open
            popup.visible = !popup.visible;
        }
    }

    // ---- slider popup (opens below the chip; click-away dismisses) ----
    PopupWindow {
        id: popup
        anchor.item: bri
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: 260
        implicitHeight: 52
        visible: false
        color: "transparent"

        // Click-away dismiss via Hyprland's focus grab. Two gotchas, both handled here:
        //  1) HyprlandFocusGrab flips its OWN `active` to false when the grab is dismissed,
        //     which permanently breaks a declarative `active: popup.visible` binding (it
        //     never re-arms on the next open). So drive `active` imperatively instead.
        //  2) Arming the grab in the same tick the popup becomes visible is too early — the
        //     surface isn't mapped yet, the grab never really engages, and `cleared` never
        //     fires. Arm it a beat later (grabArm).
        HyprlandFocusGrab {
            id: grab
            windows: [popup]
            onCleared: popup.visible = false
        }
        Connections {
            target: popup
            function onVisibleChanged() {
                if (popup.visible) grabArm.restart();
                else { grabArm.stop(); grab.active = false; }   // don't arm a grab on a closed popup
            }
        }
        Timer { id: grabArm; interval: 150; onTriggered: grab.active = popup.visible }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            radius: Theme.chipRadius
            color: Theme.barBg

            Row {
                id: row
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // label pill (matches Audio's mute-pill footprint; glyph-safe)
                Rectangle {
                    id: lblPill
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: lt.width + 16
                    radius: 13
                    color: Theme.surface
                    Text {
                        id: lt
                        anchors.centerIn: parent
                        text: "bri"
                        color: Theme.text
                        font.pixelSize: 13
                    }
                }

                // slider (click / drag to set brightness)
                Item {
                    id: slider
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.width - lblPill.width - pct.width - row.spacing * 2
                    height: parent.height

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: 4
                        color: Theme.surface
                        Rectangle {
                            width: Math.max(0, Math.min(1, bri.value / 100)) * parent.width
                            height: parent.height
                            radius: 4
                            color: Theme.briCol
                        }
                    }
                    Rectangle {   // handle
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(1, bri.value / 100)) * track.width - width / 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        function applyAt(mx) { bri.set(mx / width * 100); }
                        onPressed: (m) => { bri.dragging = true; applyAt(m.x); AutoDim.pause(bri.value); }
                        onPositionChanged: (m) => { if (pressed) applyAt(m.x); }
                        onReleased: { bri.dragging = false; bri._kick(); }
                    }
                }

                // live percentage
                Text {
                    id: pct
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: bri.value + "%"
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
