# havoc-ui

Minecraft-style cheat GUI toolkit for the Havoc hubs (Oaklands / PD / Deadline).
Single-file drop-in: one `loadstring` + a parent `ScreenGui`.

**Status: v0.8-config — sandbox iteration.** Design language: flat square
blocks, **detached per-category panels** (collapsed `[+] Combat` headers
spawn their own lists; drag each panel anywhere), plus a **main HAVOC HUB
panel** with a live module **search box** and an `[x]` visibility switch
for every category list, **right-click module settings drawers**, a **full
keybind system** (mouse buttons, Ctrl/Shift/Alt combos, hold/toggle modes,
ESC-unbinds), and a **Config tab**: live theme editing (presets +
per-colour pickers that repaint everything instantly) plus per-slot
save/load/delete configs. Tight rows, ON = #55FF55 green / OFF = #AAAAAA
gray, inline `[x]` checkboxes and vanilla-style sliders, chat-palette
accents (gold #FFFF55, red #FF5555, aqua #55FFFF).

## Layout

| file | purpose |
| --- | --- |
| `havoc-ui.luau` | the toolkit (single module, `readfile`-friendly) |
| `demo.luau` | sandbox showcase - combat / visuals / player / movement / misc |
| `scripts/check.ps1` | Luau compile gate |

## Wiring

```lua
local UI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

local toaster = UI.makeToaster(screenGui)
UI.init{ notify = toaster, saveDebounced = saveConfigDebounced }

local gui = UI.makeClickGui{ parent = screenGui, width = 180,
    startX = 60, startY = 80 }
local combat = gui.category("Combat")   -- one detached, draggable panel each
combat:addToggle("Auto Parry", getter, setter, hkEntry)
combat:addSlider("Reach", 1, 10, getter, setter, { step = 0.1 })
combat:addDropdown("Target", { "Nearest", "Crosshair" }, getter, setter)
combat:addMultiSelect("Parts", items, isOn, setOn)
combat:addColor("Box Color", getter, setter)
combat:addKeybind(hkEntry)
combat:addButton("Panic", fn, { style = "danger" })
combat:addLabel("small dim note")

track(UI.attachInput())
-- top of your InputBegan handler:
if UI.handleRebindInput(input) then return end
```

## API

`makeClickGui{ parent, width, layout ("row"|"column"), gap, startX, startY,
maxListHeight, scale }` -> `{ panels, category(name, { collapsed }),
setScale, show, hide, toggle, isVisible, destroy }`. Each category is a
detached panel: the collapsed header (`[+] Name`) spawns its list on click,
every panel drags by its own header. A drag never toggles the list — the
header only collapses on a real click. The `HAVOC HUB` panel auto-spawns
in slot 0 and lists every category with an `[x]` switch that hides/shows
that category's panel.

Category rows (each returns `{ row, update }`, `addLabel` returns the
label): `addToggle(text, get, set, hkEntry?, opts)`,
`addSlider(text, min, max, get, set, opts)`,
`addDropdown(text, items, get, set)`,
`addMultiSelect(text, items, isOn, setOn)`,
`addColor(text, get, set, { alpha = true })` — full MC-style picker
(saturation/value square + hue strip + hex input; `alpha = true` adds an
alpha strip and passes a second 0-255 argument to the setter),
`addKeybind(entry, { name })`, `addButton(text, fn, { style, confirm })`,
`addLabel(text)`, `addSeparator()`, `addSection(text)`,
`addStepper(text, min, max, step, get, set, opts)`,
`addRangeSlider(text, min, max, get, set, { step })` (get/set take lo, hi),
`addTextInput(text, get, set, { placeholder })`,
`addProgress(text, get, { format })` (get returns 0..1, auto-repaints),
`addIndicator(text, get, { on, off })` (boolean or string, auto-repaints),
and `addGroup(text, { open })` — an expandable sub-section that returns
the same builder set (no nested groups).

**Module settings drawers**: `addToggle(..., { settings = function(s) ...
end })` puts a `[+]` marker on the row — **right-click the module** to
collapse open its settings drawer underneath (same builder API inside, e.g.
`s:addSlider(...)`); left-click still toggles the module. The handle also
exposes `h.settings` (the builder) and `h.setSettingsOpen(v)`.

The HAVOC HUB search box filters every category row live (case-insensitive
substring): matching panels stay open, groups open when a child matches,
empty categories shrink to their header, and clearing the box restores the
previous expand/open state.

Rows without keybinds: click toggles/expands. Sliders: drag to scrub;
**shift-click (or right-click) opens a type-in box** for an exact value
(`Enter` applies and snaps to the step, `Esc`/click-away cancels).

**Keybinds**: click a chip and press a keyboard key, a mouse button
(`M1`/`M2`/`M3`), or a combo (`Ctrl`/`Shift`/`Alt` + key). `Esc` or
`Backspace` while editing **unbinds** the key (`[-]`); clicking the chip
again aborts the edit untouched. `UI.init{ canBind }` can veto a key.

```lua
local hk = { Key = Enum.KeyCode.P, Enabled = true, Desc = "Auto Parry" }
hk.Active = state.parry  -- seed so the first press flips from the real state
UI.bind(hk, { mode = "toggle", onActive = function(active) state.parry = active; row.update() end })
-- modes: "toggle" (press flips hk.Active) / "hold" (active while held)
-- live fields: hk.Key (KeyCode or UserInputType), hk.Mods{ctrl,shift,alt},
--              hk.Enabled (false silences), hk.Mode, hk.Active
UI.unbind(hk)  -- stops dispatching
```

`attachInput()` connects the dispatcher automatically (games just call
`UI.bind`); `UI.dispatchBinding(input, isDown)` is exposed for manual
wiring. Bindings never fire while a rebind capture is active.

## Theme (live)

```lua
UI.setThemeColor("BG", Color3.fromRGB(10, 10, 12))  -- repaints the whole UI at once
UI.setThemeColor("GREEN", Color3.fromRGB(120, 255, 120))
UI.resetTheme()          -- back to stock
UI.DEFAULT_THEME         -- the stock palette (read-only source of truth)
```

Every GUI element painted with the previous token colour is repainted on
the spot (UIStroke borders included), so themes apply while the menu is
open. `HavocUI.init{ theme = {...} }` still works for pre-load overrides.

## Configs (save / load / list / delete)

```lua
local cfg = UI.makeConfig{ folder = "havoc-ui/configs" }

cfg:track("Reach", function() return state.reach end, function(v) state.reach = v end)
cfg:trackKeybind(hkEntry)      -- saves Key / Mods / Mode / Enabled
cfg:trackTheme()               -- saves any theme overrides

cfg:save("legit")              -- -> havoc-ui/configs/legit.lua
cfg:load("legit")              -- applies modules + keybinds + theme,
                               -- then UI.refreshAll() repaints every widget
cfg:list()      --> { "legit", "rage", ... }
cfg:exists("legit"), cfg:delete("legit"), cfg.path("legit")
```

Configs serialize booleans, numbers, strings, `Color3`, `EnumItem`s and
nested tables, so module values, multiselect states and colour pickers
round-trip losslessly. `UI.refreshAll()` and `UI.refreshKeybinds()` can
also be called manually after external state changes.

## Sandbox workflow

1. Deploy `havoc-ui.luau` + `demo.luau` (as `havoc-ui-demo.luau`) to the
   executor workspace (`%LOCALAPPDATA%\Volt\workspace`).
2. Join an empty place, then through the bridge:
   `loadstring(readfile('havoc-ui-demo.luau'), '@havoc-ui-demo')()`.
3. Iterate: edit -> deploy -> re-run. Screenshots drive the polish pass.

## Rules

- New widget or generic UI option belongs in `havoc-ui.luau`.
- Game-specific pieces (HUD, radar, config persistence) stay in the game.
- Run `scripts/check.ps1` before every commit.

