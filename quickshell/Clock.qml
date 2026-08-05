import Quickshell
import QtQuick

// Efficient time source: SystemClock at minute precision (no per-second wakeups).
Text {
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: true }
    text: Qt.formatDateTime(clock.date, "ddd  HH:mm")
    color: Theme.text
    font.pixelSize: Theme.fontSize
}
