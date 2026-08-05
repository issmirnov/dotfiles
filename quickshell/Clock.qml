import Quickshell
import QtQuick

// Local date + time, prominent (bar center). Minute precision = no per-second wakeups.
Text {
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: true }
    text: Qt.formatDateTime(clock.date, "ddd d MMM  ·  HH:mm")
    color: Theme.text
    font.pixelSize: Theme.fontSize
    font.bold: true
    height: Theme.chipHeight
    verticalAlignment: Text.AlignVCenter
}
