import QtQuick

// Reactive view over Sys — five clickable stat chips, each dropping down a detail
// popup with a live sparkline. The popup bodies are per-section delegates that read
// their own chip's parsed `model` (lexical scope resolves <chipId> here).
Row {
    id: stats
    height: Theme.chipHeight
    spacing: Theme.gap

    // bytes/sec or cumulative bytes → compact string (adds a G tier for session totals)
    function fmt(b) {
        if (b < 1024) return Math.round(b) + "B";
        if (b < 1048576) return Math.round(b / 1024) + "K";
        if (b < 1073741824) return (b / 1048576).toFixed(1) + "M";
        return (b / 1073741824).toFixed(1) + "G";
    }
    // megabytes → M/G
    function mb(x) { return x >= 1024 ? (x / 1024).toFixed(1) + "G" : Math.round(x) + "M"; }

    // one labeled row inside a popup body
    component KV: Row {
        id: kvRoot
        property string k
        property string v
        property color kc: Theme.subtext
        spacing: 10
        Text { text: kvRoot.k; color: kvRoot.kc; font.pixelSize: 14; width: 118; elide: Text.ElideRight }
        Text { text: kvRoot.v; color: Theme.text; font.pixelSize: 14 }
    }

    // ---- net ----
    StatChip {
        id: netChip
        section: "net"
        accent: Theme.netCol
        label: "↓" + stats.fmt(Sys.netRx) + " ↑" + stats.fmt(Sys.netTx)
        history: Sys.netRxHist
        history2: Sys.netTxHist
        dualSpark: true
        contentComponent: Component {
            Column {
                spacing: 4
                Repeater {
                    model: netChip.model.ifaces || []
                    KV { k: modelData.name; v: "↓" + stats.fmt(modelData.rx) + "  ↑" + stats.fmt(modelData.tx) }
                }
                KV {
                    k: "session"
                    kc: Theme.subtext
                    v: "↓" + stats.fmt(netChip.model.rx_total || 0) + "  ↑" + stats.fmt(netChip.model.tx_total || 0)
                }
            }
        }
    }

    // ---- cpu ----
    StatChip {
        id: cpuChip
        section: "cpu"
        accent: Theme.cpuCol
        label: "CPU " + Math.round(Sys.cpuPct) + "%"
        history: Sys.cpuHist
        sparkMin: 0
        sparkMax: 100
        contentComponent: Component {
            Column {
                spacing: 4
                Repeater {
                    model: cpuChip.model.procs || []
                    KV { k: modelData.name; v: (modelData.pct).toFixed(1) + "%" }
                }
            }
        }
    }

    // ---- mem ----
    StatChip {
        id: memChip
        section: "mem"
        accent: Theme.memCol
        label: "MEM " + Sys.memPct + "%"
        history: Sys.memHist
        sparkMin: 0
        sparkMax: 100
        contentComponent: Component {
            Column {
                spacing: 4
                KV { k: "used";      v: stats.mb(memChip.model.used_mb   || 0) }
                KV { k: "cached";    v: stats.mb(memChip.model.cached_mb || 0) }
                KV { k: "available"; v: stats.mb(memChip.model.avail_mb  || 0) }
                KV { k: "swap";      v: stats.mb(memChip.model.swap_mb   || 0) }
                Item { width: 1; height: 6 }
                Repeater {
                    model: memChip.model.procs || []
                    KV { k: modelData.name; v: stats.mb(modelData.mb) }
                }
            }
        }
    }

    // ---- temp ----
    StatChip {
        id: tempChip
        section: "temp"
        accent: Theme.tempCol
        label: Sys.tempC + "°C"
        history: Sys.tempHist
        contentComponent: Component {
            Column {
                spacing: 4
                Repeater {
                    model: tempChip.model.sensors || []
                    KV {
                        k: modelData.label
                        v: modelData.c + "°C" + (modelData.fan !== undefined ? "   fan " + modelData.fan + "%" : "")
                    }
                }
            }
        }
    }

    // ---- load ----
    StatChip {
        id: loadChip
        section: "load"
        accent: Theme.loadCol
        label: "LOAD " + Sys.load.toFixed(2)
        history: Sys.loadHist
        contentComponent: Component {
            Column {
                spacing: 4
                KV { k: "load avg"; v: (loadChip.model.l1 || 0) + " / " + (loadChip.model.l5 || 0) + " / " + (loadChip.model.l15 || 0) }
                KV {
                    k: "saturation"
                    v: (loadChip.model.cores ? Math.round(100 * (loadChip.model.l1 || 0) / loadChip.model.cores) : 0) + "% of " + (loadChip.model.cores || "?") + " cores"
                }
                KV { k: "uptime"; v: loadChip.model.uptime || "—" }
            }
        }
    }
}
