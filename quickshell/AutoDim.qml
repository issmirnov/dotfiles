pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for the manual brightness-override marker shared with
// hexane-nightlight (~/.cache/hexane-nightlight/override). A present marker means
// the user is in control (HELD); absent means auto-dim is armed. nightlight owns
// expiry (it deletes the marker after the next sunrise), so the bar keys purely
// off the marker's PRESENCE. Callers invoke pause() once per manual gesture, so
// no write throttling is needed here.
Singleton {
    id: root

    readonly property string path: "/home/vania/.cache/hexane-nightlight/override"
    readonly property string nightlight: "/home/vania/.dotfiles/bin/hexane-nightlight"
    property bool active: false      // a valid override marker is present (HELD)

    // Pause auto-dim: write the marker. `v` is informational (nightlight ignores it,
    // keying off `since`). date -Iseconds → an offset ISO string (parses on any py3.7+).
    function pause(v) {
        root.active = true;          // optimistic; the FileView confirms/corrects
        markProc.command = ["sh", "-c",
            'd=$(dirname "$1"); mkdir -p "$d"; ' +
            'printf \'{"since":"%s","value":%s}\' "$(date -Iseconds)" "$2" > "$1"',
            "sh", root.path, String(Math.round(v))];
        markProc.running = true;
    }

    // Re-arm auto-dim: drop the marker, then kick nightlight once by ABSOLUTE path
    // (qs's PATH excludes dotbin) so it takes over now instead of ≤2 min later.
    function arm() {
        root.active = false;         // optimistic
        armProc.running = true;
    }

    Process { id: markProc }
    Process {
        id: armProc
        command: ["sh", "-c", "rm -f '" + root.path + "'; '" + root.nightlight + "' >/dev/null 2>&1"]
    }

    // Watch the marker so external changes (nightlight's daily re-arm delete) flip `active`.
    FileView {
        id: view
        path: root.path
        watchChanges: true
        printErrors: false           // an absent marker is the normal ARMED state, not an error
        onFileChanged: reload()
        onLoaded: root.active = (("" + view.text).indexOf("since") !== -1)
        onLoadFailed: root.active = false
    }
}
