import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick

// StatusNotifier tray items — left-click activates, right-click opens the native menu.
Row {
    id: tray
    height: Theme.chipHeight
    spacing: 10

    Repeater {
        model: SystemTray.items
        Item {
            required property var modelData
            width: 20
            height: Theme.chipHeight

            IconImage {
                anchors.centerIn: parent
                implicitSize: 18
                source: modelData.icon
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        modelData.activate();
                    else
                        modelData.display(QsWindow.window, mouse.x, mouse.y);
                }
                onWheel: (wheel) => modelData.scroll(wheel.angleDelta.y, false)
            }
        }
    }
}
