import Quickshell.Services.Pipewire
import QtQuick

// Default sink volume — scroll to change, click to mute.
Rectangle {
    id: audio
    readonly property var sink: Pipewire.defaultAudioSink

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
        text: (audio.sink && audio.sink.audio)
            ? (audio.sink.audio.muted ? "muted" : "VOL " + Math.round(audio.sink.audio.volume * 100) + "%")
            : "—"
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => {
            if (!audio.sink || !audio.sink.audio) return;
            const step = 0.05;
            const dir = wheel.angleDelta.y > 0 ? 1 : -1;
            audio.sink.audio.volume = Math.max(0, Math.min(1, audio.sink.audio.volume + dir * step));
        }
        onClicked: {
            if (audio.sink && audio.sink.audio)
                audio.sink.audio.muted = !audio.sink.audio.muted;
        }
    }
}
