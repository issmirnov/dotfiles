import QtQuick

// Reactive view over the Sys singleton — colored pastel chips (matches the approved look).
Row {
    id: stats
    height: Theme.chipHeight
    spacing: Theme.gap

    function fmt(b) {
        if (b < 1024) return Math.round(b) + "B";
        if (b < 1048576) return Math.round(b / 1024) + "K";
        return (b / 1048576).toFixed(1) + "M";
    }

    component Chip: Rectangle {
        property alias label: t.text
        property color accent
        height: Theme.chipHeight
        width: t.width + 16
        radius: Theme.chipRadius
        color: accent
        Text {
            id: t
            anchors.centerIn: parent
            color: Theme.chipText
            font.pixelSize: Theme.fontSize
        }
    }

    Chip { accent: Theme.netCol;  label: "↓" + stats.fmt(Sys.netRx) + " ↑" + stats.fmt(Sys.netTx) }
    Chip { accent: Theme.cpuCol;  label: "CPU " + Math.round(Sys.cpuPct) + "%" }
    Chip { accent: Theme.memCol;  label: "MEM " + Sys.memPct + "%" }
    Chip { accent: Theme.tempCol; label: Sys.tempC + "°C" }
}
