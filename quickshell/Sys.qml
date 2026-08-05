pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Polls lib/sysinfo.sh every 2s and exposes cpu%/mem%/temp/net-rate.
// All /proc + hwmon parsing lives in the (tested) shell script; here we just delta counters.
Singleton {
    id: sys

    property real cpuPct: 0
    property int  memPct: 0
    property int  tempC: 0
    property real netRx: 0   // bytes/sec
    property real netTx: 0
    property real load: 0    // 1-min load average

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
    }
}
