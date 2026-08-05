-- Hyprland configuration (Lua).
-- Migrated from hyprland.conf on 2026-08-04. Targets Hyprland >= 0.56.
-- hyprlang (.conf) is deprecated since 0.55; this is the current format.
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- NOTE: hyprlock / hypridle still use their own .conf files — those stay as-is.

------------------------------------------------------------------------
-- PROGRAMS
------------------------------------------------------------------------
local terminal    = "alacritty"
-- GDK_DPI_SCALE enlarges nemo's fonts (~40%) at 4K scale=1 without touching other
-- GTK apps or global scaling. Fonts only; icons/layout unchanged. Tune the number
-- (1.25 = subtler, 1.6 = bigger). NOTE: nemo is single-instance, so close any open
-- nemo window before a new value takes effect.
local fileManager = "env GDK_DPI_SCALE=1.4 nemo"
local menu        = "~/.dotfiles/hypr/scripts/hypr-switch"  -- SUPER+Space switcher: windows+workspaces+fav apps (fuzzel dmenu); was "fuzzel"
-- NOTE: keep WaylandFractionalScaleV1 ENABLED. Disabling it while chrome-flags.conf
-- forces --force-device-scale-factor makes Chrome paint only part of its window
-- (transparent remainder shows the wallpaper). Verified 2026-08-04.
local browser     = "google-chrome-stable --ozone-platform=wayland --enable-features=WaylandLinuxDrmSyncobj"

local leftMon  = "DP-1"
local rightMon = "DP-2"

------------------------------------------------------------------------
-- MONITORS  (https://wiki.hypr.land/Configuring/Basics/Monitors/)
------------------------------------------------------------------------
hl.monitor({ output = "",       mode = "preferred",        position = "auto",   scale = "auto" })
hl.monitor({ output = leftMon,  mode = "3840x2160@119.91", position = "0x0",    scale = 1 })
hl.monitor({ output = rightMon, mode = "3840x2160@119.91", position = "3840x0", scale = 1 })
hl.monitor({ output = "HDMI-A-2", mode = "2560x720@60.266", position = "4480x2160", scale = 1 })  -- Xeneon Edge, native 2560x720, centered under DP-2

-- Route the Xeneon Edge touchscreen to its own output. Without this, Wayland/Hyprland
-- normalizes touch across the WHOLE monitor layout, so taps on the Edge land on the wrong
-- screen. (Runtime-equivalent: hyprctl eval 'hl.device({ name=..., output=... })'.)
hl.device({ name = "wch.cn-touchscreen", output = "HDMI-A-2" })

-- Per-monitor workspaces: 1-5 -> left, 6-10 -> right
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = leftMon })
end
for i = 6, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = rightMon })
end

-- Named app workspaces, all pinned to the right monitor (DP-2). The matching window
-- rules (see WINDOW RULES below) route each app into its own workspace.
hl.workspace_rule({ workspace = "name:slack",    monitor = rightMon })
hl.workspace_rule({ workspace = "name:telegram", monitor = rightMon })
hl.workspace_rule({ workspace = "name:discord",  monitor = rightMon })
hl.workspace_rule({ workspace = "name:osrs",     monitor = rightMon })
hl.workspace_rule({ workspace = "name:spotify",  monitor = rightMon })
hl.workspace_rule({ workspace = "name:signal",   monitor = rightMon })

------------------------------------------------------------------------
-- ENVIRONMENT
------------------------------------------------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")           -- change to qt6ct if you switch
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- nvidia (current wiki recommendation is just these two + the decode backend)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")                   -- hardware video decode via libva-nvidia-driver

------------------------------------------------------------------------
-- AUTOSTART (exec-once equivalents)
------------------------------------------------------------------------
hl.on("hyprland.start", function()
    -- load hyprpm plugins (hyprbars), then re-parse so the guarded plugin block
    -- below applies its styling/buttons (config is parsed before the plugin loads)
    hl.exec_cmd("hyprpm reload -n && hyprctl reload")
    -- hl.exec_cmd("waybar")   -- swapped to Quickshell; uncomment to fall back to waybar
    hl.exec_cmd("qs")
    hl.exec_cmd(browser)
    hl.exec_cmd(terminal)
    -- night shift: wlsunset, Denver coords, 3700K night / 4500K day
    hl.exec_cmd("wlsunset -l 39.7392 -L -104.9903 -t 3700 -T 4500")
    hl.exec_cmd("telegram-desktop")
    hl.exec_cmd("slack")
    hl.exec_cmd("webcord")
    -- hl.exec_cmd("workstyle >/tmp/workstyle.log 2>&1")   -- waybar-only; Quickshell reads clients directly
    hl.exec_cmd("walker --gapplication-service")         -- pre-launch launcher
    -- Xeneon Edge dashboard: now supervised by systemd --user (Restart=on-failure);
    -- unit at ~/.dotfiles/systemd/xeneon-edge.service. Import the Wayland env into
    -- the --user manager, clear any crash-loop lockout left from a previous session,
    -- then (re)start the unit. The app still auto-detects the HDMI-A-2 panel by model
    -- and fullscreens on it. Logs -> `journalctl --user -u xeneon-edge`.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; systemctl --user reset-failed xeneon-edge.service; systemctl --user restart xeneon-edge.service")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("noisetorch")                            -- RNN noise suppression
    hl.exec_cmd("wl-paste --watch cliphist store")       -- clipboard history (fixed)
    hl.exec_cmd("nm-applet --indicator")                 -- network tray
    hl.exec_cmd("blueman-applet")                        -- bluetooth tray
end)

------------------------------------------------------------------------
-- LOOK AND FEEL  (https://wiki.hypr.land/Configuring/Basics/Variables/)
------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 20,
        border_size = 4,
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout        = "dwindle",
        allow_tearing = false,
    },

    decoration = {
        rounding       = 15,
        rounding_power = 4,      -- iOS-style squircle corners (was 2.0)

        dim_inactive = false,    -- don't dim windows on the unfocused monitor
        dim_strength = 0.1,

        blur = {
            enabled  = true,
            size     = 5,
            passes   = 3,
            noise    = 0.012,
            contrast = 0.90,
            vibrancy = 0.1696,
            xray     = true,     -- cheaper floating-window blur
        },

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            offset       = { 0, 0 },
            color        = 0x00000080,
            sharp        = false,
        },

        -- Inner glow disabled — was a second blue/green shimmer halo; keeping just the border.
        glow = {
            enabled      = false,
            range        = 12,
            render_power = 3,
            color        = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
        },

        -- Motion blur on move/resize (Hyprland 0.56+)
        motion_blur = {
            enabled = true,
            samples = 7,
        },
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout     = "us",
        follow_mouse  = 1,        -- was 1; changed for jetbrains historically
        mouse_refocus = true,
        sensitivity   = 0,
        touchpad = {
            natural_scroll = false,
        },
    },

    -- No scroll debounce: every wheel tick fires immediately, rapid spins cycle
    -- multiple workspaces. Bump to ~15 if a single detent ever overshoots.
    binds = {
        scroll_event_delay = 0,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
        new_on_top = true,
        mfact      = 0.5,
    },

    misc = {
        force_default_wallpaper    = -1,     -- disable the anime mascot wallpapers
        mouse_move_focuses_monitor = true,
        focus_on_activate          = false,  -- stop telegram etc. stealing focus
    },

    ecosystem = {
        no_update_news = true,   -- no "what's new" popup on version bumps
    },
})

------------------------------------------------------------------------
-- ANIMATIONS  (springs = the good stuff Lua unlocks)
------------------------------------------------------------------------
hl.curve("linear",   { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("smooth",   { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("bouncy",   { type = "spring", mass = 1, stiffness = 320, dampening = 18 })  -- overshoot/bounce
hl.curve("snappy",   { type = "spring", mass = 1, stiffness = 600, dampening = 40 })  -- fast settle, minimal bounce

hl.animation({ leaf = "windows",     enabled = true, speed = 5,  spring = "bouncy" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5,  spring = "bouncy", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4,  bezier = "linear", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = false })   -- static gradient border (no shimmer)
hl.animation({ leaf = "glowangle",   enabled = false })   -- glow disabled
hl.animation({ leaf = "fade",        enabled = true, speed = 3,  bezier = "default" })
-- Disabled = instant switch. Named app workspaces (slack/telegram/osrs) get negative
-- ids, so Hyprland's id-ordered slide brought them in from the wrong side (they slid
-- from the LEFT despite sitting on the right of the bar). The leaf is global with no
-- per-workspace override, so instant is the trade for correct direction everywhere.
hl.animation({ leaf = "workspaces",  enabled = false, speed = 4,  spring = "snappy", style = "slide" })

------------------------------------------------------------------------
-- KEYBINDINGS  (https://wiki.hypr.land/Configuring/Basics/Binds/)
------------------------------------------------------------------------
local mainMod = "SUPER"

hl.bind(mainMod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + X",         hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd(browser .. " --profile-directory=Default --new-window"))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + T",         hl.dsp.layout("orientationnext"))
hl.bind(mainMod .. " + R",         hl.dsp.layout("rollnext"), { release = true })
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + Space",     hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P",         hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + U",         hl.dsp.focus({ urgent_or_last = true }))

-- clipboard picker + screenshots
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("alacritty -e zsh -c 'cliphist list | fzf | cliphist decode | wl-copy'"))
hl.bind("XF86Tools",                   hl.dsp.exec_cmd("grimblast --notify --freeze copysave area ~/Pictures/$(date +'%Y-%m-%d-%H%M%S.png')"))
hl.bind("SHIFT + XF86Tools",           hl.dsp.exec_cmd("grimblast --notify copysave output ~/Pictures/$(date +'%Y-%m-%d-%H%M%S.png')"))
hl.bind(mainMod .. " + XF86Tools",     hl.dsp.exec_cmd("grimblast --notify copysave active ~/Pictures/$(date +'%Y-%m-%d-%H%M%S.png')"))

-- move focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + Tab",   hl.dsp.window.cycle_next())

-- move windows
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- workspaces: SUPER + [0-9] to switch, SUPER + SHIFT + [0-9] to move (silent)
for i = 1, 10 do
    local key = i % 10   -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Jump straight to a named app workspace (SUPER+ALT layer; the SUPER+T / SUPER+R layout binds stay put).
hl.bind(mainMod .. " + ALT + S", hl.dsp.focus({ workspace = "name:slack" }))
hl.bind(mainMod .. " + ALT + T", hl.dsp.focus({ workspace = "name:telegram" }))
hl.bind(mainMod .. " + ALT + R", hl.dsp.focus({ workspace = "name:osrs" }))

-- named workspaces via rofi (parity with i3's mod+Shift+a / mod+Shift+s):
--   SUPER + SHIFT + A  -> rename the CURRENT workspace
--   SUPER + SHIFT + S  -> move the FOCUSED window to a chosen/typed workspace
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("~/.dotfiles/hypr/scripts/hypr-rename"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.dotfiles/hypr/scripts/hypr-move"))

-- scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e+1" }))

-- move/resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

------------------------------------------------------------------------
-- WINDOW RULES  (https://wiki.hypr.land/Configuring/Basics/Window-Rules/)
------------------------------------------------------------------------
-- Ignore maximize requests from all apps
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

-- App -> its own named workspace (all pinned to DP-2 via workspace_rule above).
hl.window_rule({ name = "slack-workspace", match = { class = "^(slack)$" }, workspace = "name:slack" })
-- Telegram Desktop's class carries a per-install hash suffix (org.telegram.desktop._<hash>), so match a prefix.
hl.window_rule({ name = "telegram-workspace", match = { class = "^(org\\.telegram\\.desktop.*)$" }, workspace = "name:telegram" })
-- Discord: WebCord is the daily client (autostarts); also route the official discord client if opened.
hl.window_rule({ name = "discord-workspace", match = { class = "^(WebCord|discord)$" }, workspace = "name:discord" })
-- OSRS: RuneLite runs under XWayland; class is the dashified Java main class net.runelite.client.RuneLite.
hl.window_rule({ name = "osrs-workspace", match = { class = "^(net-runelite-client-RuneLite)$" }, workspace = "name:osrs" })
hl.window_rule({ name = "spotify-workspace", match = { class = "^(Spotify)$" }, workspace = "name:spotify" })
hl.window_rule({ name = "signal-workspace", match = { class = "^(signal)$" }, workspace = "name:signal" })

-- Sensible minimum size for floating popups (oauth logins etc.)
hl.window_rule({ name = "float-minsize", match = { float = true }, min_size = { 300, 200 } })

-- Border color accents for floating / fullscreen
hl.window_rule({ name = "float-border",      match = { float = true },      border_color = { colors = { "rgba(32CD32AA)", "rgba(7CFC0077)" }, angle = 0 } })
hl.window_rule({ name = "fullscreen-border", match = { fullscreen = true }, border_color = { colors = { "rgba(FF0000AA)", "rgba(88080877)" }, angle = 0 } })
hl.window_rule({ name = "fullscreen-bordersize", match = { fullscreen = true }, border_size = 8 })

-- Center jetbrains IDE windows
hl.window_rule({ name = "jetbrains-center", match = { class = "jetbrains-idea" }, center = true })

------------------------------------------------------------------------
-- PLUGINS  (https://wiki.hypr.land/Plugins/Using-Plugins/)
------------------------------------------------------------------------
-- hyprbars: real per-window title bars, so tiled windows (especially the many
-- Claude-Code terminals) are distinguishable at a glance. The title text comes
-- from the app itself (alacritty has dynamic_title = true).
--
-- Install once (needs sudo — hyprpm compiles against Hyprland headers):
--     hyprpm update
--     hyprpm add https://github.com/hyprwm/hyprland-plugins
--     hyprpm enable hyprbars
--     hyprpm reload -n
-- After every Hyprland upgrade, rebuild:  hyprpm update && hyprpm reload -n
--
-- The guard keeps this block inert until the plugin is actually loaded, so a
-- config reload never errors when hyprbars is missing (e.g. right after a
-- Hyprland upgrade, before the rebuild). The `hyprpm reload -n` in the autostart
-- block loads the plugin on login, which triggers the config re-parse that then
-- applies everything below.
if hl.plugin ~= nil and hl.plugin.hyprbars ~= nil then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height      = 34,
                bar_color       = "rgb(1a1a1a)",
                col             = { text = "rgb(d8d8d8)" },  -- plugin:hyprbars:col.text (title color)
                bar_text_size   = 15,
                bar_text_font   = "JetBrainsMono Nerd Font Propo",  -- proportional (nicer than Mono), keeps Nerd glyphs
                bar_text_weight = 500,                             -- medium weight = crisper titles
                bar_text_align  = "left",
                bar_padding    = 12,
                bar_part_of_window         = true,
                bar_precedence_over_border = true,
                on_double_click = "hyprctl dispatch fullscreen 1",
            },
        },
    })

    -- Right-aligned window buttons (first added renders rightmost): close, maximize.
    hl.plugin.hyprbars.add_button({ bg_color = "rgb(ac4242)", fg_color = "rgb(ffffff)", size = 14, icon = "󰖭", action = "hyprctl dispatch killactive" })
    hl.plugin.hyprbars.add_button({ bg_color = "rgb(f4bf75)", fg_color = "rgb(181818)", size = 14, icon = "󰖯", action = "hyprctl dispatch fullscreen 1" })
end
