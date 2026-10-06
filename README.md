# havoc-ui

Frosted-glass Roblox GUI toolkit for the Havoc hubs (Oaklands / PD / Deadline).
Single-file drop-in: one `loadstring` + a parent `ScreenGui`.

**Status: v0.1-frost — sandbox iteration.** Design language:
translucent dark glass, 1px light borders, rounded corners, soft accent
glow, gentle motion (hover tweens, popup grow, toast slide).

## Layout

| file | purpose |
| --- | --- |
| `havoc-ui.luau` | the toolkit (single module, `readfile`-friendly) |
| `demo.luau` | sandbox showcase - builds every widget in one window |
| `scripts/check.ps1` | Luau compile gate (must stay 20/20-style clean) |

## Wiring

```lua
local HavocUI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

local toaster = HavocUI.makeToaster(screenGui)
HavocUI.init{ notify = toaster, saveDebounced = saveConfigDebounced }

local win = HavocUI.makeWindow{ parent = screenGui, title = "HAVOC HUB",
    tabs = { "General", "Visuals" } }
-- build widgets into win.tab(i), collect handles, then:
win.setControls(controls)              -- enables the search bar

track(HavocUI.attachInput())
-- top of your InputBegan handler:
if HavocUI.handleRebindInput(input) then return end
```

## Factories

`makeWindow`, `makeToaster` (returns the notify fn),
`makeSectionHeader`, `makeNote`, `makeToggle`, `makeSlider`, `makeButton`,
`makeInput`, `makeDropdown`, `makeMultiSelect`, `makeColorPicker`,
`makeKeybindRow`.

All widget factories return `{ row, update, searchText }` except
`makeSectionHeader` (no searchText) and `makeNote` (the TextLabel itself).

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
