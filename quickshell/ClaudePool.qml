import Quickshell
import Quickshell.Io
import QtQuick

// The better-ccflare Claude fleet: one UsageChip per Anthropic account, left→right in
// ccflare priority order (lower number first). The account ccflare sends the next request
// to (isPrimary) is filled; blocked standbys dim with 🔑/⏸/⏳. One `ai_usage __pool` call
// per poll returns the whole fleet, so order, primary and usage share one snapshot.
Row {
    id: pool
    spacing: Theme.gap

    // Relative to the shell dir so a worktree build (`qs -p <wt>/quickshell`) runs its own
    // script. The kernel resolves `..` after following the ~/.config/quickshell symlink, so
    // the live bar lands on ~/.dotfiles/i3/blocklets/ai_usage.
    property string exec: Quickshell.shellDir + "/../i3/blocklets/ai_usage"
    property int interval: 30000

    property var order: []          // account names in priority order; reassigned only on change
    property var byName: ({})       // name -> __pool row; replaced every poll
    property bool loaded: false     // a poll has finished (gates the "CC ?" placeholder)

    function apply(rows) {
        var m = {}, names = [];
        for (var i = 0; i < rows.length; i++) {
            m[rows[i].name] = rows[i];
            names.push(rows[i].name);
        }
        byName = m;                                 // surviving chips rebind in place
        if (names.join("\n") !== order.join("\n"))
            order = names;                          // rebuilds the chips (closes an open popup)
        loaded = true;
    }

    Process {
        id: proc
        command: ["/usr/bin/env", "BLOCK_INSTANCE=claude", pool.exec, "__pool"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = [];
                try {
                    var o = JSON.parse(text);
                    if (Array.isArray(o))
                        rows = o;
                } catch (e) {}
                pool.apply(rows);
            }
        }
    }
    Timer {
        interval: pool.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Repeater {
        model: pool.order
        UsageChip {
            required property string modelData
            instance: "claude:" + modelData
            exec: pool.exec
            entry: pool.byName[modelData] || ({})
        }
    }

    // nothing from ccflare and nothing cached: one gray chip, like the blocklet's "CC ?"
    UsageChip {
        visible: pool.loaded && pool.order.length === 0
        instance: "claude"
        exec: pool.exec
        entry: ({ text: "CC ?", color: "#888888" })
    }
}
