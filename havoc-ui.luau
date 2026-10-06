--[[
    Havoc UI - frosted-glass Roblox GUI toolkit (v0.1)

    Design language:
      - translucent dark glass: low-opacity panels over the game world
      - 1px light borders, rounded corners, soft accent glow
      - gentle motion: hover tweens, popup grow, toast slide, window rise

    Wiring:
        local HavocUI = loadstring(readfile('havoc-ui.luau'), '@havoc-ui')()

        local toaster = HavocUI.makeToaster(screenGui)
        HavocUI.init{
            notify           = toaster,
            save             = saveConfig,
            saveDebounced    = saveConfigDebounced,
            onKeybindToggled = function(entry) end,
            onKeybindChanged = function(entry) end,
            canBind          = function(entry, key) return true end,
        }

        local win = HavocUI.makeWindow{
            parent = screenGui, title = "HAVOC HUB", subtitle = "v1.0",
            tabs = { "General", "Visuals" },
        }
        -- build widgets into win.tab(i), collect the handles, then:
        win.setControls(controls)      -- enables the search bar

        track(HavocUI.attachInput())
        -- top of your InputBegan handler:
        if HavocUI.handleRebindInput(input) then return end

    Factories (all return { row, update, searchText } unless noted):
        makeWindow, makeSectionHeader, makeNote, makeToggle, makeSlider,
        makeButton, makeInput, makeDropdown, makeMultiSelect,
        makeColorPicker, makeKeybindRow, makeToaster (returns notify fn)
]]

local UserInputService = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local TextService       = game:GetService("TextService")

local HavocUI = {}
HavocUI.VERSION = "v0.1-frost"

-- ============================================================
-- THEME / FONTS
-- ============================================================
local THEME = {
    -- glass surfaces (T = BackgroundTransparency)
    WIN        = Color3.fromRGB(13, 15, 23),    WIN_T      = 0.10,
    HEADER     = Color3.fromRGB(19, 21, 32),    HEADER_T   = 0.16,
    RAIL       = Color3.fromRGB(16, 18, 27),    RAIL_T     = 0.22,
    PANEL      = Color3.fromRGB(26, 29, 43),    PANEL_T    = 0.30,
    PANEL_HI   = Color3.fromRGB(35, 39, 56),
    TRACK      = Color3.fromRGB(30, 33, 47),    TRACK_T    = 0.25,
    POPUP      = Color3.fromRGB(17, 19, 29),    POPUP_T    = 0.06,
    -- strokes / lines
    BORDER     = Color3.fromRGB(255, 255, 255), BORDER_T   = 0.88,
    LINE       = Color3.fromRGB(255, 255, 255), LINE_T     = 0.94,
    -- text
    TEXT       = Color3.fromRGB(238, 241, 250),
    TEXT_DIM   = Color3.fromRGB(152, 159, 182),
    TEXT_FAINT = Color3.fromRGB(104, 111, 134),
    -- accents
    ACCENT     = Color3.fromRGB(122, 162, 255),
    ACCENT_HI  = Color3.fromRGB(152, 186, 255),
    GREEN      = Color3.fromRGB(88, 214, 141),
    AMBER      = Color3.fromRGB(245, 196, 106),
    RED        = Color3.fromRGB(232, 108, 122),
    RED_HI     = Color3.fromRGB(246, 132, 144),
    KNOB       = Color3.fromRGB(246, 248, 255),
}
HavocUI.THEME = THEME

local FONTS = {
    REGULAR = Enum.Font.Gotham,
    MEDIUM  = Enum.Font.GothamMedium,
    BOLD    = Enum.Font.GothamBold,
}
HavocUI.FONTS = FONTS

-- ============================================================
-- HOST HOOKS (UILib.init equivalent)
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

local function corner(gui, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = gui
    return c
end

local function stroke(gui, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.BORDER
    s.Transparency = transparency or THEME.BORDER_T
    s.Thickness = 1
    s.Parent = gui
    return s
end

local function gradient(gui, from, to, rotation, fromT, toT)
    local g = Instance.new("UIGradient")
    if type(from) == "ColorSequence" then
        g.Color = from
    else
        g.Color = ColorSequence.new(from, to)
    end
    g.Rotation = rotation or 90
    if fromT ~= nil or toT ~= nil then
        g.Transparency = NumberSequence.new(fromT or 0, toT or 0)
    end
    g.Parent = gui
    return g
end

local function tween(gui, time, props, style, dir)
    local t = TweenService:Create(gui, TweenInfo.new(
        time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- hover highlight for rows / buttons
local function hoverable(gui, baseColor, hiColor)
    gui.BackgroundColor3 = baseColor
    gui.MouseEnter:Connect(function() tween(gui, 0.12, { BackgroundColor3 = hiColor }) end)
    gui.MouseLeave:Connect(function() tween(gui, 0.12, { BackgroundColor3 = baseColor }) end)
end

-- ============================================================
-- INPUT PLUMBING
-- ============================================================
local drags = {}          -- active drag handlers: fn(mouseX, mouseY)
local activePopup = nil   -- { contains(x, y) -> bool, close() }
local pendingRebind = nil -- { entry, chip, restore }

function HavocUI.startDrag(fn)
    table.insert(drags, fn)
    return fn
end

function HavocUI.endDrag(fn)
    for i = #drags, 1, -1 do
        if drags[i] == fn then table.remove(drags, i) end
    end
end

function HavocUI.setActivePopup(popup)
    if activePopup and activePopup ~= popup then
        local prev = activePopup
        activePopup = nil
        pcall(prev.close)
    end
    activePopup = popup
end

function HavocUI.clearActivePopup(popup)
    if activePopup == popup then activePopup = nil end
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
    table.insert(conns, UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 and activePopup then
            local x, y = input.Position.X, input.Position.Y
            if not activePopup.contains(x, y) then
                local prev = activePopup
                activePopup = nil
                pcall(prev.close)
            end
        end
    end))
    return {
        disconnect = function()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        end,
    }
end

-- ---- keybind rebinding -------------------------------------
function HavocUI.beginRebind(entry, chip)
    if not entry or not chip then return end
    pendingRebind = { entry = entry, chip = chip, restore = chip.Text }
    chip.Text = "..."
    chip.TextColor3 = THEME.ACCENT
end

function HavocUI.handleRebindInput(input)
    if not pendingRebind then return false end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return false end
    local rb = pendingRebind
    if input.KeyCode == Enum.KeyCode.Escape then
        pendingRebind = nil
        rb.chip.Text = rb.restore
        rb.chip.TextColor3 = THEME.TEXT_DIM
        return true
    end
    if HOST.canBind and HOST.canBind(rb.entry, input.KeyCode) == false then
        return true
    end
    pendingRebind = nil
    rb.entry.Key = input.KeyCode
    rb.chip.Text = input.KeyCode.Name
    rb.chip.TextColor3 = THEME.TEXT_DIM
    if HOST.onKeybindChanged then
        pcall(HOST.onKeybindChanged, rb.entry)
    elseif HOST.onKeybindToggled then
        pcall(HOST.onKeybindToggled, rb.entry)
    end
    return true
end

-- ============================================================
-- SHARED ROW PIECES
-- ============================================================
local function padRow(parent, height)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, height or 38),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    corner(row, 8)
    return row
end

local function rowHover(row)
    row.BackgroundColor3 = THEME.PANEL
    row.BackgroundTransparency = 1
    row.MouseEnter:Connect(function() tween(row, 0.12, { BackgroundTransparency = 0.82 }) end)
    row.MouseLeave:Connect(function() tween(row, 0.12, { BackgroundTransparency = 1 }) end)
end

local function rowLabel(row, text, widthReserve)
    local label = create("TextLabel", {
        Size = UDim2.new(1, -(widthReserve or 110), 1, 0),
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = THEME.TEXT,
        TextSize = 14,
        Font = FONTS.MEDIUM,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })
    return label
end

local function keyChip(parent, entry, opts)
    opts = opts or {}
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(78, 22),
        Position = UDim2.new(1, 0, 0.5, -11),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = THEME.PANEL,
        BackgroundTransparency = THEME.PANEL_T,
        Text = (entry and entry.Key and entry.Key.Name) or "-",
        TextColor3 = THEME.TEXT_DIM,
        TextSize = 11,
        Font = FONTS.MEDIUM,
        AutoButtonColor = false,
        Parent = parent,
    })
    corner(chip, 6)
    stroke(chip, THEME.BORDER, 0.92)
    chip.MouseEnter:Connect(function()
        if not opts.locked then tween(chip, 0.12, { BackgroundColor3 = THEME.PANEL_HI }) end
    end)
    chip.MouseLeave:Connect(function()
        tween(chip, 0.12, { BackgroundColor3 = THEME.PANEL })
    end)
    chip.MouseButton1Click:Connect(function()
        if opts.locked then
            if opts.lockNote then toast(opts.lockNote) end
            return
        end
        HavocUI.beginRebind(entry, chip)
    end)
    return chip
end

-- ============================================================
-- WIDGETS
-- ============================================================
function HavocUI.makeSectionHeader(parent, text)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local dash = create("Frame", {
        Size = UDim2.fromOffset(3, 12),
        Position = UDim2.new(0, 2, 0.5, -6),
        BackgroundColor3 = THEME.ACCENT,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(dash, 2)
    create("TextLabel", {
        Size = UDim2.new(1, -14, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = string.upper(text or ""),
        TextColor3 = THEME.TEXT_DIM,
        TextSize = 11,
        Font = FONTS.BOLD,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    return { row = row, update = function() end }
end

function HavocUI.makeNote(parent, text)
    local label = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = THEME.TEXT_DIM,
        TextSize = 12,
        Font = FONTS.REGULAR,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = parent,
    })
    return label
end

function HavocUI.makeToggle(parent, text, getter, setter, hkEntry, opts)
    local row = padRow(parent, 38)
    rowLabel(row, text, hkEntry and 172 or 92)
    rowHover(row)
    local chip = nil
    if hkEntry then chip = keyChip(row, hkEntry) end

    local switch = create("TextButton", {
        Size = UDim2.fromOffset(38, 20),
        Position = UDim2.new(1, 0, 0.5, -10),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = THEME.TRACK,
        BackgroundTransparency = THEME.TRACK_T,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(switch, 10)
    stroke(switch, THEME.BORDER, 0.90)
    local knob = create("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = THEME.KNOB,
        BorderSizePixel = 0,
        Parent = switch,
    })
    corner(knob, 8)

    local function refresh()
        local on = getter() and true or false
        tween(switch, 0.15, { BackgroundColor3 = on and THEME.ACCENT or THEME.TRACK })
        tween(knob, 0.15, {
            Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        })
        if chip and hkEntry then
            chip.TextColor3 = hkEntry.Enabled and THEME.TEXT or THEME.TEXT_FAINT
        end
    end
    switch.MouseButton1Click:Connect(function()
        setter(not (getter() and true or false))
        refresh()
        saveTouched()
    end)
    refresh()
    return { row = row, update = refresh, searchText = text }
end

function HavocUI.makeSlider(parent, text, min, max, getter, setter, opts)
    opts = opts or {}
    local suffix = opts.suffix or ""
    local step = opts.step
    local decimals = opts.decimals
    if decimals == nil then
        local s = step or ((max - min) / 100)
        decimals = s >= 1 and 0 or 1
    end
    local row = padRow(parent, 46)
    rowLabel(row, text, 140)
    rowHover(row)
    local valueBox = create("TextLabel", {
        Size = UDim2.fromOffset(110, 20),
        Position = UDim2.new(1, 0, 0, 2),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = THEME.PANEL,
        BackgroundTransparency = THEME.PANEL_T,
        Text = "",
        TextColor3 = THEME.TEXT,
        TextSize = 12,
        Font = FONTS.MEDIUM,
        Parent = row,
    })
    corner(valueBox, 6)
    stroke(valueBox, THEME.BORDER, 0.92)

    local track = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0, 34),
        BackgroundColor3 = THEME.TRACK,
        BackgroundTransparency = THEME.TRACK_T,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(track, 3)
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.ACCENT,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 3)
    local knob = create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.KNOB,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = track,
    })
    corner(knob, 7)

    local function fmt(v)
        return string.format("%." .. tostring(decimals) .. "f", v) .. suffix
    end
    local function setFrac(frac, live)
        frac = math.clamp(frac, 0, 1)
        local v = min + frac * (max - min)
        if step then v = math.floor(v / step + 0.5) * step end
        v = math.clamp(v, min, max)
        tween(fill, live and 0.05 or 0.15, { Size = UDim2.new(frac, 0, 1, 0) })
        tween(knob, live and 0.05 or 0.15, { Position = UDim2.new(frac, 0, 0.5, 0) })
        valueBox.Text = fmt(v)
        return v
    end
    local function refresh()
        local v = math.clamp(tonumber(getter()) or min, min, max)
        setFrac((v - min) / math.max(max - min, 1e-9))
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local function apply(mx)
            local pos, size = track.AbsolutePosition, track.AbsoluteSize
            local frac = (mx - pos.X) / math.max(size.X, 1)
            local v = setFrac(frac, true)
            setter(v)
        end
        apply(input.Position.X)
        HavocUI.startDrag(function(mx)
            apply(mx)
        end)
    end)
    refresh()
    return { row = row, update = refresh, searchText = text }
end

function HavocUI.makeButton(parent, text, fn, opts)
    opts = opts or {}
    local style = opts.style or "glass"
    local base, hi, textColor
    if style == "primary" then
        base, hi, textColor = THEME.ACCENT, THEME.ACCENT_HI, Color3.fromRGB(10, 12, 20)
    elseif style == "danger" then
        base, hi, textColor = THEME.RED, THEME.RED_HI, Color3.fromRGB(24, 8, 12)
    else
        base, hi, textColor = THEME.PANEL, THEME.PANEL_HI, THEME.TEXT
    end
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = base,
        BackgroundTransparency = (style == "glass") and THEME.PANEL_T or 0.12,
        Text = text or "",
        TextColor3 = textColor,
        TextSize = 13,
        Font = FONTS.BOLD,
        AutoButtonColor = false,
        Parent = parent,
    })
    corner(btn, 8)
    if style == "glass" then stroke(btn, THEME.BORDER, 0.9) end
    hoverable(btn, base, hi)
    btn.MouseButton1Click:Connect(function()
        if fn then pcall(fn) end
    end)
    return { row = btn, update = function() end, searchText = text }
end

function HavocUI.makeInput(parent, text, getter, setter, opts)
    opts = opts or {}
    local row = padRow(parent, 38)
    rowLabel(row, text, (opts.width or 130) + 34)
    rowHover(row)
    local box = create("TextBox", {
        Size = UDim2.fromOffset(opts.width or 130, 26),
        Position = UDim2.new(1, 0, 0.5, -13),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = THEME.PANEL,
        BackgroundTransparency = THEME.PANEL_T,
        Text = "",
        PlaceholderText = opts.placeholder or "",
        PlaceholderColor3 = THEME.TEXT_FAINT,
        TextColor3 = THEME.TEXT,
        TextSize = 12,
        Font = FONTS.MEDIUM,
        ClearTextOnFocus = false,
        Parent = row,
    })
    corner(box, 6)
    local boxStroke = stroke(box, THEME.BORDER, 0.92)
    box.Focused:Connect(function()
        boxStroke.Color = THEME.ACCENT
        tween(boxStroke, 0.12, { Transparency = 0.4 })
    end)
    box.FocusLost:Connect(function()
        boxStroke.Color = THEME.BORDER
        tween(boxStroke, 0.12, { Transparency = 0.92 })
        local v = box.Text
        if opts.numeric then
            local n = tonumber(v)
            if n == nil then box.Text = tostring(getter() or ""); return end
            v = n
        end
        setter(v)
        saveTouched()
    end)
    local function refresh()
        if box:IsFocused() then return end
        local v = getter()
        box.Text = v == nil and "" or tostring(v)
    end
    refresh()
    return { row = row, update = refresh, searchText = text }
end

-- ============================================================
-- POPUPS (dropdown / multiselect / colour picker)
-- ============================================================
local function popupContains(popup, owner, x, y)
    local pp, ps = popup.AbsolutePosition, popup.AbsoluteSize
    local op, os = owner.AbsolutePosition, owner.AbsoluteSize
    if x >= pp.X and x <= pp.X + ps.X and y >= pp.Y and y <= pp.Y + ps.Y then return true end
    if x >= op.X and x <= op.X + os.X and y >= op.Y and y <= op.Y + os.Y then return true end
    return false
end

local function makePopup(overlay, owner, width, height)
    local win = overlay.Parent
    local popup = create("CanvasGroup", {
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = THEME.POPUP,
        BackgroundTransparency = THEME.POPUP_T,
        ZIndex = overlay.ZIndex + 1,
        GroupTransparency = 1,
        Parent = overlay,
    })
    corner(popup, 10)
    stroke(popup, THEME.BORDER, 0.86)
    local px = owner.AbsolutePosition.X - win.AbsolutePosition.X
    local py = owner.AbsolutePosition.Y - win.AbsolutePosition.Y + owner.AbsoluteSize.Y + 5
    local maxY = win.AbsoluteSize.Y - height - 8
    if py > maxY then
        local above = owner.AbsolutePosition.Y - win.AbsolutePosition.Y - height - 5
        py = (above >= 8) and above or math.max(8, maxY)
    end
    px = math.clamp(px, 8, math.max(8, win.AbsoluteSize.X - width - 8))
    popup.Position = UDim2.fromOffset(math.floor(px), math.floor(py) - 4)
    tween(popup, 0.16, {
        GroupTransparency = 0,
        Position = UDim2.fromOffset(math.floor(px), math.floor(py)),
    })
    return popup
end

local function closePopupAnim(popup)
    local t = tween(popup, 0.12, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    t.Completed:Connect(function() popup:Destroy() end)
end

local function chipWithValue(parent, width)
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(width, 26),
        Position = UDim2.new(1, 0, 0.5, -13),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = THEME.PANEL,
        BackgroundTransparency = THEME.PANEL_T,
        Text = "",
        AutoButtonColor = false,
        Parent = parent,
    })
    corner(chip, 7)
    stroke(chip, THEME.BORDER, 0.9)
    local value = create("TextLabel", {
        Size = UDim2.new(1, -36, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = THEME.TEXT,
        TextSize = 12,
        Font = FONTS.MEDIUM,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = chip,
    })
    local chev = create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(1, -24, 0.5, -7),
        BackgroundTransparency = 1,
        Parent = chip,
    })
    local function bar(x)
        local b = create("Frame", {
            Size = UDim2.fromOffset(7, 2),
            Position = UDim2.new(0, x, 0, 6),
            BackgroundColor3 = THEME.TEXT_DIM,
            BorderSizePixel = 0,
            Parent = chev,
        })
        corner(b, 1)
        return b
    end
    bar(1).Rotation = 45
    bar(6).Rotation = -45
    chip.MouseEnter:Connect(function() tween(chip, 0.12, { BackgroundColor3 = THEME.PANEL_HI }) end)
    chip.MouseLeave:Connect(function() tween(chip, 0.12, { BackgroundColor3 = THEME.PANEL }) end)
    return chip, value
end

function HavocUI.makeDropdown(parent, text, items, getter, setter, opts)
    opts = opts or {}
    local row = padRow(parent, 38)
    rowLabel(row, text, 196)
    rowHover(row)
    local chip, value = chipWithValue(row, 178)

    local popup = nil
    local function closeMyPopup()
        if not popup then return end
        local old = popup
        popup = nil
        HavocUI.clearActivePopup(old)
        closePopupAnim(old)
    end
    local function updateChip()
        value.Text = tostring(getter() or "-")
    end
    local function openPopup()
        local list = type(items) == "function" and items() or items
        if not opts.overlay or popup then return end
        local h = math.min(#list, 9) * 28 + 10
        popup = makePopup(opts.overlay, chip, 178, h)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
            Parent = popup,
        })
        create("UIListLayout", {
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = popup,
        })
        local current = tostring(getter())
        for i, item in ipairs(list) do
            local isOn = tostring(item) == current
            local itemBtn = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = isOn and THEME.PANEL_HI or THEME.PANEL,
                BackgroundTransparency = isOn and 0.2 or 0.5,
                Text = tostring(item),
                TextColor3 = isOn and THEME.TEXT or THEME.TEXT_DIM,
                TextSize = 12,
                Font = isOn and FONTS.BOLD or FONTS.MEDIUM,
                TextXAlignment = Enum.TextXAlignment.Left,
                AutoButtonColor = false,
                LayoutOrder = i,
                Parent = popup,
            })
            create("UIPadding", { PaddingLeft = UDim.new(0, 9), Parent = itemBtn })
            corner(itemBtn, 6)
            itemBtn.MouseEnter:Connect(function()
                tween(itemBtn, 0.1, { BackgroundColor3 = THEME.PANEL_HI, BackgroundTransparency = 0.2 })
            end)
            itemBtn.MouseLeave:Connect(function()
                tween(itemBtn, 0.1, {
                    BackgroundColor3 = isOn and THEME.PANEL_HI or THEME.PANEL,
                    BackgroundTransparency = isOn and 0.2 or 0.5,
                })
            end)
            itemBtn.MouseButton1Click:Connect(function()
                setter(item)
                updateChip()
                closeMyPopup()
                saveTouched()
            end)
        end
        local thisPopup = popup
        HavocUI.setActivePopup({
            contains = function(x, y)
                return thisPopup.Parent ~= nil and popupContains(thisPopup, chip, x, y)
            end,
            close = function() closeMyPopup() end,
        })
    end
    chip.MouseButton1Click:Connect(function()
        if popup then closeMyPopup() else openPopup() end
    end)
    updateChip()
    return { row = row, update = updateChip, searchText = text }
end

function HavocUI.makeMultiSelect(parent, text, items, isOn, setOn, opts)
    opts = opts or {}
    local row = padRow(parent, 38)
    rowLabel(row, text, 196)
    rowHover(row)
    local chip, value = chipWithValue(row, 178)

    local popup = nil
    local itemRefs = {}
    local function closeMyPopup()
        if not popup then return end
        local old = popup
        popup = nil
        itemRefs = {}
        HavocUI.clearActivePopup(old)
        closePopupAnim(old)
    end
    local function summary()
        local list = type(items) == "function" and items() or items
        local n = 0
        for _, it in ipairs(list) do
            if isOn(it) then n = n + 1 end
        end
        if n == 0 then return "none" end
        if n == #list then return "all" end
        return n .. " selected"
    end
    local function updateChip()
        value.Text = summary()
    end
    local function paintItem(ref)
        local on = isOn(ref.item) and true or false
        ref.box.BackgroundColor3 = on and THEME.ACCENT or THEME.PANEL
        ref.box.BackgroundTransparency = on and 0.05 or 0.5
        ref.inner.Visible = on
        ref.label.TextColor3 = on and THEME.TEXT or THEME.TEXT_DIM
    end
    local function openPopup()
        local list = type(items) == "function" and items() or items
        if not opts.overlay or popup then return end
        local h = math.min(#list, 9) * 28 + 10
        popup = makePopup(opts.overlay, chip, 178, h)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
            Parent = popup,
        })
        create("UIListLayout", {
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = popup,
        })
        itemRefs = {}
        for i, item in ipairs(list) do
            local itemRow = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = THEME.PANEL,
                BackgroundTransparency = 0.5,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = i,
                Parent = popup,
            })
            corner(itemRow, 6)
            local box = create("Frame", {
                Size = UDim2.fromOffset(14, 14),
                Position = UDim2.new(0, 9, 0.5, -7),
                BackgroundColor3 = THEME.PANEL,
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
                Parent = itemRow,
            })
            corner(box, 4)
            stroke(box, THEME.BORDER, 0.85)
            local inner = create("Frame", {
                Size = UDim2.fromOffset(6, 6),
                Position = UDim2.new(0.5, -3, 0.5, -3),
                BackgroundColor3 = THEME.KNOB,
                BorderSizePixel = 0,
                Parent = box,
            })
            corner(inner, 2)
            local label = create("TextLabel", {
                Size = UDim2.new(1, -34, 1, 0),
                Position = UDim2.fromOffset(30, 0),
                BackgroundTransparency = 1,
                Text = tostring(item),
                TextColor3 = THEME.TEXT_DIM,
                TextSize = 12,
                Font = FONTS.MEDIUM,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = itemRow,
            })
            local ref = { item = item, box = box, inner = inner, label = label }
            itemRefs[#itemRefs + 1] = ref
            paintItem(ref)
            itemRow.MouseEnter:Connect(function()
                tween(itemRow, 0.1, { BackgroundTransparency = 0.25 })
            end)
            itemRow.MouseLeave:Connect(function()
                tween(itemRow, 0.1, { BackgroundTransparency = 0.5 })
            end)
            itemRow.MouseButton1Click:Connect(function()
                setOn(item, not (isOn(item) and true or false))
                paintItem(ref)
                updateChip()
                saveTouched()
            end)
        end
        local thisPopup = popup
        HavocUI.setActivePopup({
            contains = function(x, y)
                return thisPopup.Parent ~= nil and popupContains(thisPopup, chip, x, y)
            end,
            close = function() closeMyPopup() end,
        })
    end
    chip.MouseButton1Click:Connect(function()
        if popup then closeMyPopup() else openPopup() end
    end)
    updateChip()
    return { row = row, update = function() updateChip() end, searchText = text }
end

function HavocUI.makeColorPicker(parent, text, getter, setter, opts)
    opts = opts or {}
    local row = padRow(parent, 38)
    rowLabel(row, text, 160)
    rowHover(row)
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(104, 26),
        Position = UDim2.new(1, 0, 0.5, -13),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Text = "",
        TextSize = 11,
        Font = FONTS.MEDIUM,
        AutoButtonColor = false,
        Parent = row,
    })
    corner(chip, 7)
    stroke(chip, THEME.BORDER, 0.8)

    local popup = nil
    local h, s, v = 0.6, 1, 1
    local syncing = false
    local function chipText(color)
        local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
        chip.TextColor3 = lum > 0.55 and Color3.fromRGB(12, 14, 22) or Color3.fromRGB(244, 246, 252)
        chip.Text = color:ToHex()
    end
    local function readColor()
        local c = getter()
        if typeof(c) ~= "Color3" then c = Color3.new(1, 1, 1) end
        h, s, v = c:ToHSV()
        return c
    end
    local function closeMyPopup()
        if not popup then return end
        local old = popup
        popup = nil
        HavocUI.clearActivePopup(old)
        closePopupAnim(old)
    end
    local function openPopup()
        if not opts.overlay or popup then return end
        readColor()
        popup = makePopup(opts.overlay, chip, 214, 224)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
            Parent = popup,
        })
        local sv = create("TextButton", {
            Size = UDim2.fromOffset(172, 150),
            BackgroundColor3 = Color3.fromHSV(h, 1, 1),
            Text = "",
            AutoButtonColor = false,
            Parent = popup,
        })
        corner(sv, 7)
        local white = create("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            Parent = sv,
        })
        corner(white, 7)
        gradient(white, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0, 0, 1)
        local black = create("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BorderSizePixel = 0,
            Parent = sv,
        })
        corner(black, 7)
        gradient(black, Color3.new(0, 0, 0), Color3.new(0, 0, 0), 90, 1, 0)
        local cursor = create("Frame", {
            Size = UDim2.fromOffset(12, 12),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = sv,
        })
        corner(cursor, 6)
        local cs = stroke(cursor, Color3.fromRGB(255, 255, 255), 0.15)
        cs.Thickness = 2

        local hueBar = create("TextButton", {
            Size = UDim2.fromOffset(16, 150),
            Position = UDim2.fromOffset(180, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            Text = "",
            AutoButtonColor = false,
            Parent = popup,
        })
        corner(hueBar, 8)
        gradient(hueBar, ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
        }), 90)
        local hueCursor = create("Frame", {
            Size = UDim2.new(1, 4, 0, 4),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = hueBar,
        })
        corner(hueCursor, 2)
        stroke(hueCursor, Color3.fromRGB(0, 0, 0), 0.6)

        local hexBox = create("TextBox", {
            Size = UDim2.fromOffset(88, 26),
            Position = UDim2.fromOffset(0, 162),
            BackgroundColor3 = THEME.PANEL,
            BackgroundTransparency = THEME.PANEL_T,
            Text = "",
            TextColor3 = THEME.TEXT,
            TextSize = 12,
            Font = FONTS.MEDIUM,
            ClearTextOnFocus = false,
            Parent = popup,
        })
        corner(hexBox, 6)
        stroke(hexBox, THEME.BORDER, 0.9)
        create("TextLabel", {
            Size = UDim2.new(1, -110, 0, 26),
            Position = UDim2.fromOffset(98, 162),
            BackgroundTransparency = 1,
            Text = "drag the square + bar",
            TextColor3 = THEME.TEXT_FAINT,
            TextSize = 10,
            Font = FONTS.REGULAR,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = popup,
        })

        local function paint(apply)
            sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            cursor.Position = UDim2.new(s, -6, 1 - v, -6)
            hueCursor.Position = UDim2.new(0.5, 0, h, 0)
            local c = Color3.fromHSV(h, s, v)
            if not hexBox:IsFocused() then hexBox.Text = c:ToHex() end
            if apply then
                syncing = true
                setter(c)
                syncing = false
                chipText(c)
                chip.BackgroundColor3 = c
                saveTouched()
            end
        end
        sv.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local function apply(mx, my)
                local pos, size = sv.AbsolutePosition, sv.AbsoluteSize
                s = math.clamp((mx - pos.X) / math.max(size.X, 1), 0, 1)
                v = 1 - math.clamp((my - pos.Y) / math.max(size.Y, 1), 0, 1)
                paint(true)
            end
            apply(input.Position.X, input.Position.Y)
            HavocUI.startDrag(function(mx, my)
                apply(mx, my)
            end)
        end)
        hueBar.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            local function apply(_mx, my)
                local pos, size = hueBar.AbsolutePosition, hueBar.AbsoluteSize
                h = math.clamp((my - pos.Y) / math.max(size.Y, 1), 0, 1)
                paint(true)
            end
            apply(input.Position.X, input.Position.Y)
            HavocUI.startDrag(function(mx, my)
                apply(mx, my)
            end)
        end)
        hexBox.FocusLost:Connect(function()
            local c = Color3.fromHex(hexBox.Text)
            syncing = true
            setter(c)
            syncing = false
            h, s, v = c:ToHSV()
            paint(false)
            chipText(c)
            chip.BackgroundColor3 = c
            saveTouched()
        end)
        paint(false)
        local thisPopup = popup
        HavocUI.setActivePopup({
            contains = function(x, y)
                return thisPopup.Parent ~= nil and popupContains(thisPopup, chip, x, y)
            end,
            close = function() closeMyPopup() end,
        })
    end
    chip.MouseButton1Click:Connect(function()
        if popup then closeMyPopup() else openPopup() end
    end)
    local function refresh()
        if syncing then return end
        local c = readColor()
        chipText(c)
        chip.BackgroundColor3 = c
    end
    refresh()
    return { row = row, update = refresh, searchText = text }
end

function HavocUI.makeKeybindRow(parent, entry, opts)
    opts = opts or {}
    local row = padRow(parent, 38)
    rowLabel(row, (entry and entry.Desc) or "Keybind", 110)
    rowHover(row)
    local chip = keyChip(row, entry, opts)
    local function refresh()
        chip.Text = (entry and entry.Key and entry.Key.Name) or "-"
        local enabled = not entry or entry.Enabled ~= false
        chip.TextColor3 = enabled and THEME.TEXT or THEME.TEXT_FAINT
    end
    refresh()
    return { row = row, update = refresh, searchText = entry and entry.Desc }
end

-- ============================================================
-- TOASTER
-- ============================================================
function HavocUI.makeToaster(parent)
    local holder = create("Frame", {
        Size = UDim2.new(0, 360, 0, 500),
        Position = UDim2.new(0.5, -180, 0, 12),
        BackgroundTransparency = 1,
        ZIndex = 300,
        Parent = parent,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Parent = holder,
    })
    local order = 0
    local KINDS = {
        info = THEME.ACCENT,
        ok = THEME.GREEN,
        warn = THEME.AMBER,
        err = THEME.RED,
    }
    local function notify(text, opts)
        opts = opts or {}
        text = tostring(text or "")
        order = order + 1
        local accent = KINDS[opts.kind or "info"] or THEME.ACCENT
        local bounds = TextService:GetTextSize(text, 13, FONTS.MEDIUM, Vector2.new(270, 600))
        local w = math.clamp(bounds.X + 60, 180, 340)
        local h = math.max(bounds.Y + 20, 38)
        local toast = create("CanvasGroup", {
            Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = THEME.WIN,
            BackgroundTransparency = THEME.WIN_T,
            GroupTransparency = 1,
            LayoutOrder = order,
            Parent = holder,
        })
        corner(toast, 10)
        stroke(toast, THEME.BORDER, 0.86)
        local bar = create("Frame", {
            Size = UDim2.fromOffset(3, h - 16),
            Position = UDim2.new(0, 10, 0.5, -(h - 16) / 2),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            Parent = toast,
        })
        corner(bar, 2)
        create("TextLabel", {
            Size = UDim2.new(1, -56, 1, 0),
            Position = UDim2.fromOffset(22, 0),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = THEME.TEXT,
            TextSize = 13,
            Font = FONTS.MEDIUM,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextWrapped = true,
            Parent = toast,
        })
        local sc = create("UIScale", { Scale = 0.96, Parent = toast })
        tween(toast, 0.18, { GroupTransparency = 0 })
        tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        task.delay(opts.duration or 2.6, function()
            if toast.Parent == nil then return end
            local t = tween(toast, 0.16, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            t.Completed:Connect(function() toast:Destroy() end)
        end)
        return toast
    end
    return notify
end

-- ============================================================
-- WINDOW
-- ============================================================
function HavocUI.makeWindow(opts)
    opts = opts or {}
    local tabsList = opts.tabs or {}
    local W = {}

    local frame = create("CanvasGroup", {
        Name = opts.name or "HavocUIWindow",
        Size = opts.size or UDim2.fromOffset(520, 640),
        Position = opts.position or UDim2.fromOffset(32, 48),
        BackgroundColor3 = THEME.WIN,
        BackgroundTransparency = THEME.WIN_T,
        ClipsDescendants = false,
        ZIndex = opts.zindex or 40,
        Parent = opts.parent,
    })
    corner(frame, 14)
    stroke(frame, THEME.BORDER, 0.84)

    local sheen = create("Frame", {
        Size = UDim2.new(1, 0, 0, 96),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = frame,
    })
    corner(sheen, 14)
    gradient(sheen, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255), 90, 0.965, 1)

    local glow = create("Frame", {
        Name = "Glow",
        Size = frame.Size + UDim2.fromOffset(14, 14),
        Position = frame.Position - UDim2.fromOffset(7, 7),
        BackgroundColor3 = THEME.ACCENT,
        BackgroundTransparency = 0.92,
        ZIndex = (opts.zindex or 40) - 1,
        Parent = opts.parent,
    })
    corner(glow, 20)

    -- UI scale (same rule as the hub menus: auto up to 1.2x on big displays)
    local scale = tonumber(opts.scale)
    if not scale then
        local vpY = 0
        local okS, psz = pcall(function() return opts.parent and opts.parent.AbsoluteSize end)
        if okS and psz then vpY = psz.Y end
        if vpY <= 0 then
            local okC, cam = pcall(function() return workspace.CurrentCamera end)
            if okC and cam then vpY = cam.ViewportSize.Y end
        end
        scale = math.clamp(vpY / 1150, 1, 1.2)
    end
    scale = math.clamp(scale, 0.5, 2)
    local uiScale = Instance.new("UIScale")
    uiScale.Parent = frame

    -- header
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = THEME.HEADER,
        BackgroundTransparency = THEME.HEADER_T,
        ZIndex = 2,
        Parent = frame,
    })
    corner(header, 14)
    create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 1, -16),
        BackgroundColor3 = THEME.HEADER,
        BackgroundTransparency = THEME.HEADER_T,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = header,
    })
    local dot = create("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 16, 0.5, -4),
        BackgroundColor3 = THEME.ACCENT,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = header,
    })
    corner(dot, 4)
    local dotGlow = create("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0.5, -8, 0.5, -8),
        BackgroundColor3 = THEME.ACCENT,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = dot,
    })
    corner(dotGlow, 8)
    create("TextLabel", {
        Size = UDim2.new(1, -180, 1, 0),
        Position = UDim2.fromOffset(32, 0),
        BackgroundTransparency = 1,
        Text = opts.title or "HAVOC",
        TextColor3 = THEME.TEXT,
        TextSize = 15,
        Font = FONTS.BOLD,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 3,
        Parent = header,
    })
    if opts.subtitle then
        create("TextLabel", {
            Size = UDim2.new(0, 190, 1, 0),
            Position = UDim2.new(1, -72, 0, 0),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundTransparency = 1,
            Text = tostring(opts.subtitle),
            TextColor3 = THEME.TEXT_DIM,
            TextSize = 11,
            Font = FONTS.MEDIUM,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 3,
            Parent = header,
        })
    end
    if opts.closable ~= false then
        local closeBtn = create("TextButton", {
            Size = UDim2.fromOffset(26, 26),
            Position = UDim2.new(1, -12, 0.5, -13),
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = THEME.RED,
            BackgroundTransparency = 0.75,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
            Parent = header,
        })
        corner(closeBtn, 8)
        for i = 1, 2 do
            local arm = create("Frame", {
                Size = UDim2.fromOffset(11, 2),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = THEME.KNOB,
                BorderSizePixel = 0,
                Rotation = (i == 1) and 45 or -45,
                ZIndex = 4,
                Parent = closeBtn,
            })
            corner(arm, 1)
        end
        closeBtn.MouseEnter:Connect(function()
            tween(closeBtn, 0.12, { BackgroundColor3 = THEME.RED_HI, BackgroundTransparency = 0.45 })
        end)
        closeBtn.MouseLeave:Connect(function()
            tween(closeBtn, 0.12, { BackgroundColor3 = THEME.RED, BackgroundTransparency = 0.75 })
        end)
        closeBtn.MouseButton1Click:Connect(function()
            if opts.onClose then
                pcall(opts.onClose)
            else
                W.hide()
            end
        end)
    end
    create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 0, 42),
        BackgroundColor3 = THEME.LINE,
        BackgroundTransparency = THEME.LINE_T,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = frame,
    })

    -- footer
    local footerH = opts.footerHint and 28 or 0
    if opts.footerHint then
        local footer = create("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            Position = UDim2.new(0, 0, 1, -28),
            BackgroundTransparency = 1,
            ZIndex = 3,
            Parent = frame,
        })
        create("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = THEME.LINE,
            BackgroundTransparency = THEME.LINE_T,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = footer,
        })
        create("TextLabel", {
            Size = UDim2.new(1, -200, 1, 0),
            Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1,
            Text = opts.footerHint,
            TextColor3 = THEME.TEXT_FAINT,
            TextSize = 11,
            Font = FONTS.MEDIUM,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3,
            Parent = footer,
        })
        if opts.footerRight then
            create("TextLabel", {
                Size = UDim2.new(0, 190, 1, 0),
                Position = UDim2.new(1, -14, 0, 0),
                AnchorPoint = Vector2.new(1, 0),
                BackgroundTransparency = 1,
                Text = tostring(opts.footerRight),
                TextColor3 = THEME.TEXT_FAINT,
                TextSize = 11,
                Font = FONTS.MEDIUM,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 3,
                Parent = footer,
            })
        end
    end

    -- search bar (created on demand by setControls)
    local search = nil
    local body = create("Frame", {
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = frame,
    })
    local function relayout()
        local top = 52 + (search and 38 or 0)
        body.Position = UDim2.fromOffset(10, top)
        body.Size = UDim2.new(1, -20, 1, -(top + footerH + 12))
    end
    relayout()

    -- rail + pages
    local rail = create("Frame", {
        Size = UDim2.new(0, 128, 1, 0),
        BackgroundColor3 = THEME.RAIL,
        BackgroundTransparency = THEME.RAIL_T,
        ZIndex = 2,
        Parent = body,
    })
    corner(rail, 10)
    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = rail,
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        Parent = rail,
    })
    local content = create("Frame", {
        Size = UDim2.new(1, -138, 1, 0),
        Position = UDim2.fromOffset(138, 0),
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = body,
    })
    local pages = {}
    local tabRefs = {}
    for i, name in ipairs(tabsList) do
        local page = create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.TEXT_FAINT,
            ScrollBarImageTransparency = 0.4,
            ZIndex = 2,
            Visible = (i == 1),
            Parent = content,
        })
        local lay = create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = page,
        })
        create("UIPadding", {
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8),
            Parent = page,
        })
        lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            page.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 16)
        end)
        pages[i] = page

        local btn = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = THEME.PANEL,
            BackgroundTransparency = 1,
            Text = name,
            TextColor3 = THEME.TEXT_DIM,
            TextSize = 13,
            Font = FONTS.MEDIUM,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
            LayoutOrder = i,
            ZIndex = 3,
            Parent = rail,
        })
        corner(btn, 8)
        create("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = btn })
        local bar = create("Frame", {
            Size = UDim2.fromOffset(3, 16),
            Position = UDim2.new(0, 4, 0.5, -8),
            BackgroundColor3 = THEME.ACCENT,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 4,
            Parent = btn,
        })
        corner(bar, 2)
        tabRefs[i] = { btn = btn, bar = bar }
        btn.MouseEnter:Connect(function()
            if pages[i].Visible then return end
            tween(btn, 0.12, { BackgroundTransparency = 0.75 })
        end)
        btn.MouseLeave:Connect(function()
            if pages[i].Visible then return end
            tween(btn, 0.12, { BackgroundTransparency = 1 })
        end)
        btn.MouseButton1Click:Connect(function() W.setTab(i) end)
    end

    function W.setTab(i)
        if type(i) == "string" then
            for k, name in ipairs(tabsList) do
                if name == i then
                    i = k
                    break
                end
            end
        end
        if not pages[i] then return end
        for k, page in pairs(pages) do
            page.Visible = (k == i)
        end
        for k, ref in pairs(tabRefs) do
            local on = (k == i)
            tween(ref.btn, 0.14, { BackgroundTransparency = on and 0.72 or 1 })
            ref.btn.TextColor3 = on and THEME.TEXT or THEME.TEXT_DIM
            tween(ref.bar, 0.14, { BackgroundTransparency = on and 0.05 or 1 })
        end
        if opts.onTabChanged then pcall(opts.onTabChanged, tabsList[i] or i) end
    end

    W.setTab(1)

    -- controls search
    local controls = {}
    local function applyFilter()
        if not search then return end
        local q = string.lower(search.Text or "")
        for _, handle in ipairs(controls) do
            local row = handle.row
            if row and row.Parent then
                if q == "" or handle.searchText == nil then
                    row.Visible = true
                else
                    row.Visible = string.find(string.lower(tostring(handle.searchText)), q, 1, true) ~= nil
                end
            end
        end
    end
    function W.setControls(list)
        controls = list or {}
        if #controls > 0 and not search then
            search = create("TextBox", {
                Size = UDim2.new(1, -28, 0, 30),
                Position = UDim2.fromOffset(14, 50),
                BackgroundColor3 = THEME.PANEL,
                BackgroundTransparency = THEME.PANEL_T,
                Text = "",
                PlaceholderText = "search...",
                PlaceholderColor3 = THEME.TEXT_FAINT,
                TextColor3 = THEME.TEXT,
                TextSize = 12,
                Font = FONTS.MEDIUM,
                ClearTextOnFocus = false,
                ZIndex = 3,
                Parent = frame,
            })
            corner(search, 8)
            stroke(search, THEME.BORDER, 0.9)
            search:GetPropertyChangedSignal("Text"):Connect(applyFilter)
            relayout()
        end
        applyFilter()
    end

    -- drag (header) - deltas cancel any client inset, so plain offset maths
    header.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local sx, sy = input.Position.X, input.Position.Y
        local px, py = frame.Position.X.Offset, frame.Position.Y.Offset
        HavocUI.startDrag(function(mx, my)
            local nx, ny = math.floor(px + (mx - sx)), math.floor(py + (my - sy))
            frame.Position = UDim2.fromOffset(nx, ny)
            glow.Position = UDim2.fromOffset(nx - 7, ny - 7)
        end)
    end)

    -- resize grip
    local grip = create("TextButton", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(1, -18, 1, -18),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = frame,
    })
    for i = 1, 2 do
        local bar = create("Frame", {
            Size = UDim2.fromOffset(7, 2),
            Position = UDim2.new(1, -2 - i * 5, 1, -2 - i * 5),
            AnchorPoint = Vector2.new(1, 1),
            BackgroundColor3 = THEME.TEXT_FAINT,
            BorderSizePixel = 0,
            Rotation = -45,
            ZIndex = 5,
            Parent = grip,
        })
        corner(bar, 1)
    end
    grip.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local sx, sy = input.Position.X, input.Position.Y
        local sw, sh = frame.Size.X.Offset, frame.Size.Y.Offset
        HavocUI.startDrag(function(mx, my)
            local w = math.clamp(math.floor(sw + (mx - sx)), 400, 1100)
            local h = math.clamp(math.floor(sh + (my - sy)), 320, 1100)
            frame.Size = UDim2.fromOffset(w, h)
            glow.Size = UDim2.fromOffset(w + 14, h + 14)
        end)
    end)

    -- popup layer (above everything inside the window)
    local popupLayer = create("Frame", {
        Name = "PopupLayer",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Active = false,
        ZIndex = (opts.zindex or 40) + 40,
        Parent = frame,
    })

    -- entry animation
    local targetPos = frame.Position
    local targetGlow = glow.Position
    frame.Position = targetPos + UDim2.fromOffset(0, 10)
    glow.Position = targetGlow + UDim2.fromOffset(0, 10)
    frame.GroupTransparency = 1
    glow.BackgroundTransparency = 1
    uiScale.Scale = scale * 0.97
    tween(frame, 0.22, { GroupTransparency = 0, Position = targetPos })
    tween(glow, 0.22, { BackgroundTransparency = 0.92, Position = targetGlow })
    tween(uiScale, 0.22, { Scale = scale })

    -- handle
    W.frame = frame
    W.header = header
    W.popupLayer = popupLayer
    W.tab = function(i) return pages[i] end
    W.setScale = function(s)
        uiScale.Scale = math.clamp(tonumber(s) or 1, 0.6, 1.6)
    end
    W.show = function()
        frame.Visible = true
        glow.Visible = true
    end
    W.hide = function()
        frame.Visible = false
        glow.Visible = false
    end
    W.toggle = function()
        if frame.Visible then W.hide() else W.show() end
    end
    W.isVisible = function() return frame.Visible end
    W.destroy = function()
        pcall(function() glow:Destroy() end)
        pcall(function() frame:Destroy() end)
    end
    return W
end

return HavocUI
