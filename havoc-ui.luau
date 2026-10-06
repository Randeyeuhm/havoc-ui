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
HavocUI.VERSION = "v0.3-detached"

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
        local channels = { "R", "G", "B" }
        local comps = { 255, 255, 255 }
        local channelRows = {}
        local function applyChannel()
            local c = Color3.fromRGB(comps[1], comps[2], comps[3])
            setter(c)
            swatch.BackgroundColor3 = c
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
            local c = getter()
            if typeof(c) ~= "Color3" then c = Color3.new(1, 1, 1) end
            comps = {
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5),
            }
            swatch.BackgroundColor3 = c
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
        row.MouseButton1Click:Connect(function()
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

    -- ========================================================
    -- CATEGORIES (each one is its own detached panel)
    -- ========================================================
    function W.category(name, opts2)
        opts2 = opts2 or {}
        index = index + 1
        local px, py
        if layout == "column" then
            px = startX
            py = startY + (index - 1) * 24
        else
            px = startX + (index - 1) * (width + gap)
            py = startY
        end

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
        header.MouseButton1Click:Connect(function()
            setExpanded(not expanded)
        end)

        -- drag each panel by its own header
        header.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local sx, sy = input.Position.X, input.Position.Y
            local ox, oy = panel.Position.X.Offset, panel.Position.Y.Offset
            HavocUI.startDrag(function(mx, my)
                panel.Position = UDim2.fromOffset(
                    math.floor(ox + (mx - sx)), math.floor(oy + (my - sy)))
            end)
        end)

        local cat = {}
        cat.panel = panel
        cat.header = header
        cat.items = items
        cat.setExpanded = setExpanded
        cat.addToggle      = function(_, t, g, s, hk, o) return addToggle(items, t, g, s, hk, o) end
        cat.addSlider      = function(_, t, mn, mx, g, s, o) return addSlider(items, t, mn, mx, g, s, o) end
        cat.addDropdown    = function(_, t, it, g, s, o) return addDropdown(items, t, it, g, s, o) end
        cat.addMultiSelect = function(_, t, it, g, s, o) return addMultiSelect(items, t, it, g, s, o) end
        cat.addColor       = function(_, t, g, s, o) return addColor(items, t, g, s, o) end
        cat.addKeybind     = function(_, e, o) return addKeybind(items, e, o) end
        cat.addButton      = function(_, t, f, o) return addButton(items, t, f, o) end
        cat.addLabel       = function(_, t) return addLabel(items, t) end
        updatePanel()
        return cat
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
        for _, ref in ipairs(panelRefs) do
            pcall(function() ref.panel:Destroy() end)
        end
    end
    return W
end

return HavocUI
