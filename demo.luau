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

local function defaultState()
    return {
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
        themePreset = "Minecraft",
        configName = "default",
        configSel = "",
        hudWatermark = true,
        hudArray = true,
        hudKeys = false,
    }
end
local state = defaultState()
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

local cfg = UI.makeConfig{ name = "demo", folder = "havoc-ui/configs" }

local hud = UI.makeHud(screenGui)
for name, key in pairs({
    ["Auto Parry"] = "autoParry", ["Aim Assist"] = "aim", ["Auto Clicker"] = "autoClicker",
    ["Box ESP"] = "box", ["Names"] = "names", ["Chams"] = "chams",
    ["Fly"] = "fly", ["Speed"] = "speed", ["Infinite Jump"] = "infJump",
    ["Fullbright"] = "fullbright", ["Noclip"] = "noclip", ["Bunny Hop"] = "bunnyhop",
}) do
    hud:addModule(name, function() return state[key] end)
end
hud:setWatermark(state.hudWatermark)
hud:setArrayList(state.hudArray)
hud:setKeybinds(state.hudKeys)

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
combat:addLabel("chip: click=rebind ESC=unbind right-click=hold/toggle")
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
    local d = defaultState()
    for k in pairs(state) do state[k] = nil end
    for k, v in pairs(d) do state[k] = v end
    pcall(delfile, cfg.path("__autosave"))
    UI.resetTheme()
    UI.refreshAll()
    toaster("states + theme reset", { kind = "warn" })
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

-- ============================================================
-- CONFIG TAB: live theme + config slots
-- ============================================================
local PRESETS = {
    ["Minecraft"] = {},
    ["Midnight"] = {
        BG = Color3.fromRGB(8, 10, 18), HEADER_BG = Color3.fromRGB(22, 26, 44),
        BORDER = Color3.fromRGB(44, 52, 88), ROW_HOVER = Color3.fromRGB(30, 36, 60),
        TRACK = Color3.fromRGB(24, 28, 48), FILL = Color3.fromRGB(40, 64, 120),
        FILL_HI = Color3.fromRGB(56, 88, 160), TEXT_DIM = Color3.fromRGB(130, 140, 170),
        GRAY = Color3.fromRGB(150, 160, 190),
    },
    ["Crimson"] = {
        BG = Color3.fromRGB(14, 8, 8), HEADER_BG = Color3.fromRGB(42, 22, 22),
        BORDER = Color3.fromRGB(90, 44, 44), ROW_HOVER = Color3.fromRGB(52, 28, 28),
        TRACK = Color3.fromRGB(40, 22, 22), FILL = Color3.fromRGB(110, 36, 36),
        FILL_HI = Color3.fromRGB(150, 52, 52), GREEN = Color3.fromRGB(255, 120, 120),
        GOLD = Color3.fromRGB(255, 200, 120),
    },
    ["Emerald"] = {
        BG = Color3.fromRGB(8, 14, 10), HEADER_BG = Color3.fromRGB(22, 42, 28),
        BORDER = Color3.fromRGB(44, 88, 56), ROW_HOVER = Color3.fromRGB(28, 52, 34),
        TRACK = Color3.fromRGB(22, 40, 28), FILL = Color3.fromRGB(36, 110, 60),
        FILL_HI = Color3.fromRGB(52, 150, 84), GREEN = Color3.fromRGB(85, 255, 140),
    },
    ["Amethyst"] = {
        BG = Color3.fromRGB(12, 8, 16), HEADER_BG = Color3.fromRGB(36, 24, 48),
        BORDER = Color3.fromRGB(76, 50, 100), ROW_HOVER = Color3.fromRGB(46, 30, 62),
        TRACK = Color3.fromRGB(36, 24, 48), FILL = Color3.fromRGB(96, 60, 140),
        FILL_HI = Color3.fromRGB(130, 84, 190), GREEN = Color3.fromRGB(190, 130, 255),
        AQUA = Color3.fromRGB(180, 160, 255),
    },
    ["Mono"] = {
        BG = Color3.fromRGB(12, 12, 12), HEADER_BG = Color3.fromRGB(34, 34, 34),
        BORDER = Color3.fromRGB(70, 70, 70), ROW_HOVER = Color3.fromRGB(44, 44, 44),
        TRACK = Color3.fromRGB(32, 32, 32), FILL = Color3.fromRGB(90, 90, 90),
        FILL_HI = Color3.fromRGB(120, 120, 120), GREEN = Color3.fromRGB(255, 255, 255),
        GOLD = Color3.fromRGB(200, 200, 200), AQUA = Color3.fromRGB(220, 220, 220),
    },
}

local themePickerRefs = {}
local function applyPreset(name)
    local p = PRESETS[name] or {}
    for token, def in pairs(UI.DEFAULT_THEME) do
        if typeof(def) == "Color3" then
            UI.setThemeColor(token, p[token] or def)
        end
    end
    for _, h in ipairs(themePickerRefs) do
        if h.update then h.update() end
    end
end

local cfgTab = gui.category("Config")
cfgTab:addSection("theme")
cfgTab:addDropdown("Preset", { "Minecraft", "Midnight", "Crimson", "Emerald", "Amethyst", "Mono" },
    function() return state.themePreset end,
    function(v)
        state.themePreset = v
        applyPreset(v)
        toaster("theme: " .. v, { kind = "info" })
    end)
local function themePicker(parent, label, token)
    local h = parent:addColor(label, function() return UI.THEME[token] end,
        function(c) UI.setThemeColor(token, c) end)
    themePickerRefs[#themePickerRefs + 1] = h
    return h
end
local colors1 = cfgTab:addGroup("Colors")
themePicker(colors1, "Panel BG", "BG")
themePicker(colors1, "Header BG", "HEADER_BG")
themePicker(colors1, "Border", "BORDER")
themePicker(colors1, "Accent ON", "GREEN")
themePicker(colors1, "Value Gold", "GOLD")
themePicker(colors1, "Alert Red", "RED")
local colors2 = cfgTab:addGroup("More Colors")
themePicker(colors2, "OFF Gray", "GRAY")
themePicker(colors2, "Info Aqua", "AQUA")
themePicker(colors2, "Slider Fill", "FILL")
themePicker(colors2, "Row Hover", "ROW_HOVER")
themePicker(colors2, "Dim Text", "TEXT_DIM")

cfgTab:addSection("hud")
cfgTab:addToggle("Watermark", function() return state.hudWatermark end,
    function(v) state.hudWatermark = v; hud:setWatermark(v) end)
cfgTab:addToggle("ArrayList", function() return state.hudArray end,
    function(v) state.hudArray = v; hud:setArrayList(v) end)
cfgTab:addToggle("Keybind List", function() return state.hudKeys end,
    function(v) state.hudKeys = v; hud:setKeybinds(v) end)
cfgTab:addSlider("UI Scale", 0.8, 1.4, function() return state.uiScale or gui.getScale() end,
    function(v)
        state.uiScale = v
        gui.setScale(v)
        gui.relayout()
    end, { step = 0.05, decimals = 2 })

cfgTab:addSection("configs")
cfgTab:addTextInput("Config Name", function() return state.configName end,
    function(v) state.configName = v end, { placeholder = "name..." })
cfgTab:addButton("Save Config", function()
    cfg:save(state.configName)
end)
cfgTab:addDropdown("Load Config", function()
    return cfg:list()
end, function()
    return state.configSel
end, function(v) state.configSel = v end)
cfgTab:addButton("Load Selected", function()
    if state.configSel == "" then
        toaster("pick a config from the list first", { kind = "warn" })
        return
    end
    cfg:load(state.configSel)
end)
cfgTab:addButton("Delete Selected", function()
    if state.configSel == "" then
        toaster("pick a config from the list first", { kind = "warn" })
        return
    end
    cfg:delete(state.configSel)
end, { style = "danger", confirm = true })

-- every module + keybind + the theme is part of a config
do
    local TRACK = {
        ["Auto Parry"] = "autoParry", ["Reach"] = "reach", ["Target Mode"] = "target",
        ["Auto Clicker"] = "autoClicker", ["Aim Assist"] = "aim",
        ["Target Name"] = "targetName", ["Prediction"] = "prediction", ["Silent Aim"] = "silentAim",
        ["Box ESP"] = "box", ["Names"] = "names", ["Chams"] = "chams",
        ["Box Color"] = "boxColor", ["Box Alpha"] = "boxAlpha", ["Chams Color"] = "chamsColor",
        ["Max Distance"] = "maxDist", ["Box Style"] = "boxStyle", ["ESP Parts"] = "parts",
        ["Fly"] = "fly", ["Fly Speed"] = "flySpeed", ["Fly Vertical"] = "flyVert",
        ["Speed"] = "speed", ["Speed Value"] = "speedValue", ["Infinite Jump"] = "infJump",
        ["Jump Power"] = "jumpPower", ["Walk Speed"] = "walkSpeed",
        ["Fullbright"] = "fullbright", ["Noclip"] = "noclip", ["Bunny Hop"] = "bunnyhop",
        ["Reach Window Lo"] = "reachLo", ["Reach Window Hi"] = "reachHi",
        ["Watermark"] = "hudWatermark", ["ArrayList"] = "hudArray",
        ["Keybind List"] = "hudKeys", ["UI Scale"] = "uiScale",
    }
    for id, key in pairs(TRACK) do
        cfg:track(id, function() return state[key] end, function(v) state[key] = v end)
    end
    for _, hk in ipairs({ hkParry, hkAim, hkSpeed, hkFly, hkChams }) do
        cfg:trackKeybind(hk)
    end
    cfg:trackTheme()
end

-- hud + scale follow every config load (and the autosave below)
UI.addRefresh(function()
    hud:setWatermark(state.hudWatermark)
    hud:setArrayList(state.hudArray)
    hud:setKeybinds(state.hudKeys)
    if state.uiScale then
        gui.setScale(state.uiScale)
        gui.relayout()
    end
end)

-- reload-in-place: bring back modules + keybinds + theme from the autosave
if cfg:exists("__autosave") then
    cfg:load("__autosave")
end
-- ...and put the panels back where the user left them
local savedPos = genv.__HAVOC_DEMO_POS
if savedPos then
    for _, p in ipairs(gui.panels) do
        local sp = savedPos[p.Name]
        if sp then p.Position = UDim2.fromOffset(sp.x, sp.y) end
    end
end

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
    ui = UI,
    state = state,
    cfg = cfg,
    hud = hud,
    keys = { parry = hkParry, aim = hkAim, speed = hkSpeed, fly = hkFly, chams = hkChams },
    destroy = function()
        -- remember everything so a reload is invisible: states, keybinds,
        -- theme (autosave config) and the panel layout (genv)
        pcall(function()
            local pos = {}
            for _, p in ipairs(gui.panels) do
                pos[p.Name] = { x = p.Position.X.Offset, y = p.Position.Y.Offset }
            end
            genv.__HAVOC_DEMO_POS = pos
        end)
        pcall(function() cfg:save("__autosave") end)
        pcall(function() hud:destroy() end)
        pcall(function() inputHandle.disconnect() end)
        for _, c in ipairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        pcall(function() gui.destroy() end)
        pcall(function() screenGui:Destroy() end)
        genv.__HAVOC_UI_DEMO = nil
    end,
}

toaster("Havoc UI " .. UI.VERSION .. " - config tab: theme + save/load slots", { kind = "ok" })
print("[havoc-ui] demo loaded " .. UI.VERSION)
