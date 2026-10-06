-- havoc-ui sandbox demo: Minecraft-style cheat menu showcase.
-- Load via the bridge:  loadstring(readfile('havoc-ui-demo.luau'), '@havoc-ui-demo')()
-- Re-runnable: destroys the previous instance first.

local genv = getgenv()
if genv.__HAVOC_UI_DEMO then
    pcall(function() genv.__HAVOC_UI_DEMO.destroy() end)
    genv.__HAVOC_UI_DEMO = nil
end

local UI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HavocUIDemo"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 60
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local ok = pcall(function() screenGui.Parent = gethui() end)
if not ok then pcall(function() screenGui.Parent = game:GetService("CoreGui") end) end

local toaster = UI.makeToaster(screenGui)
UI.init{
    notify = toaster,
    save = function() end,
    saveDebounced = function() end,
}

local state = {
    autoParry = true,
    reach = 5,
    target = "Nearest",
    autoClicker = false,
    aim = false,
    reachLo = 8,
    reachHi = 16,
    targetName = "",
    silentAim = false,
    prediction = 0.15,
    box = true,
    names = true,
    chams = false,
    maxDist = 2000,
    boxStyle = "Full",
    parts = { Head = true, Body = true, Torso = false, Arms = false, Legs = false },
    boxColor = Color3.fromRGB(85, 255, 85),
    boxAlpha = 255,
    chamsColor = Color3.fromRGB(255, 85, 85),
    fly = false,
    flySpeed = 50,
    flyVert = 30,
    speed = false,
    speedValue = 46,
    infJump = false,
    jumpPower = 50,
    walkSpeed = 16,
    fullbright = false,
    noclip = false,
    bunnyhop = false,
}
local hkParry = { Key = Enum.KeyCode.P, Enabled = true, Desc = "Auto Parry" }
local hkFly = { Key = Enum.KeyCode.J, Enabled = true, Desc = "Fly" }
local hkChams = { Key = Enum.KeyCode.C, Enabled = true, Desc = "Chams" }
local hkAim = { Key = Enum.UserInputType.MouseButton2, Enabled = true, Desc = "Aim Assist", Mode = "hold" }
local hkSpeed = { Key = Enum.KeyCode.H, Mods = { ctrl = true }, Enabled = true, Desc = "Speed" }

local gui = UI.makeClickGui{
    parent = screenGui,
    width = 180,
    startX = 70,
    startY = 100,
}

local combat = gui.category("Combat")
local parryT = combat:addToggle("Auto Parry", function() return state.autoParry end,
    function(v) state.autoParry = v end, hkParry)
combat:addSlider("Reach", 1, 10, function() return state.reach end, function(v) state.reach = v end, { step = 0.1 })
combat:addDropdown("Target Mode", { "Nearest", "Crosshair", "Mouse" }, function() return state.target end, function(v)
    state.target = v
end)
combat:addToggle("Auto Clicker", function() return state.autoClicker end, function(v) state.autoClicker = v end)
local aimT = combat:addToggle("Aim Assist", function() return state.aim end,
    function(v) state.aim = v end, hkAim)
combat:addSection("timing")
combat:addProgress("Parry Cooldown", function() return (os.clock() % 3) / 3 end)
combat:addRangeSlider("Reach Window", 5, 40, function() return state.reachLo, state.reachHi end,
    function(a, b) state.reachLo, state.reachHi = a, b end, { step = 1 })
local combatAdv = combat:addGroup("Advanced")
combatAdv:addTextInput("Target Name", function() return state.targetName end,
    function(v) state.targetName = v end, { placeholder = "player..." })
combatAdv:addSlider("Prediction", 0, 1, function() return state.prediction end,
    function(v) state.prediction = v end, { step = 0.05 })
combatAdv:addToggle("Silent Aim", function() return state.silentAim end, function(v) state.silentAim = v end)
combat:addLabel("chips: key / mouse / Ctrl+Shift combos - ESC unbinds")
hkParry.Active = state.autoParry
UI.bind(hkParry, { mode = "toggle", onActive = function(a) state.autoParry = a; parryT.update() end })
UI.bind(hkAim, { mode = "hold", onActive = function(a) state.aim = a; aimT.update() end })

local visuals = gui.category("Visuals")
visuals:addToggle("Box ESP", function() return state.box end, function(v) state.box = v end)
visuals:addToggle("Names", function() return state.names end, function(v) state.names = v end)
visuals:addToggle("Chams", function() return state.chams end, function(v) state.chams = v end, hkChams)
visuals:addIndicator("ESP Engine", function() return state.box or state.names or state.chams end,
    { on = "running", off = "idle" })
visuals:addSeparator()
visuals:addColor("Box Color", function() return state.boxColor, state.boxAlpha end,
    function(c, a) state.boxColor = c; state.boxAlpha = a end, { alpha = true })
visuals:addColor("Chams Color", function() return state.chamsColor end, function(c) state.chamsColor = c end)
visuals:addSlider("Max Distance", 100, 5000, function() return state.maxDist end, function(v) state.maxDist = v end,
    { step = 50, suffix = "m" })
visuals:addDropdown("Box Style", { "Full", "Corner", "Square", "None" }, function() return state.boxStyle end, function(v)
    state.boxStyle = v
end)
visuals:addMultiSelect("Parts", { "Head", "Body", "Torso", "Arms", "Legs" },
    function(it) return state.parts[it] == true end,
    function(it, on) state.parts[it] = on end)

local player = gui.category("Player")
player:addToggle("Fly", function() return state.fly end, function(v) state.fly = v end, hkFly, {
    settings = function(s)
        s:addSlider("Fly Speed", 20, 200, function() return state.flySpeed end,
            function(v) state.flySpeed = v end, { step = 5 })
        s:addSlider("Vertical", 10, 100, function() return state.flyVert end,
            function(v) state.flyVert = v end, { step = 5 })
    end,
})
player:addKeybind(hkFly)
local speedT = player:addToggle("Speed", function() return state.speed end, function(v) state.speed = v end, hkSpeed, {
    settings = function(s)
        s:addSlider("Speed Value", 10, 100, function() return state.speedValue end,
            function(v) state.speedValue = v end, { step = 1 })
    end,
})
player:addToggle("Infinite Jump", function() return state.infJump end, function(v) state.infJump = v end, nil, {
    settings = function(s)
        s:addSlider("Jump Power", 30, 150, function() return state.jumpPower end,
            function(v) state.jumpPower = v end, { step = 5 })
    end,
})
player:addSlider("Walk Speed", 16, 200, function() return state.walkSpeed end, function(v) state.walkSpeed = v end,
    { step = 2 })
player:addLabel("right-click a module for its settings")
hkSpeed.Active = state.speed
UI.bind(hkSpeed, { mode = "toggle", onActive = function(a) state.speed = a; speedT.update() end })

local movement = gui.category("Movement", { collapsed = true })
movement:addToggle("Fullbright", function() return state.fullbright end, function(v) state.fullbright = v end)
movement:addToggle("Noclip", function() return state.noclip end, function(v) state.noclip = v end)
movement:addToggle("Bunny Hop", function() return state.bunnyhop end, function(v) state.bunnyhop = v end)

local misc = gui.category("Misc", { collapsed = true })
misc:addButton("Reset States", function()
    toaster("states reset", { kind = "warn" })
end, { confirm = true })
misc:addButton("Test Notification", function()
    toaster("Everything is wired and live", { kind = "ok" })
end)
misc:addButton("Reload UI", function()
    loadstring(readfile('havoc-ui-demo.luau'), '@havoc-ui-demo')()
end)
misc:addButton("Unload", function()
    if genv.__HAVOC_UI_DEMO then genv.__HAVOC_UI_DEMO.destroy() end
end, { style = "danger" })

local inputHandle = UI.attachInput()
local UIS = game:GetService("UserInputService")
local conns = {}
table.insert(conns, UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if UIS:GetFocusedTextBox() then return end
    if UI.handleRebindInput(input) then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        gui.toggle()
    end
end))

genv.__HAVOC_UI_DEMO = {
    gui = screenGui,
    win = gui,
    destroy = function()
        pcall(function() inputHandle.disconnect() end)
        for _, c in ipairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        pcall(function() gui.destroy() end)
        pcall(function() screenGui:Destroy() end)
        genv.__HAVOC_UI_DEMO = nil
    end,
}

toaster("Havoc UI " .. UI.VERSION .. " - hub has search, drag headers to move", { kind = "ok" })
print("[havoc-ui] demo loaded " .. UI.VERSION)
