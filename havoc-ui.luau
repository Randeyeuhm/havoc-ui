--[[
    Havoc UI - Minecraft-style cheat GUI toolkit (v0.2-block)

    Design language:
      - flat square blocks, 1px borders, tight rows (no rounding, no glass)
      - detached category panels: the collapsed header ([+] Combat) spawns
        its own list on click; every panel is draggable by its header
      - module rows click to toggle; ON = Minecraft green, OFF = gray
      - inline option lists: dropdowns, [x] checkboxes, vanilla-style sliders
      - chat-palette accents: #55FF55 green, #FFFF55 gold, #FF5555 red,
        #55FFFF aqua, #AAAAAA gray

    Wiring:
        local UI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

        local toaster = UI.makeToaster(screenGui)
        UI.init{
            notify           = toaster,
            saveDebounced    = saveConfigDebounced,
            onKeybindChanged = function(entry) end,
            canBind          = function(entry, key) return true end,
        }

        local gui = UI.makeClickGui{
            parent = screenGui, width = 180,
            startX = 60, startY = 80,
        }
        local combat = gui.category("Combat")   -- one detached panel each
        combat:addToggle("Auto Parry", getter, setter, hkEntry)
        combat:addSlider("Reach", 1, 10, getter, setter, { step = 0.1 })
        combat:addDropdown("Target", { "Nearest", "Crosshair" }, getter, setter)
        combat:addMultiSelect("Parts", items, isOn, setOn)
        combat:addColor("Box Color", getter, setter)
        combat:addKeybind(hkEntry)
        combat:addButton("Panic", fn)
        combat:addLabel("small dim note")

        track(UI.attachInput())
        -- top of your InputBegan handler:
        if UI.handleRebindInput(input) then return end

    Every add* returns { row, update } (addLabel returns the label).
]]

local UserInputService = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local HavocUI = {}
HavocUI.VERSION = "v0.5-search"

-- ============================================================
-- THEME / FONTS  (Minecraft chat palette)
-- ============================================================
local THEME = {
    BG         = Color3.fromRGB(16, 16, 16),   BG_T         = 0.06,
    TITLEBAR   = Color3.fromRGB(28, 28, 28),   TITLEBAR_T   = 0,
    BORDER     = Color3.fromRGB(60, 60, 60),
    HEADER_BG  = Color3.fromRGB(38, 38, 38),   HEADER_T     = 0.35,
    ROW_HOVER  = Color3.fromRGB(46, 46, 46),   ROW_HOVER_T  = 0.25,
    TRACK      = Color3.fromRGB(36, 36, 36),
    FILL       = Color3.fromRGB(58, 92, 58),
    FILL_HI    = Color3.fromRGB(72, 112, 72),
    BTN        = Color3.fromRGB(42, 42, 42),   BTN_T        = 0.2,
    TEXT       = Color3.fromRGB(224, 224, 224),
    TEXT_DIM   = Color3.fromRGB(150, 150, 150),
    GRAY       = Color3.fromRGB(170, 170, 170),
    GREEN      = Color3.fromRGB(85, 255, 85),
    GOLD       = Color3.fromRGB(255, 255, 85),
    RED        = Color3.fromRGB(255, 85, 85),
    AQUA       = Color3.fromRGB(85, 255, 255),
    WHITE      = Color3.fromRGB(255, 255, 255),
    SHADOW     = 0.6,   -- text stroke transparency (the "drop shadow")
}
HavocUI.THEME = THEME

local FONTS = {
    REGULAR = Enum.Font.Gotham,
    MEDIUM  = Enum.Font.GothamMedium,
    BOLD    = Enum.Font.GothamBold,
}
HavocUI.FONTS = FONTS

-- ============================================================
-- HOST HOOKS
-- ============================================================
local HOST = {
    notify = nil, save = nil, saveDebounced = nil,
    canBind = nil, onKeybindToggled = nil, onKeybindChanged = nil,
}

function HavocUI.init(opts)
    opts = opts or {}
    for k, v in pairs(opts) do
        if k == "theme" and type(v) == "table" then
            for tk, tv in pairs(v) do THEME[tk] = tv end
        elseif k == "fonts" and type(v) == "table" then
            for fk, fv in pairs(v) do FONTS[fk] = fv end
        else
            HOST[k] = v
        end
    end
end

local function saveTouched()
    if HOST.saveDebounced then pcall(HOST.saveDebounced) end
end

local function toast(text, opts)
    if HOST.notify then pcall(HOST.notify, text, opts) end
end

-- ============================================================
-- BUILD HELPERS
-- ============================================================
local function create(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do inst[k] = v end
    return inst
end

local function box(gui, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.BORDER
    s.Transparency = transparency or 0
    s.Thickness = 1
    s.Parent = gui
    return s
end

local function tween(gui, time, props, style, dir)
    local t = TweenService:Create(gui, TweenInfo.new(
        time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- shadowed text (the Minecraft look: 1px dark outline)
local function label(parent, str, size, color, props)
    local base = {
        BackgroundTransparency = 1,
        Text = str or "",
        TextColor3 = color or THEME.TEXT,
        TextSize = size or 12,
        Font = FONTS.MEDIUM,
        TextStrokeTransparency = THEME.SHADOW,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }
    for k, v in pairs(props or {}) do base[k] = v end
    return create("TextLabel", base)
end

-- ============================================================
-- INPUT PLUMBING (drags + keybind rebinding)
-- ============================================================
local drags = {}
local pendingRebind = nil

function HavocUI.startDrag(fn)
    table.insert(drags, fn)
    return fn
end

function HavocUI.endDrag(fn)
    for i = #drags, 1, -1 do
        if drags[i] == fn then table.remove(drags, i) end
    end
end

function HavocUI.attachInput()
    local conns = {}
    table.insert(conns, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local x, y = input.Position.X, input.Position.Y
        for i = #drags, 1, -1 do
            local ok = pcall(drags[i], x, y)
            if not ok then table.remove(drags, i) end
        end
    end))
    table.insert(conns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            table.clear(drags)
        end
    end))
    return {
        disconnect = function()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        end,
    }
end

function HavocUI.beginRebind(entry, chip)
    if not entry or not chip then return end
    pendingRebind = { entry = entry, chip = chip, restore = chip.Text }
    chip.Text = "[...]"
    chip.TextColor3 = THEME.GOLD
end

function HavocUI.handleRebindInput(input)
    if not pendingRebind then return false end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return false end
    local rb = pendingRebind
    if input.KeyCode == Enum.KeyCode.Escape then
        pendingRebind = nil
        rb.chip.Text = rb.restore
        rb.chip.TextColor3 = THEME.GRAY
        return true
    end
    if HOST.canBind and HOST.canBind(rb.entry, input.KeyCode) == false then
        return true
    end
    pendingRebind = nil
    rb.entry.Key = input.KeyCode
    rb.chip.Text = "[" .. input.KeyCode.Name .. "]"
    rb.chip.TextColor3 = THEME.GRAY
    if HOST.onKeybindChanged then
        pcall(HOST.onKeybindChanged, rb.entry)
    elseif HOST.onKeybindToggled then
        pcall(HOST.onKeybindToggled, rb.entry)
    end
    return true
end

-- ============================================================
-- TOASTER  (flat chat lines)
-- ============================================================
function HavocUI.makeToaster(parent)
    local holder = create("Frame", {
        Size = UDim2.new(0, 420, 0, 400),
        Position = UDim2.new(0.5, -210, 0, 8),
        BackgroundTransparency = 1,
        ZIndex = 300,
        Parent = parent,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Parent = holder,
    })
    local order = 0
    local KINDS = {
        info = THEME.AQUA,
        ok   = THEME.GREEN,
        warn = THEME.GOLD,
        err  = THEME.RED,
    }
    local function notify(text, opts)
        opts = opts or {}
        text = tostring(text or "")
        order = order + 1
        local line = create("Frame", {
            Size = UDim2.new(0, 380, 0, 20),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.35,
            LayoutOrder = order,
            ZIndex = 300,
            Parent = holder,
        })
        box(line, THEME.BORDER, 0.4)
        label(line, "[Havoc]", 12, KINDS[opts.kind or "info"] or THEME.AQUA, {
            Size = UDim2.new(0, 52, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            Font = FONTS.BOLD,
            ZIndex = 301,
            Parent = line,
        })
        label(line, text, 12, Color3.fromRGB(255, 255, 255), {
            Size = UDim2.new(1, -62, 1, 0),
            Position = UDim2.fromOffset(56, 0),
            ZIndex = 301,
            Parent = line,
        })
        task.delay(opts.duration or 3.0, function()
            if line.Parent then line:Destroy() end
        end)
        return line
    end
    return notify
end

-- ============================================================
-- CLICK GUI
-- ============================================================
function HavocUI.makeClickGui(opts)
    opts = opts or {}
    local W = { panels = {} }
    local width = opts.width or 180
    local gap = opts.gap or 10
    local layout = opts.layout or "row"
    local startX = opts.startX or 60
    local startY = opts.startY or 80
    local maxList = opts.maxListHeight or 480
    local parent = opts.parent
    local index = 0
    local panelRefs = {}

    -- UI scale (same rule as the hub menus: auto up to 1.2x on big displays)
    local scale = tonumber(opts.scale)
    if not scale then
        local vpY = 0
        local okS, psz = pcall(function() return parent and parent.AbsoluteSize end)
        if okS and psz then vpY = psz.Y end
        if vpY <= 0 then
            local okC, cam = pcall(function() return workspace.CurrentCamera end)
            if okC and cam then vpY = cam.ViewportSize.Y end
        end
        scale = math.clamp(vpY / 1150, 1, 1.2)
    end
    scale = math.clamp(scale, 0.5, 2)

    -- ========================================================
    -- ROW BUILDERS (used by categories)
    -- ========================================================
    local order = 0
    local function nextOrder()
        order = order + 1
        return order
    end

    local function makeRow(parent, height)
        local row = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height or 20),
            BackgroundColor3 = THEME.ROW_HOVER,
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        row.MouseEnter:Connect(function() tween(row, 0.1, { BackgroundTransparency = THEME.ROW_HOVER_T }) end)
        row.MouseLeave:Connect(function() tween(row, 0.1, { BackgroundTransparency = 1 }) end)
        return row
    end

    local function keyChip(parent, entry, opts2)
        opts2 = opts2 or {}
        local chip = create("TextButton", {
            Size = UDim2.fromOffset(38, 16),
            Position = UDim2.new(1, -4, 0.5, -8),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = THEME.TRACK,
            BackgroundTransparency = 0.25,
            Text = "[" .. ((entry and entry.Key and entry.Key.Name) or "-") .. "]",
            TextColor3 = THEME.GRAY,
            TextSize = 10,
            Font = FONTS.MEDIUM,
            TextStrokeTransparency = THEME.SHADOW,
            AutoButtonColor = false,
            ZIndex = 62,
            Parent = parent,
        })
        box(chip, THEME.BORDER, 0.5)
        chip.MouseEnter:Connect(function() tween(chip, 0.1, { BackgroundTransparency = 0 }) end)
        chip.MouseLeave:Connect(function() tween(chip, 0.1, { BackgroundTransparency = 0.25 }) end)
        chip.MouseButton1Click:Connect(function()
            if opts2.locked then
                if opts2.lockNote then toast(opts2.lockNote, { kind = "warn" }) end
                return
            end
            HavocUI.beginRebind(entry, chip)
        end)
        return chip
    end

    -- ---- add* factories (shared by every category) ----------
    local function addToggle(parent, text, getter, setter, hkEntry, opts2)
        opts2 = opts2 or {}
        local row = makeRow(parent, 20)
        local name = label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(1, hkEntry and 50 or 14, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local chip = nil
        if hkEntry then chip = keyChip(row, hkEntry, opts2) end
        local function refresh()
            local on = getter() and true or false
            name.TextColor3 = on and THEME.GREEN or THEME.GRAY
            if chip and hkEntry then
                chip.TextColor3 = hkEntry.Enabled and THEME.GRAY or Color3.fromRGB(90, 90, 90)
            end
        end
        row.MouseButton1Click:Connect(function()
            setter(not (getter() and true or false))
            refresh()
            saveTouched()
        end)
        refresh()
        return { row = row, update = refresh }
    end

    local function addSlider(parent, text, min, max, getter, setter, opts2)
        opts2 = opts2 or {}
        local step = opts2.step
        local decimals = opts2.decimals
        if decimals == nil then
            decimals = (step or ((max - min) / 100)) >= 1 and 0 or 1
        end
        local suffix = opts2.suffix or ""
        local row = makeRow(parent, 20)
        local fill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = THEME.FILL,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = row,
        })
        local name = label(row, text, 12, Color3.fromRGB(220, 220, 220), {
            Size = UDim2.new(0.6, -6, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.4, -6, 1, 0),
            Position = UDim2.new(0.6, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local function setFrac(frac, live)
            frac = math.clamp(frac, 0, 1)
            local v = min + frac * (max - min)
            if step then v = math.floor(v / step + 0.5) * step end
            v = math.clamp(v, min, max)
            tween(fill, live and 0.03 or 0.1, { Size = UDim2.new(frac, 0, 1, 0) })
            value.Text = string.format("%." .. tostring(decimals) .. "f", v) .. suffix
            return v
        end
        local function refresh()
            local v = math.clamp(tonumber(getter()) or min, min, max)
            setFrac((v - min) / math.max(max - min, 1e-9))
        end
        row.MouseEnter:Connect(function()
            tween(fill, 0.1, { BackgroundColor3 = THEME.FILL_HI })
        end)
        row.MouseLeave:Connect(function()
            tween(fill, 0.1, { BackgroundColor3 = THEME.FILL })
        end)
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local function apply(mx)
                local pos, size = row.AbsolutePosition, row.AbsoluteSize
                local v = setFrac((mx - pos.X) / math.max(size.X, 1), true)
                setter(v)
            end
            apply(input.Position.X)
            HavocUI.startDrag(function(mx)
                apply(mx)
            end)
        end)
        refresh()
        return { row = row, update = refresh }
    end

    local function addDropdown(parent, text, items, getter, setter, opts2)
        opts2 = opts2 or {}
        local expanded = false
        local row = makeRow(parent, 20)
        label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(0.55, -6, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.35, -4, 1, 0),
            Position = UDim2.new(0.55, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local marker = label(row, "[+]", 12, THEME.TEXT_DIM, {
            Size = UDim2.fromOffset(22, 20),
            Position = UDim2.new(1, -22, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 62,
            Parent = row,
        })
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.55,
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        local holderLayout = create("UIListLayout", {
            Padding = UDim.new(0, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder,
        })
        local optionRows = {}
        local update
        local function rebuildOptions()
            for _, r in ipairs(optionRows) do r:Destroy() end
            optionRows = {}
            local listItems = type(items) == "function" and items() or items
            local current = tostring(getter())
            for i, item in ipairs(listItems) do
                local orow = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundColor3 = THEME.ROW_HOVER,
                    BackgroundTransparency = 1,
                    Text = "",
                    AutoButtonColor = false,
                    LayoutOrder = i,
                    ZIndex = 61,
                    Parent = holder,
                })
                label(orow, tostring(item), 11, tostring(item) == current and THEME.GREEN or THEME.TEXT_DIM, {
                    Size = UDim2.new(1, -18, 1, 0),
                    Position = UDim2.fromOffset(14, 0),
                    ZIndex = 62,
                    Parent = orow,
                })
                orow.MouseEnter:Connect(function() tween(orow, 0.1, { BackgroundTransparency = THEME.ROW_HOVER_T }) end)
                orow.MouseLeave:Connect(function() tween(orow, 0.1, { BackgroundTransparency = 1 }) end)
                orow.MouseButton1Click:Connect(function()
                    setter(item)
                    update()
                    expanded = false
                    holder.Visible = false
                    marker.Text = "[+]"
                    saveTouched()
                end)
                optionRows[#optionRows + 1] = orow
            end
        end
        update = function()
            local cur = getter()
            value.Text = tostring(cur == nil and "-" or cur)
            if expanded then rebuildOptions() end
        end
        row.MouseButton1Click:Connect(function()
            expanded = not expanded
            holder.Visible = expanded
            marker.Text = expanded and "[-]" or "[+]"
            if expanded then rebuildOptions() end
        end)
        update()
        return { row = row, update = update }
    end

    local function addMultiSelect(parent, text, items, isOn, setOn, opts2)
        opts2 = opts2 or {}
        local expanded = false
        local row = makeRow(parent, 20)
        label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(0.6, -6, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.3, -4, 1, 0),
            Position = UDim2.new(0.6, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local marker = label(row, "[+]", 12, THEME.TEXT_DIM, {
            Size = UDim2.fromOffset(22, 20),
            Position = UDim2.new(1, -22, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 62,
            Parent = row,
        })
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.55,
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        create("UIListLayout", {
            Padding = UDim.new(0, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder,
        })
        local optionRows = {}
        local update
        local function rebuildOptions()
            for _, r in ipairs(optionRows) do r:Destroy() end
            optionRows = {}
            local listItems = type(items) == "function" and items() or items
            for i, item in ipairs(listItems) do
                local on = isOn(item) and true or false
                local orow = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundColor3 = THEME.ROW_HOVER,
                    BackgroundTransparency = 1,
                    Text = "",
                    AutoButtonColor = false,
                    LayoutOrder = i,
                    ZIndex = 61,
                    Parent = holder,
                })
                label(orow, on and "[x]" or "[ ]", 11, on and THEME.GREEN or THEME.TEXT_DIM, {
                    Size = UDim2.fromOffset(24, 18),
                    Position = UDim2.fromOffset(10, 0),
                    ZIndex = 62,
                    Parent = orow,
                })
                label(orow, tostring(item), 11, on and THEME.WHITE or THEME.TEXT_DIM, {
                    Size = UDim2.new(1, -40, 1, 0),
                    Position = UDim2.fromOffset(34, 0),
                    ZIndex = 62,
                    Parent = orow,
                })
                orow.MouseEnter:Connect(function() tween(orow, 0.1, { BackgroundTransparency = THEME.ROW_HOVER_T }) end)
                orow.MouseLeave:Connect(function() tween(orow, 0.1, { BackgroundTransparency = 1 }) end)
                orow.MouseButton1Click:Connect(function()
                    setOn(item, not (isOn(item) and true or false))
                    rebuildOptions()
                    update()
                    saveTouched()
                end)
                optionRows[#optionRows + 1] = orow
            end
        end
        update = function()
            local listItems = type(items) == "function" and items() or items
            local n = 0
            for _, it in ipairs(listItems) do
                if isOn(it) then n = n + 1 end
            end
            value.Text = n .. "/" .. #listItems
            if expanded then rebuildOptions() end
        end
        row.MouseButton1Click:Connect(function()
            expanded = not expanded
            holder.Visible = expanded
            marker.Text = expanded and "[-]" or "[+]"
            if expanded then rebuildOptions() end
        end)
        update()
        return { row = row, update = update }
    end

    local function addColor(parent, text, getter, setter, opts2)
        opts2 = opts2 or {}
        local expanded = false
        local row = makeRow(parent, 20)
        local swatch = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.new(0, 6, 0.5, -5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = row,
        })
        box(swatch, Color3.fromRGB(0, 0, 0), 0.3)
        label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(0.6, -26, 1, 0),
            Position = UDim2.fromOffset(22, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.3, -4, 1, 0),
            Position = UDim2.new(0.6, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local marker = label(row, "[+]", 12, THEME.TEXT_DIM, {
            Size = UDim2.fromOffset(22, 20),
            Position = UDim2.new(1, -22, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 62,
            Parent = row,
        })
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.55,
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        create("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
        local channels = opts2.alpha and { "R", "G", "B", "A" } or { "R", "G", "B" }
        local comps = { 255, 255, 255, 255 }
        local channelRows = {}
        local function applyChannel()
            local c = Color3.fromRGB(comps[1], comps[2], comps[3])
            if opts2.alpha then
                setter(c, comps[4])
            else
                setter(c)
            end
            swatch.BackgroundColor3 = c
            swatch.BackgroundTransparency = opts2.alpha and (1 - comps[4] / 255) or 0
            value.Text = string.format("#%02X%02X%02X",
                math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
            saveTouched()
        end
        for ci, ch in ipairs(channels) do
            local crow = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundColor3 = THEME.ROW_HOVER,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = ci,
                ZIndex = 61,
                Parent = holder,
            })
            local cfill = create("Frame", {
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = THEME.FILL,
                BorderSizePixel = 0,
                ZIndex = 61,
                Parent = crow,
            })
            label(crow, ch, 10, THEME.TEXT_DIM, {
                Size = UDim2.fromOffset(20, 16),
                Position = UDim2.fromOffset(10, 0),
                ZIndex = 62,
                Parent = crow,
            })
            local cval = label(crow, "255", 10, THEME.GOLD, {
                Size = UDim2.new(0, 30, 1, 0),
                Position = UDim2.new(1, -34, 0, 0),
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 62,
                Parent = crow,
            })
            local function setChannel(frac, live)
                comps[ci] = math.clamp(math.floor(frac * 255 + 0.5), 0, 255)
                tween(cfill, live and 0.03 or 0.1, { Size = UDim2.new(comps[ci] / 255, 0, 1, 0) })
                cval.Text = tostring(comps[ci])
                applyChannel()
            end
            crow.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                local function chapply(mx)
                    local pos, size = crow.AbsolutePosition, crow.AbsoluteSize
                    setChannel((mx - pos.X) / math.max(size.X, 1), true)
                end
                chapply(input.Position.X)
                HavocUI.startDrag(function(mx)
                    chapply(mx)
                end)
            end)
            channelRows[#channelRows + 1] = { set = setChannel, fill = cfill, val = cval }
        end
        local function update()
            local c, a = getter()
            if typeof(c) ~= "Color3" then c = Color3.new(1, 1, 1) end
            comps = {
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5),
                math.clamp(math.floor((tonumber(a) or 255) + 0.5), 0, 255),
            }
            swatch.BackgroundColor3 = c
            swatch.BackgroundTransparency = opts2.alpha and (1 - comps[4] / 255) or 0
            value.Text = string.format("#%02X%02X%02X", comps[1], comps[2], comps[3])
            for i, ref in ipairs(channelRows) do
                ref.fill.Size = UDim2.new(comps[i] / 255, 0, 1, 0)
                ref.val.Text = tostring(comps[i])
            end
        end
        row.MouseButton1Click:Connect(function()
            expanded = not expanded
            holder.Visible = expanded
            marker.Text = expanded and "[-]" or "[+]"
            if expanded then update() end
        end)
        update()
        return { row = row, update = update }
    end

    local function addKeybind(parent, entry, opts2)
        opts2 = opts2 or {}
        local row = makeRow(parent, 20)
        label(row, (entry and entry.Desc) or "Keybind", 12, THEME.GRAY, {
            Size = UDim2.new(1, -50, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local chip = keyChip(row, entry, opts2)
        local function refresh()
            chip.Text = "[" .. ((entry and entry.Key and entry.Key.Name) or "-") .. "]"
            chip.TextColor3 = (entry and entry.Enabled ~= false) and THEME.GRAY or Color3.fromRGB(90, 90, 90)
        end
        refresh()
        return { row = row, update = refresh }
    end

    local function addButton(parent, text, fn, opts2)
        opts2 = opts2 or {}
        local danger = opts2.style == "danger"
        local row = makeRow(parent, 20)
        local txt = label(row, text, 12, danger and THEME.RED or Color3.fromRGB(210, 210, 210), {
            Size = UDim2.new(1, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 62,
            Parent = row,
        })
        row.BackgroundColor3 = THEME.BTN
        row.BackgroundTransparency = THEME.BTN_T
        row.MouseEnter:Connect(function()
            txt.TextColor3 = danger and THEME.RED or THEME.GREEN
        end)
        row.MouseLeave:Connect(function()
            txt.TextColor3 = danger and THEME.RED or Color3.fromRGB(210, 210, 210)
        end)
        local armed = false
        local armToken = 0
        local function setVisual(a)
            if a then
                txt.Text = "sure?"
                txt.TextColor3 = THEME.WHITE
                row.BackgroundColor3 = THEME.RED
                row.BackgroundTransparency = 0.3
            else
                txt.Text = text
                txt.TextColor3 = danger and THEME.RED or Color3.fromRGB(210, 210, 210)
                row.BackgroundColor3 = THEME.BTN
                row.BackgroundTransparency = THEME.BTN_T
            end
        end
        row.MouseButton1Click:Connect(function()
            if opts2.confirm and not armed then
                armed = true
                armToken = armToken + 1
                local tok = armToken
                setVisual(true)
                task.delay(opts2.confirmTime or 2, function()
                    if armed and armToken == tok then
                        armed = false
                        setVisual(false)
                    end
                end)
                return
            end
            if armed then
                armed = false
                armToken = armToken + 1
            end
            setVisual(false)
            if fn then pcall(fn) end
        end)
        return { row = row, update = function() end }
    end

    local function addLabel(parent, text)
        local l = label(parent, text, 10, Color3.fromRGB(140, 140, 140), {
            Size = UDim2.new(1, -8, 0, 14),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.fromOffset(6, 0),
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = nextOrder(),
            ZIndex = 62,
            Parent = parent,
        })
        return l
    end

    -- ---- shared ticker: read-only widgets repaint themselves ----
    local tickers = {}
    local tickerConn = nil
    local tickerLast = 0
    local function registerTick(fn)
        tickers[#tickers + 1] = fn
        if not tickerConn then
            tickerConn = game:GetService("RunService").Heartbeat:Connect(function()
                local now = os.clock()
                if now - tickerLast < 0.05 then return end
                tickerLast = now
                for i = #tickers, 1, -1 do
                    local ok = pcall(tickers[i])
                    if not ok then table.remove(tickers, i) end
                end
            end)
        end
    end

    local function addSeparator(parent)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 8),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        create("Frame", {
            Size = UDim2.new(1, -8, 0, 1),
            Position = UDim2.new(0, 4, 0.5, 0),
            BackgroundColor3 = THEME.BORDER,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = row,
        })
        return { row = row, update = function() end }
    end

    local function addSection(parent, text)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        label(row, text, 11, THEME.GOLD, {
            Size = UDim2.new(1, -8, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            Font = FONTS.BOLD,
            ZIndex = 62,
            Parent = row,
        })
        return { row = row, update = function() end }
    end

    local function addProgress(parent, text, getter, opts2)
        opts2 = opts2 or {}
        local fmt = opts2.format or function(frac)
            return string.format("%d%%", math.floor(frac * 100 + 0.5))
        end
        local row = makeRow(parent, 22)
        label(row, text, 12, Color3.fromRGB(220, 220, 220), {
            Size = UDim2.new(0.6, -6, 0, 14),
            Position = UDim2.fromOffset(6, 2),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.4, -6, 0, 14),
            Position = UDim2.new(0.6, 0, 0, 2),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local track = create("Frame", {
            Size = UDim2.new(1, -12, 0, 4),
            Position = UDim2.new(0, 6, 1, -8),
            BackgroundColor3 = THEME.TRACK,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = row,
        })
        local fill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = opts2.color or THEME.FILL,
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = track,
        })
        local lastText
        local function apply()
            local frac = math.clamp(tonumber(getter()) or 0, 0, 1)
            fill.Size = UDim2.new(frac, 0, 1, 0)
            local t = fmt(frac)
            if t ~= lastText then
                value.Text = t
                lastText = t
            end
        end
        registerTick(apply)
        apply()
        return { row = row, update = apply }
    end

    local function addIndicator(parent, text, getter, opts2)
        opts2 = opts2 or {}
        local row = makeRow(parent, 20)
        label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(0.5, -6, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.AQUA, {
            Size = UDim2.new(0.5, -10, 1, 0),
            Position = UDim2.new(0.5, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local lastText, lastCol
        local function apply()
            local v = getter()
            local txt, col
            if type(v) == "boolean" then
                txt = v and (opts2.on or "ON") or (opts2.off or "OFF")
                col = v and THEME.GREEN or THEME.TEXT_DIM
            else
                txt = tostring(v == nil and "-" or v)
                col = opts2.color or THEME.AQUA
            end
            if txt ~= lastText or col ~= lastCol then
                value.Text = txt
                value.TextColor3 = col
                lastText, lastCol = txt, col
            end
        end
        registerTick(apply)
        apply()
        return { row = row, update = apply }
    end

    local function addTextInput(parent, text, getter, setter, opts2)
        opts2 = opts2 or {}
        local row = makeRow(parent, 20)
        label(row, text, 12, THEME.GRAY, {
            Size = UDim2.new(0.4, -6, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local input = create("TextBox", {
            Size = UDim2.new(0.6, -4, 0, 16),
            Position = UDim2.new(0.4, 0, 0, 2),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.4,
            Text = "",
            PlaceholderText = opts2.placeholder or "...",
            PlaceholderColor3 = THEME.TEXT_DIM,
            TextColor3 = THEME.WHITE,
            TextSize = 11,
            Font = FONTS.MEDIUM,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            ZIndex = 62,
            Parent = row,
        })
        box(input, THEME.BORDER, 0.4)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 4)
        pad.Parent = input
        local function refresh()
            if not input:IsFocused() then
                input.Text = tostring(getter() or "")
            end
        end
        input.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                input:ReleaseFocus()
            end
            setter(input.Text)
            saveTouched()
            refresh()
        end)
        refresh()
        return { row = row, update = refresh }
    end

    local function addStepper(parent, text, minVal, maxVal, step, getter, setter, opts2)
        opts2 = opts2 or {}
        step = tonumber(step) or 1
        local decimals = opts2.decimals
        if decimals == nil then decimals = step >= 1 and 0 or 1 end
        local row = makeRow(parent, 20)
        label(row, text, 12, Color3.fromRGB(220, 220, 220), {
            Size = UDim2.new(1, -112, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0, 34, 1, 0),
            Position = UDim2.new(1, -72, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local function mkBtn(sym, x)
            local b = create("TextButton", {
                Size = UDim2.fromOffset(16, 14),
                Position = UDim2.new(1, x, 0, 3),
                BackgroundColor3 = THEME.BTN,
                BackgroundTransparency = THEME.BTN_T,
                Text = sym,
                TextColor3 = Color3.fromRGB(210, 210, 210),
                TextSize = 12,
                Font = FONTS.BOLD,
                TextStrokeTransparency = THEME.SHADOW,
                AutoButtonColor = false,
                ZIndex = 62,
                Parent = row,
            })
            box(b, THEME.BORDER, 0.4)
            b.MouseEnter:Connect(function() b.TextColor3 = THEME.GREEN end)
            b.MouseLeave:Connect(function() b.TextColor3 = Color3.fromRGB(210, 210, 210) end)
            return b
        end
        local refresh
        local function nudge(dir)
            local cur = tonumber(getter()) or minVal
            local nv = math.clamp(cur + dir * step, minVal, maxVal)
            nv = minVal + math.floor((nv - minVal) / step + 0.5) * step
            nv = math.clamp(nv, minVal, maxVal)
            setter(nv)
            refresh()
            saveTouched()
        end
        mkBtn("-", -38).MouseButton1Click:Connect(function() nudge(-1) end)
        mkBtn("+", -20).MouseButton1Click:Connect(function() nudge(1) end)
        refresh = function()
            value.Text = string.format("%." .. tostring(decimals) .. "f", tonumber(getter()) or minVal)
        end
        refresh()
        return { row = row, update = refresh }
    end

    local function addRangeSlider(parent, text, minVal, maxVal, getter, setter, opts2)
        opts2 = opts2 or {}
        local step = tonumber(opts2.step) or ((maxVal - minVal) / 100)
        local decimals = opts2.decimals
        if decimals == nil then decimals = step >= 1 and 0 or 1 end
        local row = makeRow(parent, 24)
        label(row, text, 12, Color3.fromRGB(220, 220, 220), {
            Size = UDim2.new(0.5, -6, 0, 14),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local value = label(row, "", 12, THEME.GOLD, {
            Size = UDim2.new(0.5, -6, 0, 14),
            Position = UDim2.new(0.5, 0, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 62,
            Parent = row,
        })
        local bar = create("Frame", {
            Size = UDim2.new(1, -12, 0, 8),
            Position = UDim2.new(0, 6, 0, 15),
            BackgroundColor3 = THEME.TRACK,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = row,
        })
        box(bar, THEME.BORDER, 0.5)
        local fill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = THEME.FILL,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = bar,
        })
        local capLo = create("Frame", {
            Size = UDim2.fromOffset(2, 10),
            BackgroundColor3 = THEME.GREEN,
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = bar,
        })
        local capHi = create("Frame", {
            Size = UDim2.fromOffset(2, 10),
            BackgroundColor3 = THEME.GREEN,
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = bar,
        })
        local lo, hi = minVal, maxVal
        local function snap(v)
            return math.clamp(minVal + math.floor((v - minVal) / step + 0.5) * step, minVal, maxVal)
        end
        local function paint()
            local span = math.max(maxVal - minVal, 1e-9)
            local f1, f2 = (lo - minVal) / span, (hi - minVal) / span
            fill.Position = UDim2.new(f1, 0, 0, 0)
            fill.Size = UDim2.new(math.max(f2 - f1, 0), 0, 1, 0)
            capLo.Position = UDim2.new(f1, -1, 0.5, -5)
            capHi.Position = UDim2.new(f2, -1, 0.5, -5)
            value.Text = string.format("%." .. tostring(decimals) .. "f", lo) ..
                " - " .. string.format("%." .. tostring(decimals) .. "f", hi)
        end
        local function refresh()
            local a, b = getter()
            lo, hi = snap(tonumber(a) or minVal), snap(tonumber(b) or maxVal)
            if lo > hi then lo, hi = hi, lo end
            paint()
        end
        bar.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local which = 0
            local function apply(mx)
                local pos, size = bar.AbsolutePosition, bar.AbsoluteSize
                local frac = math.clamp((mx - pos.X) / math.max(size.X, 1), 0, 1)
                local v = snap(minVal + frac * (maxVal - minVal))
                if which == 0 then
                    which = (math.abs(v - lo) <= math.abs(v - hi)) and 1 or 2
                end
                if which == 1 then
                    lo = math.min(v, hi)
                else
                    hi = math.max(v, lo)
                end
                paint()
                setter(lo, hi)
            end
            apply(input.Position.X)
            HavocUI.startDrag(function(mx) apply(mx) end)
        end)
        refresh()
        return { row = row, update = refresh }
    end

    -- ---- search registry --------------------------------------
    local searchCats = {}
    local function registerEntry(cat, entryName, rowObj, group)
        local e = { row = rowObj, name = string.lower(tostring(entryName or "")), group = group }
        cat.entries[#cat.entries + 1] = e
        if group then group.entries[#group.entries + 1] = e end
    end

    local addGroup -- forward declaration (groups use the builders, builders expose groups)

    local function makeBuilders(cat, target, group)
        local b = {}
        b.addToggle = function(_, t, g, s, hk, o)
            local h = addToggle(target, t, g, s, hk, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addSlider = function(_, t, mn, mx, g, s, o)
            local h = addSlider(target, t, mn, mx, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addDropdown = function(_, t, it, g, s, o)
            local h = addDropdown(target, t, it, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addMultiSelect = function(_, t, it, g, s, o)
            local h = addMultiSelect(target, t, it, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addColor = function(_, t, g, s, o)
            local h = addColor(target, t, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addKeybind = function(_, e, o)
            local h = addKeybind(target, e, o)
            registerEntry(cat, (o and o.name) or (e and e.Desc) or "keybind", h.row, group)
            return h
        end
        b.addButton = function(_, t, f, o)
            local h = addButton(target, t, f, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addLabel = function(_, t)
            local h = addLabel(target, t)
            registerEntry(cat, t, h, group)
            return h
        end
        b.addSeparator = function()
            local h = addSeparator(target)
            registerEntry(cat, "", h.row, group)
            return h
        end
        b.addSection = function(_, t)
            local h = addSection(target, t)
            registerEntry(cat, "", h.row, group)
            return h
        end
        b.addProgress = function(_, t, g, o)
            local h = addProgress(target, t, g, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addIndicator = function(_, t, g, o)
            local h = addIndicator(target, t, g, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addTextInput = function(_, t, g, s, o)
            local h = addTextInput(target, t, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addStepper = function(_, t, mn, mx, st, g, s, o)
            local h = addStepper(target, t, mn, mx, st, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        b.addRangeSlider = function(_, t, mn, mx, g, s, o)
            local h = addRangeSlider(target, t, mn, mx, g, s, o)
            registerEntry(cat, t, h.row, group)
            return h
        end
        if not group then
            b.addGroup = function(_, t, o) return addGroup(cat, target, t, o) end
        end
        return b
    end

    addGroup = function(cat, parent, text, opts2)
        opts2 = opts2 or {}
        local grp = { name = text, nameLower = string.lower(text), entries = {}, open = false }
        local container = create("Frame", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = parent,
        })
        grp.container = container
        create("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = container })
        local header = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundColor3 = THEME.ROW_HOVER,
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = 0,
            ZIndex = 61,
            Parent = container,
        })
        local htxt = label(header, "", 12, THEME.GOLD, {
            Size = UDim2.new(1, -10, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            Font = FONTS.MEDIUM,
            ZIndex = 62,
            Parent = header,
        })
        local inner = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            LayoutOrder = 1,
            ZIndex = 61,
            Parent = container,
        })
        create("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
        create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = inner })
        local function setOpen(v)
            grp.open = v and true or false
            inner.Visible = grp.open
            htxt.Text = (grp.open and "[-] " or "[+] ") .. tostring(text)
        end
        grp.setOpen = setOpen
        grp.getOpen = function() return grp.open end
        header.MouseEnter:Connect(function() tween(header, 0.1, { BackgroundTransparency = THEME.ROW_HOVER_T }) end)
        header.MouseLeave:Connect(function() tween(header, 0.1, { BackgroundTransparency = 1 }) end)
        header.MouseButton1Click:Connect(function() setOpen(not grp.open) end)
        setOpen(opts2.open)
        cat.entries[#cat.entries + 1] = { row = container, name = grp.nameLower, grp = grp }
        cat.groups[#cat.groups + 1] = grp
        local builder = makeBuilders(cat, inner, grp)
        builder.setOpen = setOpen
        builder.isOpen = grp.getOpen
        return builder
    end


    -- ========================================================
    -- PANEL FACTORY (main hub + every category)
    -- ========================================================
    local function slotPosition(slot)
        if layout == "column" then
            return startX, startY + slot * 24
        end
        return startX + slot * (width + gap), startY
    end

    local function spawnPanel(name, opts2, slot)
        opts2 = opts2 or {}
        local px, py = slotPosition(slot)
        local panel = create("Frame", {
            Name = "HavocCat_" .. name,
            Size = UDim2.fromOffset(width, 22),
            Position = UDim2.fromOffset(px, py),
            BackgroundColor3 = THEME.BG,
            BackgroundTransparency = THEME.BG_T,
            BorderSizePixel = 0,
            ZIndex = opts.zindex or 60,
            Parent = parent,
        })
        box(panel, THEME.BORDER, 0)
        local panelScale = Instance.new("UIScale")
        panelScale.Scale = scale
        panelScale.Parent = panel
        panelRefs[#panelRefs + 1] = { panel = panel, uiScale = panelScale }
        W.panels[#W.panels + 1] = panel

        local header = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = THEME.HEADER_BG,
            BackgroundTransparency = THEME.HEADER_T,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 61,
            Parent = panel,
        })
        local headerText = label(header, (opts2.collapsed and "[+] " or "[-] ") .. name, 13, THEME.WHITE, {
            Size = UDim2.new(1, -10, 1, 0),
            Position = UDim2.fromOffset(6, 0),
            Font = FONTS.BOLD,
            ZIndex = 62,
            Parent = header,
        })
        local items = create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.fromOffset(0, 22),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
            ScrollBarImageTransparency = 0.2,
            Visible = not opts2.collapsed,
            ZIndex = 61,
            Parent = panel,
        })
        local itemsLayout = create("UIListLayout", {
            Padding = UDim.new(0, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = items,
        })
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2),
            Parent = items,
        })

        local expanded = not opts2.collapsed
        local function updatePanel()
            local contentH = itemsLayout.AbsoluteContentSize.Y
            local visH = expanded and math.min(contentH, maxList) or 0
            panel.Size = UDim2.fromOffset(width, 22 + visH)
            items.Size = UDim2.new(1, 0, 0, visH)
            items.CanvasSize = UDim2.new(0, 0, 0, contentH)
        end
        itemsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updatePanel)

        header.MouseEnter:Connect(function() tween(header, 0.1, { BackgroundTransparency = 0.1 }) end)
        header.MouseLeave:Connect(function() tween(header, 0.1, { BackgroundTransparency = THEME.HEADER_T }) end)

        local function setExpanded(v)
            expanded = v and true or false
            items.Visible = expanded
            headerText.Text = (expanded and "[-] " or "[+] ") .. name
            updatePanel()
        end

        -- drag by the header; a real drag must not fire the expand toggle
        local pressX, pressY, moved = 0, 0, false
        header.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            pressX, pressY, moved = input.Position.X, input.Position.Y, false
            local ox, oy = panel.Position.X.Offset, panel.Position.Y.Offset
            HavocUI.startDrag(function(mx, my)
                if math.abs(mx - pressX) + math.abs(my - pressY) > 4 then
                    moved = true
                end
                panel.Position = UDim2.fromOffset(
                    math.floor(ox + (mx - pressX)), math.floor(oy + (my - pressY)))
            end)
        end)
        header.MouseButton1Click:Connect(function()
            if moved then
                moved = false
                return
            end
            setExpanded(not expanded)
        end)

        updatePanel()
        return {
            panel = panel, header = header, items = items,
            setExpanded = setExpanded,
            isExpanded = function() return expanded end,
        }
    end

    -- the little main hub: an [x] switch for every category list
    local mainRef = spawnPanel("HAVOC HUB", {}, 0)

    -- live search: filters every registered category row in place
    local function applySearch(raw)
        local q = string.lower(raw or "")
        local searching = q ~= ""
        for _, cat in ipairs(searchCats) do
            if searching then
                if not cat.snap then
                    cat.snap = { expanded = cat.panelRef.isExpanded(), groups = {} }
                    for _, gr in ipairs(cat.groups) do
                        cat.snap.groups[gr] = gr.getOpen()
                    end
                end
                local matches = 0
                for _, e in ipairs(cat.entries) do
                    if not e.grp and not e.group then
                        local m = string.find(e.name, q, 1, true) ~= nil
                        e.row.Visible = m
                        if m then matches = matches + 1 end
                    end
                end
                for _, gr in ipairs(cat.groups) do
                    local gm = string.find(gr.nameLower, q, 1, true) ~= nil
                    local child = false
                    for _, e in ipairs(gr.entries) do
                        local m = gm or (string.find(e.name, q, 1, true) ~= nil)
                        e.row.Visible = m
                        if m then child = true end
                    end
                    local show = gm or child
                    gr.container.Visible = show
                    gr.setOpen(show)
                    if show then matches = matches + 1 end
                end
                if matches > 0 then cat.panelRef.setExpanded(true) end
            else
                for _, e in ipairs(cat.entries) do
                    e.row.Visible = true
                end
                for _, gr in ipairs(cat.groups) do
                    gr.container.Visible = true
                end
                if cat.snap then
                    cat.panelRef.setExpanded(cat.snap.expanded)
                    for _, gr in ipairs(cat.groups) do
                        gr.setOpen(cat.snap.groups[gr])
                    end
                    cat.snap = nil
                end
            end
        end
    end

    local searchBox = create("TextBox", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.4,
        Text = "",
        PlaceholderText = "search modules...",
        PlaceholderColor3 = THEME.TEXT_DIM,
        TextColor3 = THEME.WHITE,
        TextSize = 11,
        Font = FONTS.MEDIUM,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        LayoutOrder = nextOrder(),
        ZIndex = 61,
        Parent = mainRef.items,
    })
    box(searchBox, THEME.BORDER, 0.4)
    local searchPad = Instance.new("UIPadding")
    searchPad.PaddingLeft = UDim.new(0, 4)
    searchPad.Parent = searchBox
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        applySearch(searchBox.Text)
    end)
    addLabel(mainRef.items, "havoc-ui " .. tostring(HavocUI.VERSION))

    local function addVisibilityRow(catName, catPanel)
        local row = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundColor3 = THEME.ROW_HOVER,
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = nextOrder(),
            ZIndex = 61,
            Parent = mainRef.items,
        })
        local marker = label(row, "[x]", 12, THEME.GREEN, {
            Size = UDim2.fromOffset(26, 20),
            Position = UDim2.fromOffset(6, 0),
            ZIndex = 62,
            Parent = row,
        })
        local nameL = label(row, catName, 12, THEME.WHITE, {
            Size = UDim2.new(1, -40, 1, 0),
            Position = UDim2.fromOffset(30, 0),
            ZIndex = 62,
            Parent = row,
        })
        row.MouseEnter:Connect(function() tween(row, 0.1, { BackgroundTransparency = THEME.ROW_HOVER_T }) end)
        row.MouseLeave:Connect(function() tween(row, 0.1, { BackgroundTransparency = 1 }) end)
        row.MouseButton1Click:Connect(function()
            local vis = not catPanel.Visible
            catPanel.Visible = vis
            marker.Text = vis and "[x]" or "[ ]"
            marker.TextColor3 = vis and THEME.GREEN or THEME.TEXT_DIM
            nameL.TextColor3 = vis and THEME.WHITE or THEME.TEXT_DIM
        end)
    end

    function W.category(name, opts2)
        opts2 = opts2 or {}
        index = index + 1
        local ref = spawnPanel(name, opts2, index)
        addVisibilityRow(name, ref.panel)
        local cat = { panelRef = ref, entries = {}, groups = {} }
        searchCats[#searchCats + 1] = cat
        local api = makeBuilders(cat, ref.items, nil)
        api.panel = ref.panel
        api.header = ref.header
        api.items = ref.items
        api.setExpanded = ref.setExpanded
        return api
    end

    -- manager handle (all panels act as one menu)
    W.setScale = function(s)
        local v = math.clamp(tonumber(s) or 1, 0.6, 1.6)
        for _, ref in ipairs(panelRefs) do
            ref.uiScale.Scale = v
        end
    end
    W.show = function()
        for _, ref in ipairs(panelRefs) do ref.panel.Visible = true end
    end
    W.hide = function()
        for _, ref in ipairs(panelRefs) do ref.panel.Visible = false end
    end
    W.toggle = function()
        if W.isVisible() then W.hide() else W.show() end
    end
    W.isVisible = function()
        local first = panelRefs[1]
        return first ~= nil and first.panel.Visible
    end
    W.destroy = function()
        if tickerConn then
            pcall(function() tickerConn:Disconnect() end)
            tickerConn = nil
        end
        table.clear(tickers)
        table.clear(searchCats)
        for _, ref in ipairs(panelRefs) do
            pcall(function() ref.panel:Destroy() end)
        end
    end
    return W
end

return HavocUI
