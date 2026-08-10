# Quickshell stat-chip detail popups + sparklines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the five inert `Stats.qml` chips (net / CPU / MEM / temp / LOAD) clickable — each drops down a read-only detail popup with a live ~2-min history sparkline.

**Architecture:** Sparkline history comes free from the always-running `Sys` singleton (extend its 2 s poll with rolling buffers). Heavier detail (top procs, sensors, per-iface rates) is fetched on-demand by a new `lib/sysdetail.sh` only while a popup is open. A reusable `StatChip.qml` owns the pill + drop-down popup (cloning `Audio.qml`'s anchor + focus-grab), and `Stats.qml` instantiates five of them with per-section content delegates.

**Tech Stack:** Quickshell 0.3.0 (Qt6/QML), bash, `/proc` + hwmon + `ps`/`free`/`sensors`/`nvidia-smi`.

## Global Constraints

- **Config dir:** `~/.dotfiles/quickshell/` (symlinked to `~/.config/quickshell/`). FLAT layout — no `qmldir`, no per-file sibling imports; uppercase-neighbor `.qml` auto-imported.
- **Never trust hot-reload.** After every QML edit: `pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'` then `grep -iE 'error|warning|invalid|not a type' /tmp/qs.log` (expect `Configuration Loaded`).
- **No `border` on the transparent bar window** (QTBUG-137166 blanks the whole bar). Popups here don't add one.
- **PATH:** qs runs child processes with `PATH=/usr/local/bin:/usr/bin`. `sysdetail.sh` must use only tools there (all of `ps`/`free`/`sensors`/`nvidia-smi`/`awk` are in `/usr/bin` — verified). **No `~/.local/bin` dependency.**
- **PopupWindow anchoring:** never set `anchor.rect.x` (collapses the rect). Use `anchor.edges: Bottom|Right` + `anchor.gravity: Bottom|Left` (from `Audio.qml`).
- **Focus-grab click-away:** reuse `Audio.qml`'s imperative arming verbatim (150 ms `grabArm` Timer + `Connections` on `onVisibleChanged`); the declarative `active: popup.visible` binding is known-broken.
- **Commit hygiene:** `~/.dotfiles` is shared `master`. **Stage only these files** — never `git add -A`. Leave the user's uncommitted `hypr/hypridle.conf` etc. alone. Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Theme tokens (exist already):** accents `cpuCol`/`memCol`/`tempCol`/`loadCol`/`netCol`; `barBg`, `surface`, `text`, `subtext`, `chipText`; `chipHeight 32`, `chipRadius 12`, `fontSize 16`, `gap 9`.

---

### Task 1: `lib/sysdetail.sh` — on-demand detail fetcher

The only real logic in the feature. Emits one JSON object per section. Hardened by running it and validating with `jq`.

**Files:**
- Create: `~/.dotfiles/quickshell/lib/sysdetail.sh` (== `~/.config/quickshell/lib/sysdetail.sh` via symlink)

**Interfaces:**
- Produces (consumed by Task 4/5 via `JSON.parse`):
  - `cpu` → `{"procs":[{"name":str,"pct":num}, …≤5]}`
  - `mem` → `{"used_mb":int,"cached_mb":int,"avail_mb":int,"swap_mb":int,"procs":[{"name":str,"mb":int}, …≤5]}`
  - `temp` → `{"sensors":[{"label":str,"c":num,"fan":num?}, …]}`
  - `load` → `{"l1":num,"l5":num,"l15":num,"cores":int,"uptime":str}`
  - `net` → `{"ifaces":[{"name":str,"rx":num,"tx":num}, …],"primary":str,"rx_total":num,"tx_total":num}` (`rx`/`tx` are B/s rates)

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# On-demand detail for the Quickshell stat-chip popups — one JSON object on stdout.
# Usage: sysdetail.sh <cpu|mem|temp|load|net>
# Only /usr/bin tools (ps/free/sensors/nvidia-smi/awk + /proc + hwmon): safe under
# qs's minimal PATH=/usr/local/bin:/usr/bin.
set -uo pipefail

jstr() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }   # escape a string for JSON

sec_cpu() {
  ps -eo pcpu=,comm= --sort=-pcpu 2>/dev/null | head -5 | awk '
    BEGIN{ printf "{\"procs\":[" }
    { pct=$1; $1=""; sub(/^[ \t]+/,""); n=$0; gsub(/\\/,"\\\\",n); gsub(/"/,"\\\"",n)
      printf "%s{\"name\":\"%s\",\"pct\":%s}", (c++?",":""), n, pct+0 }
    END{ print "]}" }'
}

sec_mem() {
  awk '
    /^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^Cached:/{c=$2}
    /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
    END{ printf "%d %d %d %d", (t-a)/1024, c/1024, a/1024, (st-sf)/1024 }' /proc/meminfo \
  | { read used cached avail swap
      procs=$(ps -eo rss=,comm= --sort=-rss 2>/dev/null | head -5 | awk '
        { mb=$1/1024; $1=""; sub(/^[ \t]+/,""); n=$0; gsub(/\\/,"\\\\",n); gsub(/"/,"\\\"",n)
          printf "%s{\"name\":\"%s\",\"mb\":%d}", (c++?",":""), n, mb }')
      printf '{"used_mb":%d,"cached_mb":%d,"avail_mb":%d,"swap_mb":%d,"procs":[%s]}\n' \
        "$used" "$cached" "$avail" "$swap" "$procs"; }
}

sec_temp() {
  # hwmon: coretemp package + a few labeled cores, nvme composite, fans>0
  {
    for h in /sys/class/hwmon/hwmon*; do
      [ -r "$h/name" ] || continue; nm=$(<"$h/name")
      case "$nm" in
        coretemp)
          [ -r "$h/temp1_input" ] && echo "CPU pkg|$(( $(<"$h/temp1_input")/1000 ))|"
          for f in "$h"/temp[2-9]_input "$h"/temp1[0-9]_input; do
            [ -r "$f" ] || continue; lbl="${f%_input}_label"
            l=$([ -r "$lbl" ] && cat "$lbl" || echo core)
            echo "$l|$(( $(<"$f")/1000 ))|"
          done ;;
        nvme) [ -r "$h/temp1_input" ] && echo "NVMe|$(( $(<"$h/temp1_input")/1000 ))|" ;;
      esac
      for f in "$h"/fan[1-9]_input; do
        [ -r "$f" ] || continue; r=$(<"$f"); [ "$r" -gt 0 ] 2>/dev/null && echo "Fan|${r}|rpm"
      done
    done
    # GPU via nvidia-smi (temp + fan%)
    g=$(nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv,noheader,nounits 2>/dev/null | head -1)
    [ -n "$g" ] && echo "GPU|${g%%,*}|${g##*, }"
  } | awk -F'|' '
    BEGIN{ printf "{\"sensors\":[" }
    { l=$1; gsub(/\\/,"\\\\",l); gsub(/"/,"\\\"",l)
      printf "%s{\"label\":\"%s\",\"c\":%s%s}", (c++?",":""), l, $2+0, ($3!=""?",\"fan\":" $3+0:"") }
    END{ print "]}" }'
}

sec_load() {
  read l1 l5 l15 _ < /proc/loadavg
  up=$(awk '{d=int($1/86400);h=int(($1%86400)/3600);m=int(($1%3600)/60)
            if(d)printf "%dd %dh",d,h; else if(h)printf "%dh %dm",h,m; else printf "%dm",m}' /proc/uptime)
  printf '{"l1":%s,"l5":%s,"l15":%s,"cores":%d,"uptime":"%s"}\n' "$l1" "$l5" "$l15" "$(nproc)" "$up"
}

sec_net() {
  snap() { awk 'NR>2{ sub(/^ +/,""); i=index($0,":"); name=substr($0,1,i-1)
                      n=split(substr($0,i+1),f," "); if(name!="lo") print name, f[1], f[9] }' /proc/net/dev; }
  a=$(snap); sleep 0.4; b=$(snap)
  prim=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
  echo "$a" | awk -v B="$b" -v prim="$prim" '
    BEGIN{ n=split(B,bl,"\n"); for(i=1;i<=n;i++){split(bl[i],x," "); rx2[x[1]]=x[2]; tx2[x[1]]=x[3]} }
    { name=$1; rxr=(rx2[name]-$2)/0.4; txr=(tx2[name]-$3)/0.4; if(rxr<0)rxr=0; if(txr<0)txr=0
      order[c++]=name; RX[name]=rxr; TX[name]=txr; RT[name]=rx2[name]; TT[name]=tx2[name] }
    END{ printf "{\"ifaces\":["
         for(i=0;i<c;i++){ nm=order[i]; g=nm; gsub(/\\/,"\\\\",g); gsub(/"/,"\\\"",g)
           printf "%s{\"name\":\"%s\",\"rx\":%d,\"tx\":%d}", (i?",":""), g, RX[nm], TX[nm]) }
         printf "],\"primary\":\"%s\",\"rx_total\":%d,\"tx_total\":%d}\n", prim, RT[prim]+0, TT[prim]+0 }'
}

case "${1:-}" in
  cpu) sec_cpu ;; mem) sec_mem ;; temp) sec_temp ;; load) sec_load ;; net) sec_net ;;
  *) echo '{"error":"usage: sysdetail.sh <cpu|mem|temp|load|net>"}'; exit 2 ;;
esac
```

- [ ] **Step 2: Make executable + validate every section is well-formed JSON**

```bash
chmod +x ~/.dotfiles/quickshell/lib/sysdetail.sh
for s in cpu mem temp load net; do
  printf '== %s ==\n' "$s"
  ~/.config/quickshell/lib/sysdetail.sh "$s" | tee /tmp/sd.json | jq . >/dev/null && echo "JSON OK" || echo "BAD JSON"
  jq -c . /tmp/sd.json
done
```
Expected: each prints `JSON OK` and a sane object (cpu/mem have ≤5 procs; temp lists CPU pkg + GPU; load has cores=24; net has ifaces + primary). **Fix awk/quoting until all five pass** — this is the task's test.

- [ ] **Step 3: Verify it runs under qs's minimal PATH**

```bash
env -i PATH=/usr/local/bin:/usr/bin ~/.config/quickshell/lib/sysdetail.sh temp | jq .
```
Expected: valid JSON (no "command not found"). Confirms no `~/.local/bin` dependency.

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles && git add quickshell/lib/sysdetail.sh && \
git commit -m "feat(quickshell): sysdetail.sh — on-demand JSON detail for stat popups

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `Sys.qml` — rolling history buffers for sparklines

**Files:**
- Modify: `~/.dotfiles/quickshell/Sys.qml`

**Interfaces:**
- Produces: `Sys.histLen` (int), and array props `Sys.cpuHist`, `Sys.memHist`, `Sys.tempHist`, `Sys.loadHist`, `Sys.netRxHist`, `Sys.netTxHist` — each a growing/capped array of numbers, reassigned every 2 s.

- [ ] **Step 1: Add the history properties + helper** (after the existing `property real load: 0` block)

```qml
    readonly property int histLen: 60      // ~2 min at the 2 s poll
    property var cpuHist: []
    property var memHist: []
    property var tempHist: []
    property var loadHist: []
    property var netRxHist: []
    property var netTxHist: []

    // push onto a *copy* — mutating the array in place does NOT notify QML bindings
    function _push(arr, v) {
        var a = arr.slice();
        a.push(v);
        while (a.length > sys.histLen) a.shift();
        return a;
    }
```

- [ ] **Step 2: Append each sample at the end of `_parse`** (just before the closing `}` of `_parse`, after `sys._net = …`)

```qml
        sys.cpuHist   = sys._push(sys.cpuHist,   sys.cpuPct);
        sys.memHist   = sys._push(sys.memHist,   sys.memPct);
        sys.tempHist  = sys._push(sys.tempHist,  sys.tempC);
        sys.loadHist  = sys._push(sys.loadHist,  sys.load);
        sys.netRxHist = sys._push(sys.netRxHist, sys.netRx);
        sys.netTxHist = sys._push(sys.netTxHist, sys.netTx);
```

- [ ] **Step 3: Relaunch + verify clean parse**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'; sleep 2
grep -iE 'error|warning|invalid|not a type' /tmp/qs.log; echo "--- exit $? (1 = no matches = good) ---"
grep -c "Configuration Loaded" /tmp/qs.log
```
Expected: no error lines; `Configuration Loaded` present. (Buffers fill silently; visually confirmed in Task 5.)

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles && git add quickshell/Sys.qml && \
git commit -m "feat(quickshell): Sys rolling history buffers for stat sparklines

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `Sparkline.qml` — reusable mini-graph

**Files:**
- Create: `~/.dotfiles/quickshell/Sparkline.qml`

**Interfaces:**
- Produces: `Sparkline` component. Props `values` (array), `stroke` (color), `values2` (array, optional 2nd series), `stroke2` (color), `minY`/`maxY` (reals; `NaN` → autoscale). Repaints on `values`/`values2` change.

- [ ] **Step 1: Write it**

```qml
import QtQuick

// Tiny polyline sparkline. One or two series; fixed or autoscaled Y.
Canvas {
    id: spark
    property var values: []
    property color stroke: Theme.text
    property var values2: []
    property color stroke2: Theme.subtext
    property real minY: NaN
    property real maxY: NaN
    implicitHeight: 28
    implicitWidth: 120
    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var series = [[values, stroke], [values2, stroke2]];
        for (var s = 0; s < series.length; s++) {
            var vals = series[s][0], col = series[s][1];
            if (!vals || vals.length < 2) continue;
            var lo = minY, hi = maxY;
            if (isNaN(lo) || isNaN(hi)) {
                lo = Math.min.apply(null, vals);
                hi = Math.max.apply(null, vals);
            }
            if (hi - lo < 1e-6) hi = lo + 1;
            ctx.lineWidth = 2;
            ctx.strokeStyle = col;
            ctx.beginPath();
            for (var i = 0; i < vals.length; i++) {
                var x = width * i / (vals.length - 1);
                var y = height - 1 - (height - 2) * (vals[i] - lo) / (hi - lo);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
    }
}
```

- [ ] **Step 2: Parse check** (relaunch + log as in Task 2 Step 3). Expected: no `not a type` / errors. Visual proof in Task 5.

- [ ] **Step 3: Commit**

```bash
cd ~/.dotfiles && git add quickshell/Sparkline.qml && \
git commit -m "feat(quickshell): Sparkline.qml reusable mini-graph

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `StatChip.qml` — clickable pill + drop-down popup shell

**Files:**
- Create: `~/.dotfiles/quickshell/StatChip.qml`

**Interfaces:**
- Consumes: `Sparkline` (Task 3); `sysdetail.sh` (Task 1).
- Produces: `StatChip` component. Props: `label` (string), `accent` (color), `section` (string → `sysdetail.sh` arg), `history`/`history2` (arrays), `dualSpark` (bool), `sparkMin`/`sparkMax` (reals), `contentComponent` (Component — the per-section body), and `model` (var — parsed JSON, read by the content delegate as `<chipId>.model`).

- [ ] **Step 1: Write it** (clones `Audio.qml`'s popup anchor + focus-grab)

```qml
import Quickshell
import Quickshell.Hyprland
import QtQuick

// A stat pill that drops down a detail popup on click (dismiss on click-away).
Rectangle {
    id: chip
    property string label
    property color accent
    property string section
    property var history: []
    property var history2: []
    property bool dualSpark: false
    property real sparkMin: NaN
    property real sparkMax: NaN
    property Component contentComponent
    property var model: ({})            // parsed sysdetail.sh JSON; delegate reads <chipId>.model

    height: Theme.chipHeight
    width: t.width + 16
    radius: Theme.chipRadius
    color: accent

    Text {
        id: t
        anchors.centerIn: parent
        text: chip.label
        color: Theme.chipText
        font.pixelSize: Theme.fontSize
    }

    // on-demand detail, only while the popup is open
    Process {
        id: detail
        command: ["/home/vania/.config/quickshell/lib/sysdetail.sh", chip.section]
        stdout: StdioCollector {
            onStreamFinished: { try { var o = JSON.parse(text); if (o) chip.model = o; } catch (e) {} }
        }
    }
    Timer {
        interval: 2000; repeat: true; running: popup.visible; triggeredOnStart: true
        onTriggered: detail.running = true
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    PopupWindow {
        id: popup
        anchor.item: chip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: 320
        implicitHeight: body.implicitHeight + 6      // +6 = the see-through gap
        visible: false
        color: "transparent"

        // click-away dismiss — imperative arming, copied from Audio.qml (declarative binding is broken)
        HyprlandFocusGrab { id: grab; windows: [popup]; onCleared: popup.visible = false }
        Connections {
            target: popup
            function onVisibleChanged() {
                if (popup.visible) grabArm.restart();
                else { grabArm.stop(); grab.active = false; }
            }
        }
        Timer { id: grabArm; interval: 150; onTriggered: grab.active = popup.visible }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            radius: Theme.chipRadius
            color: Theme.barBg

            Column {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Text {
                    text: chip.label
                    color: chip.accent
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Sparkline {
                    width: body.width
                    height: 28
                    values: chip.history
                    stroke: chip.accent
                    values2: chip.dualSpark ? chip.history2 : []
                    stroke2: Theme.subtext
                    minY: chip.sparkMin
                    maxY: chip.sparkMax
                }
                Loader {
                    width: body.width
                    active: popup.visible
                    sourceComponent: chip.contentComponent
                }
            }
        }
    }
}
```

- [ ] **Step 2: Parse check** (relaunch + log). Expected: no errors. StatChip isn't instantiated yet, so no visual change — Task 5 wires + proves it.

- [ ] **Step 3: Commit**

```bash
cd ~/.dotfiles && git add quickshell/StatChip.qml && \
git commit -m "feat(quickshell): StatChip.qml — pill + click-away detail popup shell

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `Stats.qml` — wire five StatChips with per-section bodies

**Files:**
- Modify: `~/.dotfiles/quickshell/Stats.qml` (full rewrite of the chip list; keep the `fmt` helper)

**Interfaces:**
- Consumes: `StatChip` (Task 4), `Sys.*` values + `Sys.*Hist` (Task 2), Theme accents.

- [ ] **Step 1: Rewrite `Stats.qml`** — keep the `Row` + `fmt`, replace the five `Chip`s with `StatChip`s. Each content delegate reads its own `<chipId>.model` (lexical scope resolves the id because the `Component` is declared here).

```qml
import QtQuick

// Reactive view over Sys — five clickable stat chips, each with a detail popup.
Row {
    id: stats
    height: Theme.chipHeight
    spacing: Theme.gap

    function fmt(b) {
        if (b < 1024) return Math.round(b) + "B";
        if (b < 1048576) return Math.round(b / 1024) + "K";
        return (b / 1048576).toFixed(1) + "M";
    }
    function mb(x) { return x >= 1024 ? (x / 1024).toFixed(1) + "G" : Math.round(x) + "M"; }

    // small helpers for popup body rows
    component KV: Row {
        property string k
        property string v
        property color kc: Theme.subtext
        spacing: 8
        Text { text: parent.k; color: parent.kc; font.pixelSize: 14 }
        Item { width: 1; height: 1 }
        Text { text: parent.v; color: Theme.text; font.pixelSize: 14 }
    }

    // ---- net ----
    StatChip {
        id: netChip
        section: "net"; accent: Theme.netCol
        label: "↓" + stats.fmt(Sys.netRx) + " ↑" + stats.fmt(Sys.netTx)
        history: Sys.netRxHist; history2: Sys.netTxHist; dualSpark: true
        contentComponent: Component {
            Column {
                spacing: 4
                Repeater {
                    model: netChip.model.ifaces || []
                    KV { k: modelData.name; v: "↓" + stats.fmt(modelData.rx) + "  ↑" + stats.fmt(modelData.tx) }
                }
                KV { k: "session"; kc: Theme.subtext
                     v: "↓" + stats.fmt(netChip.model.rx_total || 0) + "  ↑" + stats.fmt(netChip.model.tx_total || 0) }
            }
        }
    }

    // ---- cpu ----
    StatChip {
        id: cpuChip
        section: "cpu"; accent: Theme.cpuCol
        label: "CPU " + Math.round(Sys.cpuPct) + "%"
        history: Sys.cpuHist; sparkMin: 0; sparkMax: 100
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
        section: "mem"; accent: Theme.memCol
        label: "MEM " + Sys.memPct + "%"
        history: Sys.memHist; sparkMin: 0; sparkMax: 100
        contentComponent: Component {
            Column {
                spacing: 4
                KV { k: "used";  v: stats.mb(memChip.model.used_mb  || 0) }
                KV { k: "cached"; v: stats.mb(memChip.model.cached_mb || 0) }
                KV { k: "avail";  v: stats.mb(memChip.model.avail_mb || 0) }
                KV { k: "swap";   v: stats.mb(memChip.model.swap_mb  || 0) }
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
        section: "temp"; accent: Theme.tempCol
        label: Sys.tempC + "°C"
        history: Sys.tempHist
        contentComponent: Component {
            Column {
                spacing: 4
                Repeater {
                    model: tempChip.model.sensors || []
                    KV { k: modelData.label
                         v: modelData.c + "°C" + (modelData.fan !== undefined ? "   " + modelData.fan + (modelData.label === "Fan" ? " rpm" : "%") : "") }
                }
            }
        }
    }

    // ---- load ----
    StatChip {
        id: loadChip
        section: "load"; accent: Theme.loadCol
        label: "LOAD " + Sys.load.toFixed(2)
        history: Sys.loadHist
        contentComponent: Component {
            Column {
                spacing: 4
                KV { k: "1 / 5 / 15"; v: (loadChip.model.l1||0) + " / " + (loadChip.model.l5||0) + " / " + (loadChip.model.l15||0) }
                KV { k: "saturation"
                     v: (loadChip.model.cores ? Math.round(100*(loadChip.model.l1||0)/loadChip.model.cores) : 0) + "%  of " + (loadChip.model.cores||"?") + " cores" }
                KV { k: "uptime"; v: loadChip.model.uptime || "—" }
            }
        }
    }
}
```

- [ ] **Step 2: Relaunch + verify clean parse**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'; sleep 2
grep -iE 'error|warning|invalid|not a type' /tmp/qs.log; echo "--- (no matches = good) ---"
grep -c "Configuration Loaded" /tmp/qs.log
```
Expected: no errors; `Configuration Loaded`.

- [ ] **Step 3: Confirm the bar surfaces still render** (not blank — rules out an accidental blank-bar regression)

```bash
hyprctl layers -j | jq -r 'to_entries[] | .key as $o | .value.levels | to_entries[] | .value[]? | select(.namespace|test("quickshell";"i")) | "\($o): \(.w)x\(.h)"'
```
Expected: two ~3820x46 surfaces (DP-1 + DP-2).

- [ ] **Step 4: Visual QA — open each popup and screenshot**

Use hypr-cua `screenshot(output="DP-1")` → `click(x,y,frame_id)` on each chip (top-right cluster), or grim-crop after clicking. For each of net/CPU/MEM/temp/LOAD confirm: popup drops **below** the chip, right-aligned & on-screen; sparkline draws; body shows live rows; **clicking elsewhere dismisses it**. Re-open one after ~10 s to confirm live refresh.

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles && git add quickshell/Stats.qml && \
git commit -m "feat(quickshell): stat chips open detail popups with sparklines

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** in-bar popups ✓ (Task 4/5); read-only ✓; sparklines ✓ (Task 2/3); all five chips ✓ (Task 5); ~2-min window ✓ (`histLen 60`, Task 2); on-demand detail ✓ (Task 1, Timer `running: popup.visible`); Audio anchor + focus-grab reuse ✓ (Task 4); GPU via nvidia-smi ✓ (Task 1 `sec_temp`); load/cores saturation ✓ (Task 5 load body); net per-iface double-sample ✓ (Task 1 `sec_net`). No spec requirement without a task.

**Placeholder scan:** no TBD/TODO; every code step is complete; commands have expected output.

**Type consistency:** `sysdetail.sh` JSON keys (`procs[].pct`, `procs[].mb`, `sensors[].c/.fan`, `l1/l5/l15/cores/uptime`, `ifaces[].rx/.tx`, `rx_total/tx_total`, `primary`) match every reader in Task 5. `Sys.*Hist` names match Task 5 bindings. `StatChip` prop names (`history`, `history2`, `dualSpark`, `sparkMin/Max`, `contentComponent`, `model`) match Task 5 usage. `Sparkline` props (`values`, `values2`, `stroke`, `stroke2`, `minY`, `maxY`) match Task 4 usage.
