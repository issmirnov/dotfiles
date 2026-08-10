import QtQuick

// One horizontal usage bar for the AI-usage popups: label · track+fill · pct%, with a
// sub-line for the reset countdown (left) and weekly pace (right). Fill color tracks the
// same green/amber/red thresholds the chip uses (pct_color in the ai_usage blocklet).
Item {
    id: m
    property string label: ""
    property real pct: 0
    property int reset: -1          // seconds until reset; < 0 = none
    property string pace: ""

    implicitHeight: topRow.height + (sub.height > 0 ? sub.height + 2 : 0)

    function threshColor(p) {
        if (p >= 90) return "#FF1744";
        if (p >= 70) return "#FFD600";
        return "#00C853";
    }
    function fmtReset(s) {
        if (s < 0) return "";
        var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), mi = Math.floor((s % 3600) / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + mi + "m";
        if (mi > 0) return mi + "m";
        return "<1m";
    }

    Item {
        id: topRow
        width: parent.width
        height: 18

        Text {
            id: lbl
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: m.label
            color: Theme.text
            font.pixelSize: 13
            font.bold: true
        }
        Rectangle {                                   // track
            id: track
            anchors.left: lbl.right
            anchors.leftMargin: 2
            anchors.right: pctT.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: Theme.surface
            Rectangle {                               // fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, Math.min(1, m.pct / 100)) * parent.width
                radius: 4
                color: m.threshColor(m.pct)
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            id: pctT
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: Math.round(m.pct) + "%"
            color: m.threshColor(m.pct)
            font.pixelSize: 13
            font.bold: true
        }
    }

    Item {
        id: sub
        anchors.top: topRow.bottom
        anchors.topMargin: 2
        width: parent.width
        height: (resetT.text !== "" || paceT.text !== "") ? 15 : 0

        Text {
            id: resetT
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: m.reset >= 0 ? "resets in " + m.fmtReset(m.reset) : ""
            color: Theme.subtext
            font.pixelSize: 12
        }
        Text {
            id: paceT
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: m.pace
            color: Theme.subtext
            font.pixelSize: 12
        }
    }
}
