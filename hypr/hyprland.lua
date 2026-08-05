-- Hyprland configuration (Lua).
-- Migrated from hyprland.conf on 2026-08-04. Targets Hyprland >= 0.56.
-- hyprlang (.conf) is deprecated since 0.55; this is the current format.
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- NOTE: hyprlock / hypridle still use their own .conf files — those stay as-is.

------------------------------------------------------------------------
-- PROGRAMS
------------------------------------------------------------------------
local terminal    = "alacritty"
local fileManager = "nemo"
local menu        = "fuzzel"
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
hl.monitor({ output = "HDMI-A-2", mode = "2560x720@60.266", position = "4960x2160", scale = 1.6 })  -- Xeneon Edge, centered under DP-2

-- Per-monitor workspaces: 1-5 -> left, 6-10 -> right
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = leftMon })
end
for i = 6, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = rightMon })
end

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
    hl.exec_cmd("waybar")
    hl.exec_cmd(browser)
    hl.exec_cmd(terminal)
    -- night shift: wlsunset, Denver coords, 3700K night / 4500K day
    hl.exec_cmd("wlsunset -l 39.7392 -L -104.9903 -t 3700 -T 4500")
    hl.exec_cmd("telegram-desktop")
    hl.exec_cmd("slack")
    hl.exec_cmd("webcord")
    hl.exec_cmd("workstyle >/tmp/workstyle.log 2>&1")   -- annotates waybar
    hl.exec_cmd("walker --gapplication-service")         -- pre-launch launcher
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

        dim_inactive = true,     -- subtle depth on unfocused windows
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

hl.animation({ leaf = "windows",     enabled = true, speed = 5,  spring = "bouncy" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5,  spring = "bouncy", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4,  bezier = "linear", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = false })   -- static gradient border (no shimmer)
hl.animation({ leaf = "glowangle",   enabled = false })   -- glow disabled
hl.animation({ leaf = "fade",        enabled = true, speed = 3,  bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 4,  spring = "bouncy", style = "slide" })

------------------------------------------------------------------------
-- KEYBINDINGS  (https://wiki.hypr.land/Configuring/Basics/Binds/)
------------------------------------------------------------------------
local mainMod = "SUPER"

hl.bind(mainMod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + X",         hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd(browser))
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
hl.bind("Print",                   hl.dsp.exec_cmd("slurp | grim -g - - | tee ~/Pictures/$(date +'%Y-%m-%d-%H%M%S.png') | wl-copy"))
hl.bind(mainMod .. " + Print",     hl.dsp.exec_cmd("slurp | grim -g - - | wl-copy"))

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

-- Slack -> its own named workspace
hl.window_rule({ name = "slack-workspace", match = { class = "^(slack)$" }, workspace = "name:slack" })

-- Sensible minimum size for floating popups (oauth logins etc.)
hl.window_rule({ name = "float-minsize", match = { float = true }, min_size = { 300, 200 } })

-- Border color accents for floating / fullscreen
hl.window_rule({ name = "float-border",      match = { float = true },      border_color = { colors = { "rgba(32CD32AA)", "rgba(7CFC0077)" }, angle = 0 } })
hl.window_rule({ name = "fullscreen-border", match = { fullscreen = true }, border_color = { colors = { "rgba(FF0000AA)", "rgba(88080877)" }, angle = 0 } })
hl.window_rule({ name = "fullscreen-bordersize", match = { fullscreen = true }, border_size = 8 })

-- Center jetbrains IDE windows
hl.window_rule({ name = "jetbrains-center", match = { class = "jetbrains-idea" }, center = true })
