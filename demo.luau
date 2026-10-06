-- havoc-ui sandbox demo: full widget showcase, built for an empty place.
-- Load via the bridge:  loadstring(readfile('havoc-ui-demo.luau'), '@havoc-ui-demo')()
-- Re-runnable: destroys the previous instance first.

local genv = getgenv()
if genv.__HAVOC_UI_DEMO then
    pcall(function() genv.__HAVOC_UI_DEMO.destroy() end)
    genv.__HAVOC_UI_DEMO = nil
end

local HavocUI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HavocUIDemo"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 60
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local ok = pcall(function() screenGui.Parent = gethui() end)
if not ok then pcall(function() screenGui.Parent = game:GetService("CoreGui") end) end

local toaster = HavocUI.makeToaster(screenGui)
HavocUI.init{
    notify = toaster,
    save = function() end,
    saveDebounced = function() end,
}

local state = {
    uiScale = 1,
    anims = true,
    compact = false,
    boxStyle = "Full",
    parts = { Head = true, Body = true, Torso = false, ["Left Arm"] = false, ["Right Arm"] = false, Legs = false },
    maxDist = 2000,
    boxColor = Color3.fromRGB(122, 162, 255),
    chamsColor = Color3.fromRGB(255, 108, 168),
    names = true,
    distance = true,
    health = false,
    targetMode = "Nearest",
    aimSpeed = 0.35,
    autoParry = false,
    customSpeed = 46,
}
local hkFly = { Key = Enum.KeyCode.J, Enabled = true, Desc = "Fly" }
local hkCam = { Key = Enum.KeyCode.LeftAlt, Enabled = true, Desc = "Freecam" }

local win = HavocUI.makeWindow{
    parent = screenGui,
    title = "HAVOC UI",
    subtitle = HavocUI.VERSION,
    position = UDim2.fromOffset(40, 60),
    size = UDim2.fromOffset(560, 640),
    tabs = { "General", "Visuals", "Player", "Misc" },
    footerHint = "RightShift - toggle menu",
    footerRight = "frosted glass preview",
}

local controls = {}
local function track(handle)
    table.insert(controls, handle)
    return handle
end
local pg, pv, pp, pm = win.tab(1), win.tab(2), win.tab(3), win.tab(4)

-- General
track(HavocUI.makeSectionHeader(pg, "Interface"))
track(HavocUI.makeToggle(pg, "UI Animations", function() return state.anims end, function(v) state.anims = v end))
track(HavocUI.makeToggle(pg, "Compact Rows", function() return state.compact end, function(v) state.compact = v end))
track(HavocUI.makeSlider(pg, "UI Scale", 0.8, 1.4, function() return state.uiScale end, function(v)
    state.uiScale = v
    win.setScale(v)
end, { step = 0.05, decimals = 2 }))
track(HavocUI.makeInput(pg, "Custom Speed", function() return state.customSpeed end, function(v)
    state.customSpeed = tonumber(v) or state.customSpeed
end, { numeric = true, width = 110 }))
track(HavocUI.makeSectionHeader(pg, "Notifications"))
track(HavocUI.makeButton(pg, "Toast: success", function()
    toaster("Config saved to havoc_db", { kind = "ok" })
end, { style = "primary" }))
track(HavocUI.makeButton(pg, "Toast: warning", function()
    toaster("Rock ESP cap reached (80 of 80)", { kind = "warn" })
end))
track(HavocUI.makeButton(pg, "Toast: error", function()
    toaster("Shield failed to install - retrying in 5s", { kind = "err" })
end, { style = "danger" }))

-- Visuals
track(HavocUI.makeSectionHeader(pv, "ESP Style"))
track(HavocUI.makeColorPicker(pv, "Box Color", function() return state.boxColor end, function(c)
    state.boxColor = c
end, { overlay = win.popupLayer }))
track(HavocUI.makeColorPicker(pv, "Chams Color", function() return state.chamsColor end, function(c)
    state.chamsColor = c
end, { overlay = win.popupLayer }))
track(HavocUI.makeDropdown(pv, "Box Style", { "None", "Full", "Corner", "Square" }, function()
    return state.boxStyle
end, function(v) state.boxStyle = v end, { overlay = win.popupLayer }))
track(HavocUI.makeMultiSelect(pv, "Parts to Highlight",
    { "Head", "Body", "Torso", "Left Arm", "Right Arm", "Legs" },
    function(it) return state.parts[it] == true end,
    function(it, on) state.parts[it] = on end,
    { overlay = win.popupLayer }))
track(HavocUI.makeSlider(pv, "Max Distance", 100, 5000, function() return state.maxDist end, function(v)
    state.maxDist = v
end, { step = 50, suffix = " studs" }))
track(HavocUI.makeToggle(pv, "Names", function() return state.names end, function(v) state.names = v end))
track(HavocUI.makeToggle(pv, "Distance", function() return state.distance end, function(v) state.distance = v end))
track(HavocUI.makeToggle(pv, "Health Bars", function() return state.health end, function(v) state.health = v end))
HavocUI.makeNote(pv, "Try the colour pickers - drag inside the square and the hue bar. Every control here is wired to live state.")

-- Player
track(HavocUI.makeSectionHeader(pp, "Aimbot"))
track(HavocUI.makeDropdown(pp, "Target Mode", { "Nearest", "Crosshair", "Mouse" }, function()
    return state.targetMode
end, function(v) state.targetMode = v end, { overlay = win.popupLayer }))
track(HavocUI.makeSlider(pp, "Aim Smoothness", 0.05, 1, function() return state.aimSpeed end, function(v)
    state.aimSpeed = v
end, { step = 0.05, decimals = 2 }))
track(HavocUI.makeSectionHeader(pp, "Movement"))
track(HavocUI.makeToggle(pp, "Fly", function() return hkFly.Enabled end, function(v) hkFly.Enabled = v end, hkFly))
track(HavocUI.makeKeybindRow(pp, hkFly))
track(HavocUI.makeKeybindRow(pp, hkCam, { locked = true, lockNote = "Freecam key is locked in this preview" }))
track(HavocUI.makeToggle(pp, "Auto Parry", function() return state.autoParry end, function(v) state.autoParry = v end))

-- Misc
track(HavocUI.makeSectionHeader(pm, "Danger Zone"))
track(HavocUI.makeButton(pm, "Reload UI", function()
    loadstring(readfile('havoc-ui-demo.luau'), '@havoc-ui-demo')()
end))
track(HavocUI.makeButton(pm, "Unload Havoc UI", function()
    if genv.__HAVOC_UI_DEMO then genv.__HAVOC_UI_DEMO.destroy() end
end, { style = "danger" }))
HavocUI.makeNote(pm, "havoc-ui " .. HavocUI.VERSION .. " - frosted glass toolkit. Sandbox build; iterate freely.")

win.setControls(controls)

local inputHandle = HavocUI.attachInput()
local conns = {}
table.insert(conns, game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if HavocUI.handleRebindInput(input) then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        win.toggle()
    end
end))

genv.__HAVOC_UI_DEMO = {
    gui = screenGui,
    win = win,
    destroy = function()
        pcall(function() inputHandle.disconnect() end)
        for _, c in ipairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        pcall(function() win.destroy() end)
        pcall(function() screenGui:Destroy() end)
        genv.__HAVOC_UI_DEMO = nil
    end,
}

toaster("Havoc UI sandbox loaded - " .. HavocUI.VERSION, { kind = "ok" })
print("[havoc-ui] demo loaded " .. HavocUI.VERSION)
