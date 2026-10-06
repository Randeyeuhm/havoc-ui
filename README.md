# havoc-ui

Minecraft-style cheat GUI toolkit for the Havoc hubs (Oaklands / PD / Deadline).
Single-file drop-in: one `loadstring` + a parent `ScreenGui`.

**Status: v0.2-block — sandbox iteration.** Design language: flat square
blocks, `[+]`/`[-]` collapsible category lists, tight rows, ON = #55FF55
green / OFF = #AAAAAA gray, inline `[x]` checkboxes and vanilla-style
sliders, chat-palette accents (gold #FFFF55, red #FF5555, aqua #55FFFF).

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

local gui = UI.makeClickGui{ parent = screenGui, title = "HAVOC HUB",
    position = UDim2.fromOffset(60, 90), footerHint = "RightShift - toggle" }
local combat = gui.category("Combat")
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

`makeClickGui{ parent, title, position, width, footerHint, maxListHeight,
onClose, scale }` -> `{ frame, titlebar, category(name, { collapsed }),
setScale, show, hide, toggle, isVisible, destroy }`.

Category rows (each returns `{ row, update }`, `addLabel` returns the
label): `addToggle(text, get, set, hkEntry?, opts)`,
`addSlider(text, min, max, get, set, opts)`,
`addDropdown(text, items, get, set)`,
`addMultiSelect(text, items, isOn, setOn)`,
`addColor(text, get, set)` (RGB slider trio),
`addKeybind(entry, opts)`, `addButton(text, fn, opts)`, `addLabel(text)`.

Rows without keybinds: click toggles/expands. Keybind chips: click, then
press a key (`Esc` cancels; `UI.init{ canBind }` can veto).

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

