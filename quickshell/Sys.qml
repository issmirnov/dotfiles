pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Polls lib/sysinfo.sh every 2s and exposes cpu%/mem%/temp/net-rate (+ GPU VRAM via nvidia-smi).
// All /proc + hwmon parsing lives in the (tested) shell script; here we just delta counters.
Singleton {
    id: sys

    property real cpuPct: 0
    property int  memPct: 0
    property int  tempC: 0
    property real netRx: 0   // bytes/sec
    property real netTx: 0
    property real load: 0    // 1-min load average
    property int  cpuCores: 0 // logical CPUs; 0 until probed (drives the load chip's saturation ramp)
    property int  vramPct: 0  // GPU 0 VRAM occupied % = (total - free) / total, so the driver's reserved slice counts
    property real vramTotal: 0 // MiB; stays 0 without an NVIDIA GPU, which hides the VRAM chip
    readonly property int vramAlertPct: 90 // at/above this the VRAM chip pulses and a desktop alert fires

    // --- rolling history for the stat-chip sparklines (~2 min at the 2s poll) ---
    readonly property int histLen: 60
    property var cpuHist: []
    property var memHist: []
    property var tempHist: []
    property var loadHist: []
    property var netRxHist: []
    property var netTxHist: []
    property var vramHist: []

    // push onto a *copy* — mutating an array in place does not notify QML bindings
    function _push(arr, v) {
        var a = arr.slice();
        a.push(v);
        while (a.length > sys.histLen) a.shift();
        return a;
    }

    property var _cpu   // { idle, total }
    property var _net   // { rx, tx, t }

    Process {
        id: proc
        command: ["/home/vania/.config/quickshell/lib/sysinfo.sh"]
        stdout: StdioCollector {
            onStreamFinished: sys._parse(text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // one-shot probe: logical CPU count, so the load chip can ramp on saturation (load/cores)
    Process {
        command: ["nproc"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt(text);
                if (n > 0)
                    sys.cpuCores = n;
            }
        }
    }

    // GPU VRAM: one long-lived `nvidia-smi -l 2` streams "free, total" (MiB) every 2s, which is
    // cheaper than spawning it per poll. Without an NVIDIA GPU it never starts and vramTotal stays 0.
    Process {
        command: ["nvidia-smi", "-i", "0", "--query-gpu=memory.free,memory.total",
                  "--format=csv,noheader,nounits", "-l", "2"]
        running: true
        stdout: SplitParser {
            onRead: line => sys._parseVram(line)
        }
        onExited: sys.vramTotal = 0   // died (driver hiccup): hide the chip rather than freeze it
    }

    function _parseVram(line) {
        const p = ("" + line).split(",").map(Number);   // "free, total"
        if (p.length < 2 || p.some(isNaN) || p[1] <= 0)
            return;
        sys.vramTotal = p[1];
        sys.vramPct = Math.round(100 * (p[1] - p[0]) / p[1]);
        sys.vramHist = sys._push(sys.vramHist, sys.vramPct);

        // one alert per climb past the line; re-arms only once it falls 5 points back under it
        if (sys.vramPct >= sys.vramAlertPct && !sys._vramAlerted) {
            sys._vramAlerted = true;
            vramAlert.running = true;
        } else if (sys.vramPct < sys.vramAlertPct - 5) {
            sys._vramAlerted = false;
        }
    }

    // VRAM desktop alert. Sent from this singleton so a multi-monitor bar notifies once, not once
    // per screen. It first fetches the top consumers (sysdetail.sh) so the alert says what to close.
    property bool _vramAlerted: false
    Process {
        id: vramAlert
        command: ["/home/vania/.config/quickshell/lib/sysdetail.sh", "vram"]
        stdout: StdioCollector {
            onStreamFinished: sys._notifyVram(text)
        }
    }

    function _notifyVram(json) {
        let d = {};
        try { d = JSON.parse(json) || {}; } catch (e) {}
        const fmt = mb => mb >= 1024 ? (mb / 1024).toFixed(1) + "G" : Math.round(mb) + "M";
        const top = (d.procs || []).slice(0, 3).map(p => p.name + " " + fmt(p.mb)).join(", ");
        const body = [d.total_mb ? fmt(d.free_mb) + " free" : "", top ? "top: " + top : ""]
                         .filter(s => s).join(" · ");
        Quickshell.execDetached(["notify-send", "-a", "VRAM", "-u", "critical",
                                 "-h", "string:x-canonical-private-synchronous:vram",   // replace, don't stack
                                 "⚠️ VRAM " + sys.vramPct + "% full", body]);
    }

    function _parse(line) {
        const p = ("" + line).trim().split(/\s+/).map(Number);
        if (p.length < 6 || p.some(isNaN))
            return;
        const idle = p[0], total = p[1], mem = p[2], temp = p[3], rx = p[4], tx = p[5];
        sys.load = p.length > 6 ? p[6] : 0;

        if (sys._cpu) {
            const dt = total - sys._cpu.total;
            const di = idle - sys._cpu.idle;
            if (dt > 0)
                sys.cpuPct = Math.max(0, Math.min(100, 100 * (dt - di) / dt));
        }
        sys._cpu = { idle: idle, total: total };

        sys.memPct = mem;
        sys.tempC = temp;

        const now = Date.now();
        if (sys._net) {
            const dts = (now - sys._net.t) / 1000;
            if (dts > 0) {
                sys.netRx = Math.max(0, (rx - sys._net.rx) / dts);
                sys.netTx = Math.max(0, (tx - sys._net.tx) / dts);
            }
        }
        sys._net = { rx: rx, tx: tx, t: now };

        sys.cpuHist   = sys._push(sys.cpuHist,   sys.cpuPct);
        sys.memHist   = sys._push(sys.memHist,   sys.memPct);
        sys.tempHist  = sys._push(sys.tempHist,  sys.tempC);
        sys.loadHist  = sys._push(sys.loadHist,  sys.load);
        sys.netRxHist = sys._push(sys.netRxHist, sys.netRx);
        sys.netTxHist = sys._push(sys.netTxHist, sys.netTx);
    }
}
