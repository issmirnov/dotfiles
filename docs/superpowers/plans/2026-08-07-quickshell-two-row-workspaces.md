# Two-row (two-deck) workspaces — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Domain skill: **quickshell-bar** (edit → relaunch `qs` → grep `/tmp/qs.log` → grim screenshot).

**Goal:** Make the hexane Quickshell bar two decks tall so long-named workspace pills wrap onto a second row instead of sliding under the clock.

**Architecture:** Grow `barHeight` to two rows; restructure `Bar.qml`'s three centered clusters into a top deck (workspaces · clock · live stats) and a bottom deck (overflow workspaces · calendar/world-clock · tray); turn `Workspaces` into a width-budgeted `Flow` whose two pill rows align to the two deck centers.

**Tech Stack:** Quickshell 0.3.0 (Qt6/QML), Hyprland (Lua). Flat config in `~/.dotfiles/quickshell/` (dir-symlinked to `~/.config/quickshell/`).

## Global Constraints

- **No `border`** on the transparent bar window (QTBUG-137166 blanks the whole bar).
- **No hot-reload trust:** after every edit `pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'`, then `grep -iE 'error|warning|invalid|not a type' /tmp/qs.log` (expect `Configuration Loaded`), then grim-screenshot to QA.
- **Flat layout:** no `qmldir`, no sibling imports — uppercase neighbours auto-import. Pull all colors/metrics from `Theme.*`.
- **Keep as-is:** full workspace names, named-workspace sort, click `activate()`, `overrideIcon` map, `◆ scratch` special badge, per-monitor filter.
- **Commits deferred:** do NOT `git commit` until the user asks; when they do, stage only the three touched files.
- **Screenshot QA:** `grim -o DP-1 -t png /tmp/b.png` then `magick /tmp/b.png -crop 1400x120+40+2 +repage /tmp/c.png` and view `/tmp/c.png`. If black → screen locked or a QML error, not necessarily a render bug.

---

### Task 1: Theme metrics — grow to two decks

**Files:**
- Modify: `~/.dotfiles/quickshell/Theme.qml` (metrics block, ~lines 40-49)

**Interfaces:**
- Produces: `Theme.barHeight` (int, now 90), `Theme.deckHeight` (readonly int = `(barHeight - gap) / 2`), consumed by `Bar.qml` deck heights and `Workspaces.qml` cell heights.

- [ ] **Step 1: Bump barHeight and add deckHeight**

In the `--- metrics ---` block change `barHeight` and add `deckHeight` right after it:

```qml
    readonly property int barHeight:  90          // two decks (was 46)
    readonly property int deckHeight: (barHeight - gap) / 2   // one deck row; middle gap = `gap`
    readonly property int barRadius:  22
```

- [ ] **Step 2: Relaunch and verify a clean parse + taller bar**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type|Configuration Loaded' /tmp/qs.log
```
Expected: `Configuration Loaded`, no QML errors. Screenshot: bar is ~2× taller; existing modules now sit vertically centered in the tall bar (clusters not yet split — that's Task 2).

---

### Task 2: Bar.qml — split into top and bottom decks

**Files:**
- Modify: `~/.dotfiles/quickshell/Bar.qml` (the inner `Rectangle`, lines ~16-73)

**Interfaces:**
- Consumes: `Theme.deckHeight`, `Theme.barHeight`, `Theme.gap`.
- Produces: `topDeck` (Item, anchored top, `height: Theme.deckHeight`) and `bottomDeck` (Item, anchored bottom, `height: Theme.deckHeight`) as the layout frame Task 3's `Workspaces` overlays.

- [ ] **Step 1: Replace the inner Rectangle body with two decks**

Replace everything inside `Rectangle { anchors.fill: parent; radius; color … }` (the three current children) with:

```qml
        // ---- TOP DECK: workspaces (row 1, added in Task 3) · clock · live stats ----
        Item {
            id: topDeck
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: Theme.deckHeight

            Clock {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.gap
                Blocklet { exec: "/home/vania/.dotfiles/i3/blocklets/ai_usage"; instance: "claude:claude-smirnovlabs"; interval: 60000 }
                Blocklet { exec: "/home/vania/.dotfiles/i3/blocklets/ai_usage"; instance: "claude:claude_isgmirnov"; interval: 60000 }
                Blocklet { exec: "/home/vania/.dotfiles/i3/blocklets/ai_usage"; instance: "codex"; interval: 60000 }
                Brightness {}
                AutoDimToggle {}
                Audio {}
                Stats {}
                IdleToggle { barWindow: bar }
            }
        }

        // ---- BOTTOM DECK: overflow workspaces (row 2, Task 3) · world-clock+calendar · tray ----
        Item {
            id: bottomDeck
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: Theme.deckHeight

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.gap * 2
                Blocklet { flat: true; exec: "/home/vania/.dotfiles/i3/blocklets/worldclock"; interval: 30000 }
                Blocklet { flat: true; exec: "/home/vania/.config/quickshell/lib/cal-next"; args: ["current"]; interval: 60000 }
                Blocklet { flat: true; exec: "/home/vania/.config/quickshell/lib/cal-next"; interval: 60000 }
            }
            SysTray {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ---- WORKSPACES overlay the left of BOTH decks (declared last = on top for clicks) ----
        Workspaces {
            anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
            anchors.leftMargin: 12
            barScreen: bar.screen
        }
```

(Clock moves out of the old center Row to the top-deck center alone; the world-clock + two `cal-next` blocklets move to the bottom-deck center; `SysTray` moves out of the right Row to the bottom-deck right. AI-usage/Brightness/AutoDimToggle/Audio/Stats/IdleToggle stay top-right.)

- [ ] **Step 2: Relaunch and QA the deck layout**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type|Configuration Loaded' /tmp/qs.log
grim -o DP-1 -t png /tmp/b.png && magick /tmp/b.png -crop 1600x120+40+2 +repage /tmp/c.png
```
Expected (view `/tmp/c.png`): clock centered on the top deck; AI-usage/stats top-right; world-clock+calendar centered on the bottom deck; tray bottom-right. Workspaces still a single left row (overlapping/misaligned until Task 3 — that's fine here). No QML errors.

---

### Task 3: Workspaces.qml — Flow that wraps across the two decks

**Files:**
- Modify: `~/.dotfiles/quickshell/Workspaces.qml` (root `Row` → `Flow`, delegate wrapped in a deck-height cell, lines 8-131)

**Interfaces:**
- Consumes: `Theme.deckHeight`, `Theme.gap`, `Theme.chipHeight`, `Theme.barHeight`.
- Produces: nothing downstream (leaf component).

- [ ] **Step 1: Change the root from `Row` to a width-budgeted `Flow`**

Replace the root `Row { id: root; … height: Theme.chipHeight; spacing: Theme.gap; … }` opening with:

```qml
Flow {
    id: root
    property var barScreen
    readonly property var hlMonitor: barScreen ? Hyprland.monitorFor(barScreen) : null

    // Two-deck height; wrap top-row-first. Width budget = left edge → short of the
    // centered clock/calendar so pills never slide under them. TUNE `wsBudget`.
    property int wsBudget: Math.max(200, (parent ? parent.width : 1200) / 2 - 260)
    height: Theme.barHeight
    width: wsBudget
    spacing: Theme.gap
    flow: Flow.LeftToRight
```

- [ ] **Step 2: Wrap each pill delegate in a deck-height cell so the two rows land on the deck centers**

The `Repeater` delegate is currently the pill `Rectangle`. Wrap it: make the delegate an `Item` of `height: Theme.deckHeight`, with the existing pill `Rectangle` vertically centered inside. I.e. change the delegate from `Rectangle { id: pill; … }` to:

```qml
        Item {
            id: cell
            required property var modelData
            implicitWidth: pill.width
            height: Theme.deckHeight            // row band; pill centered → aligns deck center

            Rectangle {
                id: pill
                readonly property var ws: cell.modelData
                readonly property bool focused: ws.focused
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.chipHeight
                width: inner.width + 16
                radius: height / 2
                color: ws.urgent ? Theme.urgent
                     : focused ? Theme.wsActiveBg
                     : ma.containsMouse ? Theme.wsHoverBg
                     : Theme.wsIdleBg
                Behavior on color { ColorAnimation { duration: 120 } }
                // … inner Row (name + icon Repeater) and MouseArea UNCHANGED …
            }
        }
```

Keep the inner `Row { id: inner … }`, the icon `Repeater`/`overrideIcon` logic, and the `MouseArea { onClicked: pill.ws.activate() }` exactly as they are — only the outer wrapper and the `required property`/`ws` plumbing move to `cell`. (All `pill.ws` / `pill.focused` references inside stay valid.)

- [ ] **Step 3: Keep the special badge + Connections after the Repeater**

The `special` badge `Rectangle` and the `Connections { onRawEvent … }` stay as trailing children of the `Flow` (the badge flows in after the pills, still top-left region). No change to their bodies.

- [ ] **Step 4: Relaunch and QA the wrap + alignment**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type|Configuration Loaded' /tmp/qs.log
grim -o DP-1 -t png /tmp/b.png && magick /tmp/b.png -crop 1600x120+40+2 +repage /tmp/c.png
```
Expected (view `/tmp/c.png`): pills fill the top-left, overflow to the bottom-left; row 1 aligns with the clock's vertical center, row 2 with the calendar's; no collision with the clock; full names intact.

---

### Task 4: Live tuning & acceptance

**Files:** none (tuning values already in place; adjust `Theme.barHeight`, `Theme.gap`, `root.wsBudget` as needed).

- [ ] **Step 1: Tune vertical alignment.** If row 2 sits above/below the calendar center, nudge `Theme.barHeight` (±2) or the deck `height`/gap so `deckHeight*2 + middleGap == barHeight` and the Flow's row-2 offset (`deckHeight + spacing`) equals the bottom deck's top. Re-screenshot.
- [ ] **Step 2: Tune the width budget.** With a full set of long-named workspaces open, confirm no pill reaches the clock/calendar; if it does, lower `wsBudget`; if pills wrap far too early, raise it. Re-screenshot.
- [ ] **Step 3: Few-workspaces case.** With 2–3 workspaces, confirm the bottom deck still shows calendar + tray (not empty) and the top deck looks normal.
- [ ] **Step 4: Both monitors.** `grim -o DP-2 …` and confirm DP-2 renders identically (two surfaces exist: `hyprctl layers -j | jq … quickshell` → DP-1 + DP-2, ~3820×~88).
- [ ] **Step 5: Interaction.** Click a pill on each deck → switches workspace (`hyprctl activeworkspace`). Toggle the SUPER+C scratchpad → `◆ scratch` badge still appears.
- [ ] **Step 6: No reflow.** Open/close a workspace → tiled windows do NOT jump (always-tall holds height constant).

---

### Task 5: Commit (ONLY when the user asks)

- [ ] **Step 1:** On the user's go-ahead, stage exactly the three files and commit:

```bash
git -C ~/.dotfiles add quickshell/Theme.qml quickshell/Bar.qml quickshell/Workspaces.qml
git -C ~/.dotfiles commit -m "quickshell: two-deck bar — wrap workspace pills to a second row

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(Do NOT `git add -A` — parallel agent sessions + the user's own uncommitted edits share this repo. Durable gotchas → the KB `~/docs/docs/systems/hexane/hyprland-bars.md`.)

---

## Self-Review

**Spec coverage:** barHeight→90 (T1) ✓ · two-deck restructure + exact chip split (T2) ✓ · Flow width-budget + top-first wrap + deck alignment (T3) ✓ · keep names/sort/click/icons/badge (T3) ✓ · always-tall no-reflow (T4.6) ✓ · both monitors (T4.4) ✓ · few-workspace not-empty (T4.3) ✓ · QTBUG no-border (Global) ✓.
**Placeholders:** none — real QML in every code step; tuning task lists concrete values to nudge.
**Type consistency:** `Theme.deckHeight` defined T1, consumed T2/T3; `topDeck`/`bottomDeck` ids T2; `cell.modelData`/`pill.ws` plumbing T3 consistent with retained inner refs.
