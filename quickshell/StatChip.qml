import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// A stat pill that drops down a read-only detail popup on click (dismiss on click-away).
// Sparkline history comes from the caller (Sys.*Hist); the heavier detail is fetched by
// sysdetail.sh only while the popup is open. Popup anchor + focus-grab cloned from Audio.qml.
Rectangle {
    id: chip
    property string label
    property color accent
    property string section                 // sysdetail.sh argument
    property var history: []
    property var history2: []
    property bool dualSpark: false
    property real sparkMin: NaN
    property real sparkMax: NaN
    property Component contentComponent
    property var model: ({})                 // parsed sysdetail.sh JSON; delegate reads <chipId>.model

    height: Theme.chipHeight
    width: t.width + 16
    radius: Theme.chipRadius
    color: accent

    Text {
        id: t
        anchors.centerIn: parent
        text: chip.label
        color: Theme.chipText
        font.pixelSize: Theme.fontSize
    }

    // on-demand detail — only runs while the popup is open (Timer gated on popup.visible)
    Process {
        id: detail
        command: ["/home/vania/.config/quickshell/lib/sysdetail.sh", chip.section]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(text);
                    if (o)
                        chip.model = o;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: popup.visible
        triggeredOnStart: true
        onTriggered: detail.running = true
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
        implicitWidth: 320
        implicitHeight: body.implicitHeight + 30   // 6 gap + 12 top + 12 bottom inner margins
        visible: false
        color: "transparent"

        // click-away dismiss — imperative arming copied from Audio.qml (declarative binding is broken)
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
            anchors.topMargin: 6                   // the see-through gap under the bar
            radius: Theme.chipRadius
            color: Theme.barBg

            Column {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Text {
                    text: chip.label
                    color: chip.accent
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Sparkline {
                    width: body.width
                    height: 28
                    values: chip.history
                    stroke: chip.accent
                    values2: chip.dualSpark ? chip.history2 : []
                    stroke2: Theme.subtext
                    minY: chip.sparkMin
                    maxY: chip.sparkMax
                }
                Loader {
                    width: body.width
                    active: popup.visible
                    sourceComponent: chip.contentComponent
                }
            }
        }
    }
}
