-- ==========================================================
-- NURHUB v1.3 | Delta Executor Compatible | без Drawing API
-- + Система ключей + вкладка Profile
-- ==========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ==========================================================
-- 0. ОЧИСТКА ПРИ ПОВТОРНОМ ЗАПУСКЕ + ТРЕКЕР СОЕДИНЕНИЙ
-- ==========================================================
local ENV = (getgenv and getgenv()) or _G
if ENV.NurHubCleanup then pcall(ENV.NurHubCleanup) end

local Conns = {}
local function track(conn)
    table.insert(Conns, conn)
    return conn
end

local function getGuiParent()
    local ok, result = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if ok and result then return result end
    return LocalPlayer:WaitForChild("PlayerGui")
end

ENV.NurHubCleanup = function()
    if ENV.NurHubSilentState then
        ENV.NurHubSilentState.Enabled = false
        ENV.NurHubSilentState.Target = nil
    end
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    Conns = {}
    pcall(function() RunService:UnbindFromRenderStep("NurHubLoop") end)
    local gp = getGuiParent()
    for _, n in ipairs({"NurHubGui", "NurHubESPGui", "NurHubKeyGui"}) do
        local g = gp:FindFirstChild(n)
        if g then g:Destroy() end
    end
    -- убираем остатки полёта
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if myHrp then
        for _, d in ipairs(myHrp:GetChildren()) do
            if d.Name == "NurHub_Fly" then d:Destroy() end
        end
    end
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
    if myHum then myHum.PlatformStand = false end
    -- убираем остатки ESP из персонажей
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            for _, d in ipairs(p.Character:GetChildren()) do
                if d.Name == "NurHub_ESP" or d.Name == "NurHub_Box3D" then d:Destroy() end
            end
            local head = p.Character:FindFirstChild("Head")
            local bb = head and head:FindFirstChild("NurHub_Billboard")
            if bb then bb:Destroy() end
        end
    end
end

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

-- ==========================================================
-- НАСТРОЙКИ
-- ==========================================================
local Config = {
    Visual = {
        ESP = false,            -- главный переключатель
        Outline = true,         -- контур (Highlight)
        ShowNickname = true,
        ShowDistance = true,
        Line = false,
        Box = false,
        Box3D = false,
        DistanceLimit = 500,
        Colors = {
            Outline  = Color3.fromRGB(255, 214, 10),
            Nickname = Color3.fromRGB(255, 255, 255),
            Distance = Color3.fromRGB(64, 200, 224),
            Line     = Color3.fromRGB(255, 69, 58),
            Box      = Color3.fromRGB(48, 209, 88),
            Box3D    = Color3.fromRGB(191, 90, 242),
        }
    },
    Combat = {
        Aimbot = false,
        AimbotFOV = 200,
        AimbotSmoothness = 0.2,   -- 0.01..1 (1 = мгновенно)
        Prediction = 0,           -- секунды упреждения
        HoldToAim = true,         -- ПК: зажать ПКМ. На телефоне всегда активен
        Sticky = true,            -- удерживать цель
        ShowFOV = true,
        SilentAim = false,
        SilentFOV = 150,
        HitChance = 100,
        ShowSilentFOV = true,
        TargetHead = true,
        TeamCheck = false,
        VisibleCheck = true,
        Colors = {
            AimbotFOV = Color3.fromRGB(255, 214, 10),
            SilentFOV = Color3.fromRGB(255, 69, 58),
        }
    },
    Player = {
        WalkSpeed = 16,
        JumpPower = 50,
        Noclip = false,
        Fly = false,
        FlySpeed = 50,
        ThirdPerson = false
    }
}

local espObjects = {}
local isMenuOpen = false
local flyBodyVelocity, flyBodyGyro

-- ==========================================================
-- 1. ТЕМА И ХЕЛПЕРЫ
-- ==========================================================

local THEME = {
    Bg = Color3.fromRGB(16, 16, 22),
    Side = Color3.fromRGB(20, 20, 28),
    Card = Color3.fromRGB(28, 28, 38),
    CardHover = Color3.fromRGB(35, 35, 48),
    Stroke = Color3.fromRGB(48, 48, 62),
    Text = Color3.fromRGB(240, 240, 248),
    Dim = Color3.fromRGB(142, 142, 160),
    Accent = Color3.fromRGB(255, 214, 10),
    Accent2 = Color3.fromRGB(255, 140, 0),
    Off = Color3.fromRGB(58, 58, 74),
}

local RED = Color3.fromRGB(255, 69, 58)
local GREEN = Color3.fromRGB(48, 209, 88)

local PALETTE = {
    Color3.fromRGB(255, 214, 10),
    Color3.fromRGB(255, 69, 58),
    Color3.fromRGB(48, 209, 88),
    Color3.fromRGB(64, 200, 224),
    Color3.fromRGB(10, 132, 255),
    Color3.fromRGB(191, 90, 242),
    Color3.fromRGB(255, 255, 255),
}

local function tween(obj, props, time, style, dir)
    local info = TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function accentGradient(parent, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(THEME.Accent, THEME.Accent2)
    g.Rotation = rotation or 0
    g.Parent = parent
    return g
end

local function makeLabel(parent, text, size, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = font or Enum.Font.Gotham
    l.Parent = parent
    return l
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    local state = {moved = false}

    track(handle.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            state.moved = false
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isMove(input) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then state.moved = true end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    return state
end

-- ==========================================================
-- 1.5 СИСТЕМА КЛЮЧЕЙ
--     Ключи и срок действия (в днях) задаются в таблице KEYS.
--     Время активации хранится в JSON-файле (writefile/readfile).
--     Срок отсчитывается с момента ПЕРВОЙ активации ключа.
-- ==========================================================

local KEYS = {
    ["OCTOBER"] = 7,     -- 7 дней
    ["MAGA761"] = 999,   -- 999 дней
}
local KEY_FILE = "NurHub_key.json"

-- Состояние лицензии. Active = true -> функции чита работают
local Lic = {
    Active = false,
    Key = nil,
    Days = 0,
    Activated = 0,
    Expires = 0,
    OnUnlock = nil,   -- вызывается после успешной активации (ставится ниже)
    OnLock = nil,     -- вызывается при блокировке (истёк срок / смена ключа)
}

-- Чтение данных: файл -> (запасной вариант) память executor'а
local function loadData()
    local data
    local ok, res = pcall(function()
        if isfile and readfile and isfile(KEY_FILE) then
            return HttpService:JSONDecode(readfile(KEY_FILE))
        end
    end)
    if ok and type(res) == "table" then
        data = res
    elseif type(ENV.NurHubKeyMem) == "table" then
        data = ENV.NurHubKeyMem
    end
    data = data or {}
    if type(data.used) ~= "table" then data.used = {} end
    return data
end

-- Запись данных: и в файл, и в память (если writefile недоступен)
local function saveData(data)
    ENV.NurHubKeyMem = data
    pcall(function()
        if writefile then
            writefile(KEY_FILE, HttpService:JSONEncode(data))
        end
    end)
end

-- Применить ключ к текущей сессии (срок считаем сами, файлу не доверяем слепо)
local function applyLicense(key, activated)
    Lic.Key = key
    Lic.Days = KEYS[key]
    Lic.Activated = activated
    Lic.Expires = activated + KEYS[key] * 86400
    Lic.Active = true
end

-- Проверка введённого ключа. Возвращает ok, сообщение
local function tryKey(input)
    local key = string.upper((tostring(input or ""):gsub("%s+", "")))
    if key == "" then return false, "Введите ключ" end

    local days = KEYS[key]
    if not days then return false, "Неверный ключ" end

    local data = loadData()
    local rec = data.used[key]
    local now = os.time()

    if type(rec) == "table" and type(rec.activated) == "number" then
        -- ключ уже активировали раньше: проверяем, не истёк ли он
        if rec.activated + days * 86400 <= now then
            return false, "Срок этого ключа уже истёк"
        end
    else
        -- первая активация
        rec = {activated = now}
    end

    rec.expires = rec.activated + days * 86400
    data.used[key] = rec
    data.current = key
    saveData(data)

    applyLicense(key, rec.activated)
    return true, "Ключ принят"
end

-- Форматирование оставшегося времени
function Lic.FormatLeft(sec)
    sec = math.max(0, math.floor(sec))
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    if d > 0 then return d .. " дн. " .. h .. " ч." end
    if h > 0 then return h .. " ч. " .. m .. " мин." end
    return m .. " мин. " .. (sec % 60) .. " сек."
end

local keyGui, keyAnimConn

-- Окно ввода ключа
-- presetKey: текст в поле, presetMsg/presetColor: статус, autoSubmit: сразу проверить
local function showKeyWindow(presetKey, presetMsg, presetColor, autoSubmit)
    if keyGui then keyGui:Destroy() keyGui = nil end
    if keyAnimConn then keyAnimConn:Disconnect() keyAnimConn = nil end

    local gui = Instance.new("ScreenGui")
    gui.Name = "NurHubKeyGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 50
    gui.Parent = getGuiParent()
    keyGui = gui

    -- затемнение фона (заодно блокирует клики под окном)
    local dim = Instance.new("Frame")
    dim.Size = UDim2.new(1, 0, 1, 0)
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.Active = true
    dim.Parent = gui
    tween(dim, {BackgroundTransparency = 0.4}, 0.5)

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(0, 380, 0, 280)
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Position = UDim2.new(0.5, 0, 0.5, 0)
    holder.BackgroundTransparency = 1
    holder.Parent = gui

    -- масштаб под размер экрана (телефон)
    local vp = Camera.ViewportSize
    local fit = math.max(math.min(1, (vp.X - 20) / 380, (vp.Y - 20) / 280), 0.4)
    local scale = Instance.new("UIScale")
    scale.Scale = fit * 0.8
    scale.Parent = holder

    local shadow = Instance.new("Frame")
    shadow.Size = UDim2.new(1, 20, 1, 20)
    shadow.Position = UDim2.new(0, -10, 0, -6)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 1
    shadow.BorderSizePixel = 0
    shadow.Parent = holder
    corner(shadow, 24)
    tween(shadow, {BackgroundTransparency = 0.6}, 0.5)

    local card = Instance.new("CanvasGroup")
    card.Size = UDim2.new(1, 0, 1, 0)
    card.BackgroundColor3 = THEME.Bg
    card.BorderSizePixel = 0
    card.GroupTransparency = 1
    card.Parent = holder
    corner(card, 16)
    addStroke(card, THEME.Stroke, 1)

    -- верхняя анимированная полоса
    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 3)
    topBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    topBar.BorderSizePixel = 0
    topBar.Parent = card
    local barGrad = Instance.new("UIGradient")
    barGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.Accent2),
        ColorSequenceKeypoint.new(0.5, THEME.Accent),
        ColorSequenceKeypoint.new(1, THEME.Accent2),
    })
    barGrad.Parent = topBar

    -- логотип (пульсирует)
    local logo = Instance.new("Frame")
    logo.Size = UDim2.new(0, 54, 0, 54)
    logo.AnchorPoint = Vector2.new(0.5, 0)
    logo.Position = UDim2.new(0.5, 0, 0, 22)
    logo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    logo.BorderSizePixel = 0
    logo.Parent = card
    corner(logo, 27)
    accentGradient(logo, 45)
    local logoScale = Instance.new("UIScale")
    logoScale.Parent = logo
    local logoText = makeLabel(logo, "N", 26, Color3.fromRGB(20, 20, 20), Enum.Font.GothamBlack)
    logoText.Size = UDim2.new(1, 0, 1, 0)

    local title = makeLabel(card, 'Nur<font color="rgb(255,214,10)">Hub</font>', 22, THEME.Text, Enum.Font.GothamBold)
    title.RichText = true
    title.Size = UDim2.new(1, 0, 0, 28)
    title.Position = UDim2.new(0, 0, 0, 84)

    local sub = makeLabel(card, "Активация ключа", 13, THEME.Dim, Enum.Font.Gotham)
    sub.Size = UDim2.new(1, 0, 0, 18)
    sub.Position = UDim2.new(0, 0, 0, 112)

    -- поле ввода
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -48, 0, 42)
    box.Position = UDim2.new(0, 24, 0, 142)
    box.BackgroundColor3 = THEME.Card
    box.BorderSizePixel = 0
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 15
    box.TextColor3 = THEME.Text
    box.PlaceholderText = "Введите ключ..."
    box.PlaceholderColor3 = THEME.Dim
    box.Text = presetKey or ""
    box.ClearTextOnFocus = false
    box.Parent = card
    corner(box, 10)
    local boxStroke = addStroke(box, THEME.Stroke, 1.5)

    track(box.Focused:Connect(function()
        tween(boxStroke, {Color = THEME.Accent}, 0.2)
    end))
    track(box.FocusLost:Connect(function()
        tween(boxStroke, {Color = THEME.Stroke}, 0.2)
    end))

    -- кнопка
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -48, 0, 42)
    btn.Position = UDim2.new(0, 24, 0, 194)
    btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    btn.BorderSizePixel = 0
    btn.Text = "Активировать"
    btn.TextSize = 15
    btn.TextColor3 = Color3.fromRGB(20, 20, 20)
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.Parent = card
    corner(btn, 10)
    accentGradient(btn, 0)
    local btnScale = Instance.new("UIScale")
    btnScale.Parent = btn

    track(btn.MouseEnter:Connect(function() tween(btnScale, {Scale = 1.03}, 0.15) end))
    track(btn.MouseLeave:Connect(function() tween(btnScale, {Scale = 1}, 0.15) end))
    track(btn.MouseButton1Down:Connect(function() tween(btnScale, {Scale = 0.96}, 0.1) end))
    track(btn.MouseButton1Up:Connect(function() tween(btnScale, {Scale = 1}, 0.2, Enum.EasingStyle.Back) end))

    -- статус
    local status = makeLabel(card, presetMsg or "", 13, presetColor or THEME.Dim, Enum.Font.GothamMedium)
    status.Size = UDim2.new(1, -40, 0, 20)
    status.Position = UDim2.new(0, 20, 0, 248)

    local function setStatus(text, color)
        status.Text = text
        status.TextTransparency = 1
        status.TextColor3 = color
        tween(status, {TextTransparency = 0}, 0.25)
    end

    -- плавное появление элементов по очереди
    local function slideIn(obj, delay)
        local p = obj.Position
        obj.Position = p + UDim2.fromOffset(0, 14)
        task.delay(delay, function()
            if obj.Parent then tween(obj, {Position = p}, 0.45) end
        end)
    end
    slideIn(title, 0.05)
    slideIn(sub, 0.1)
    slideIn(box, 0.15)
    slideIn(btn, 0.22)
    slideIn(status, 0.28)

    tween(scale, {Scale = fit}, 0.55, Enum.EasingStyle.Back)
    tween(card, {GroupTransparency = 0}, 0.35)

    -- постоянная анимация: бегущий градиент и пульс логотипа
    keyAnimConn = track(RunService.Heartbeat:Connect(function()
        local t = os.clock()
        barGrad.Offset = Vector2.new(math.sin(t * 1.5) * 0.5, 0)
        logoScale.Scale = 1 + 0.06 * math.sin(t * 3)
    end))

    -- тряска окна при ошибке
    local function shake()
        task.spawn(function()
            for _, dx in ipairs({-12, 12, -8, 8, -4, 0}) do
                tween(holder, {Position = UDim2.new(0.5, dx, 0.5, 0)}, 0.05, Enum.EasingStyle.Sine)
                task.wait(0.05)
            end
        end)
        tween(boxStroke, {Color = RED}, 0.1)
        task.delay(0.6, function()
            if boxStroke.Parent then tween(boxStroke, {Color = THEME.Stroke}, 0.3) end
        end)
    end

    -- плавное закрытие окна
    local function closeWindow(after)
        tween(card, {GroupTransparency = 1}, 0.4)
        tween(scale, {Scale = fit * 1.06}, 0.4)
        tween(dim, {BackgroundTransparency = 1}, 0.45)
        tween(shadow, {BackgroundTransparency = 1}, 0.4)
        task.delay(0.5, function()
            if keyAnimConn then keyAnimConn:Disconnect() keyAnimConn = nil end
            gui:Destroy()
            if keyGui == gui then keyGui = nil end
            if after then after() end
        end)
    end

    local busy = false
    local function submit()
        if busy then return end
        busy = true
        btn.Text = "Проверка..."
        setStatus("Проверка ключа...", THEME.Dim)
        task.wait(0.6) -- небольшая задержка для красоты

        local ok, msg = tryKey(box.Text)
        btn.Text = "Активировать"
        if ok then
            setStatus(msg .. "! Добро пожаловать", GREEN)
            task.wait(0.7)
            closeWindow(function()
                if Lic.OnUnlock then pcall(Lic.OnUnlock) end
            end)
        else
            setStatus(msg, RED)
            shake()
            busy = false
        end
    end

    track(btn.MouseButton1Click:Connect(submit))
    track(box.FocusLost:Connect(function(enter)
        if enter then submit() end
    end))

    -- найден сохранённый ключ -> проверяем автоматически
    if autoSubmit then
        task.delay(1.2, function()
            if gui.Parent and not busy then submit() end
        end)
    end
end

-- Блокировка чита (истёк срок)
function Lic.Lock(msg)
    Lic.Active = false
    if Lic.OnLock then pcall(Lic.OnLock) end
    showKeyWindow("", msg or "Введите ключ для активации", RED, false)
end

-- Смена ключа (кнопка в Profile)
function Lic.Logout()
    local data = loadData()
    data.current = nil
    saveData(data)
    Lic.Active = false
    Lic.Key = nil
    if Lic.OnLock then pcall(Lic.OnLock) end
    showKeyWindow("", "Введите новый ключ", THEME.Dim, false)
end

-- Запуск: смотрим, есть ли сохранённый ключ
function Lic.Start()
    local data = loadData()
    local key = data.current
    local rec = key and data.used[key]
    if type(key) == "string" and KEYS[key] and type(rec) == "table" and type(rec.activated) == "number" then
        if rec.activated + KEYS[key] * 86400 > os.time() then
            showKeyWindow(key, "Найден сохранённый ключ...", THEME.Dim, true)
        else
            showKeyWindow("", "Срок ключа " .. key .. " истёк. Введите новый", RED, false)
        end
    else
        showKeyWindow("", "Введите ключ для активации", THEME.Dim, false)
    end
end

-- Раз в секунду проверяем, не закончился ли срок
do
    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        if Lic.Active and os.time() >= Lic.Expires then
            Lic.Lock("Срок действия ключа истёк. Введите новый")
        end
    end))
end

-- ==========================================================
-- 2. ИНТЕРФЕЙС
-- ==========================================================

local layoutCounter = 0
local function nextOrder()
    layoutCounter = layoutCounter + 1
    return layoutCounter
end

local function createSlider(parent, y, label, tbl, key, minV, maxV, onChange, scroller)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -28, 0, 38)
    row.Position = UDim2.new(0, 14, 0, y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = makeLabel(row, label, 13, THEME.Dim, Enum.Font.Gotham)
    lbl.Size = UDim2.new(0.65, 0, 0, 18)
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local valLbl = makeLabel(row, tostring(tbl[key]), 13, THEME.Accent, Enum.Font.GothamBold)
    valLbl.Size = UDim2.new(0.35, 0, 0, 18)
    valLbl.Position = UDim2.new(0.65, 0, 0, 0)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right

    local track_ = Instance.new("Frame")
    track_.Size = UDim2.new(1, 0, 0, 6)
    track_.Position = UDim2.new(0, 0, 0, 27)
    track_.BackgroundColor3 = THEME.Off
    track_.BorderSizePixel = 0
    track_.Parent = row
    corner(track_, 3)

    local pct = math.clamp((tbl[key] - minV) / (maxV - minV), 0, 1)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track_
    corner(fill, 3)
    accentGradient(fill, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(pct, -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track_
    corner(knob, 7)
    addStroke(knob, THEME.Accent, 2)

    local knobScale = Instance.new("UIScale")
    knobScale.Parent = knob

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 0, 26)
    hit.Position = UDim2.new(0, 0, 0, 16)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.ZIndex = 2
    hit.Parent = row

    local dragging = false

    local function updateFromX(x)
        local p = math.clamp((x - track_.AbsolutePosition.X) / track_.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, -7, 0.5, -7)
        local val = math.floor(minV + (maxV - minV) * p + 0.5)
        tbl[key] = val
        valLbl.Text = tostring(val)
        if onChange then onChange(val) end
    end

    track(hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            if scroller then scroller.ScrollingEnabled = false end
            tween(knobScale, {Scale = 1.3}, 0.15)
            updateFromX(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if scroller then scroller.ScrollingEnabled = true end
            tween(knobScale, {Scale = 1}, 0.2)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isMove(input) then
            updateFromX(input.Position.X)
        end
    end))
end

local function createSection(parent, text)
    local l = makeLabel(parent, text, 12, THEME.Dim, Enum.Font.GothamBold)
    l.Size = UDim2.new(1, 0, 0, 20)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = nextOrder()
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.Parent = l
    return l
end

-- opts: {sliders = {{label, tbl, key, min, max, onChange}},
--        palettes = {{tbl = <таблица>, key = "<ключ цвета>"}}, onChange = fn}
local function createToggleCard(parent, title, tbl, key, opts)
    opts = opts or {}
    local sliders = opts.sliders or {}
    local palettes = opts.palettes or {}
    local bodyH = #sliders * 44 + #palettes * 40
    local hasBody = bodyH > 0
    local HEAD = 42

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, HEAD)
    card.BackgroundColor3 = THEME.Card
    card.ClipsDescendants = true
    card.LayoutOrder = nextOrder()
    card.Parent = parent
    corner(card, 10)
    addStroke(card, THEME.Stroke, 1)

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, HEAD)
    head.BackgroundTransparency = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.Parent = card

    local titleLbl = makeLabel(head, title, 14, THEME.Text, Enum.Font.GothamMedium)
    titleLbl.Size = UDim2.new(1, -110, 1, 0)
    titleLbl.Position = UDim2.new(0, 14, 0, 0)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    local chevron
    if hasBody then
        chevron = makeLabel(head, "›", 22, THEME.Dim, Enum.Font.GothamBold)
        chevron.Size = UDim2.new(0, 20, 1, 0)
        chevron.Position = UDim2.new(1, -84, 0, 0)
    end

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 42, 0, 22)
    toggle.Position = UDim2.new(1, -54, 0.5, -11)
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = head
    corner(toggle, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = toggle
    corner(knob, 8)

    local function paint(animate)
        local on = tbl[key]
        local t = animate and 0.22 or 0
        tween(toggle, {BackgroundColor3 = on and THEME.Accent or THEME.Off}, t)
        tween(knob, {Position = on and UDim2.new(0, 23, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}, t, Enum.EasingStyle.Back)
    end
    paint(false)

    toggle.MouseButton1Click:Connect(function()
        tbl[key] = not tbl[key]
        paint(true)
        if opts.onChange then opts.onChange(tbl[key]) end
    end)

    head.MouseEnter:Connect(function() tween(card, {BackgroundColor3 = THEME.CardHover}, 0.15) end)
    head.MouseLeave:Connect(function() tween(card, {BackgroundColor3 = THEME.Card}, 0.15) end)

    if hasBody then
        local body = Instance.new("Frame")
        body.Size = UDim2.new(1, 0, 0, bodyH)
        body.Position = UDim2.new(0, 0, 0, HEAD)
        body.BackgroundTransparency = 1
        body.Parent = card

        local y = 0
        for _, s in ipairs(sliders) do
            createSlider(body, y, s.label, s.tbl, s.key, s.min, s.max, s.onChange, parent)
            y = y + 44
        end

        for _, pal in ipairs(palettes) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -28, 0, 32)
            row.Position = UDim2.new(0, 14, 0, y + 4)
            row.BackgroundTransparency = 1
            row.Parent = body
            y = y + 40

            local list = Instance.new("UIListLayout")
            list.FillDirection = Enum.FillDirection.Horizontal
            list.Padding = UDim.new(0, 8)
            list.VerticalAlignment = Enum.VerticalAlignment.Center
            list.Parent = row

            local swatches = {}
            local function refreshRings()
                for _, sw in ipairs(swatches) do
                    tween(sw.ring, {Transparency = (sw.color == pal.tbl[pal.key]) and 0 or 1}, 0.2)
                end
            end

            for _, col in ipairs(PALETTE) do
                local sw = Instance.new("TextButton")
                sw.Size = UDim2.new(0, 24, 0, 24)
                sw.BackgroundColor3 = col
                sw.Text = ""
                sw.AutoButtonColor = false
                sw.Parent = row
                corner(sw, 12)

                local ring = addStroke(sw, Color3.fromRGB(255, 255, 255), 2,
                    (col == pal.tbl[pal.key]) and 0 or 1)
                table.insert(swatches, {color = col, ring = ring})

                sw.MouseButton1Click:Connect(function()
                    pal.tbl[pal.key] = col
                    refreshRings()
                end)
            end
        end

        local open = false
        head.MouseButton1Click:Connect(function()
            open = not open
            tween(card, {Size = UDim2.new(1, 0, 0, open and (HEAD + bodyH + 6) or HEAD)}, 0.32)
            if chevron then
                tween(chevron, {Rotation = open and 90 or 0, TextColor3 = open and THEME.Accent or THEME.Dim}, 0.25)
            end
        end)
    end

    return card
end

local function createSliderCard(parent, label, tbl, key, minV, maxV, onChange)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = THEME.Card
    card.LayoutOrder = nextOrder()
    card.Parent = parent
    corner(card, 10)
    addStroke(card, THEME.Stroke, 1)
    createSlider(card, 9, label, tbl, key, minV, maxV, onChange, parent)
    return card
end

local function createGUI()
    local guiParent = getGuiParent()
    local old = guiParent:FindFirstChild("NurHubGui")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NurHubGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 10
    screenGui.Parent = guiParent

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.Size = UDim2.new(0, 460, 0, 310)
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.new(0.5, 0, 0.5, 0)
    root.BackgroundTransparency = 1
    root.Visible = false
    root.Parent = screenGui

    local rootScale = Instance.new("UIScale")
    rootScale.Parent = root

    local shadow = Instance.new("Frame")
    shadow.Size = UDim2.new(1, 20, 1, 20)
    shadow.Position = UDim2.new(0, -10, 0, -6)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.65
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = root
    corner(shadow, 22)

    local window = Instance.new("CanvasGroup")
    window.Name = "Window"
    window.Size = UDim2.new(1, 0, 1, 0)
    window.BackgroundColor3 = THEME.Bg
    window.BorderSizePixel = 0
    window.ZIndex = 1
    window.Parent = root
    corner(window, 14)
    addStroke(window, THEME.Stroke, 1)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = THEME.Side
    header.BorderSizePixel = 0
    header.Parent = window

    local headerLine = Instance.new("Frame")
    headerLine.Size = UDim2.new(1, 0, 0, 1)
    headerLine.Position = UDim2.new(0, 0, 1, -1)
    headerLine.BackgroundColor3 = THEME.Stroke
    headerLine.BorderSizePixel = 0
    headerLine.Parent = header

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(0, 16, 0.5, -4)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel = 0
    dot.Parent = header
    corner(dot, 4)
    accentGradient(dot, 45)

    local title = makeLabel(header, 'Nur<font color="rgb(255,214,10)">Hub</font>', 18, THEME.Text, Enum.Font.GothamBold)
    title.RichText = true
    title.Size = UDim2.new(0, 80, 1, 0)
    title.Position = UDim2.new(0, 32, 0, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left

    local ver = makeLabel(header, "v1.3", 12, THEME.Dim, Enum.Font.Gotham)
    ver.Size = UDim2.new(0, 40, 1, 0)
    ver.Position = UDim2.new(0, 104, 0, 1)
    ver.TextXAlignment = Enum.TextXAlignment.Left

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -15)
    closeBtn.BackgroundColor3 = THEME.Card
    closeBtn.Text = "×"
    closeBtn.TextSize = 22
    closeBtn.TextColor3 = THEME.Dim
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = header
    corner(closeBtn, 8)

    closeBtn.MouseEnter:Connect(function()
        tween(closeBtn, {BackgroundColor3 = Color3.fromRGB(255, 69, 58), TextColor3 = Color3.fromRGB(255, 255, 255)}, 0.15)
    end)
    closeBtn.MouseLeave:Connect(function()
        tween(closeBtn, {BackgroundColor3 = THEME.Card, TextColor3 = THEME.Dim}, 0.15)
    end)

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 118, 1, -44)
    sidebar.Position = UDim2.new(0, 0, 0, 44)
    sidebar.BackgroundColor3 = THEME.Side
    sidebar.BorderSizePixel = 0
    sidebar.Parent = window

    local sideLine = Instance.new("Frame")
    sideLine.Size = UDim2.new(0, 1, 1, 0)
    sideLine.Position = UDim2.new(1, -1, 0, 0)
    sideLine.BackgroundColor3 = THEME.Stroke
    sideLine.BorderSizePixel = 0
    sideLine.Parent = sidebar

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 3, 0, 18)
    indicator.Position = UDim2.new(0, 2, 0, 19)
    indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    indicator.BorderSizePixel = 0
    indicator.Parent = sidebar
    corner(indicator, 2)
    accentGradient(indicator, 90)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -118, 1, -44)
    content.Position = UDim2.new(0, 118, 0, 44)
    content.BackgroundTransparency = 1
    content.Parent = window

    local pages, tabButtons, tabIndex = {}, {}, {}

    local function createPage(name)
        local page = Instance.new("CanvasGroup")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.Parent = content

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 3
        scroll.ScrollBarImageColor3 = THEME.Accent
        scroll.ScrollingDirection = Enum.ScrollingDirection.Y
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Parent = page

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = scroll

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 14)
        pad.Parent = scroll

        pages[name] = page
        return scroll
    end

    local tabNames = {"Visual", "Combat", "Player", "Profile"}
    local currentTab

    -- Обновление данных вкладки Profile (реализация ниже, после создания страницы)
    local refreshProfile = function() end

    local function selectTab(name, animate)
        if currentTab == name then return end
        currentTab = name
        local t = animate and 0.25 or 0

        for n, b in pairs(tabButtons) do
            local sel = (n == name)
            tween(b, {BackgroundTransparency = sel and 0.88 or 1, TextColor3 = sel and THEME.Accent or THEME.Dim}, t)
        end
        tween(indicator, {Position = UDim2.new(0, 2, 0, 10 + (tabIndex[name] - 1) * 42 + 9)}, t, Enum.EasingStyle.Back)

        for n, p in pairs(pages) do
            if n == name then
                p.Visible = true
                if animate then
                    p.GroupTransparency = 1
                    p.Position = UDim2.new(0, 0, 0, 14)
                    tween(p, {GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0)}, 0.3)
                else
                    p.GroupTransparency = 0
                    p.Position = UDim2.new(0, 0, 0, 0)
                end
            else
                p.Visible = false
            end
        end

        if name == "Profile" then refreshProfile() end
    end

    for i, name in ipairs(tabNames) do
        tabIndex[name] = i

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -18, 0, 36)
        btn.Position = UDim2.new(0, 10, 0, 10 + (i - 1) * 42)
        btn.BackgroundColor3 = THEME.Accent
        btn.BackgroundTransparency = 1
        btn.Text = name
        btn.TextSize = 14
        btn.TextColor3 = THEME.Dim
        btn.Font = Enum.Font.GothamMedium
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.AutoButtonColor = false
        btn.Parent = sidebar
        corner(btn, 8)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 14)
        pad.Parent = btn

        tabButtons[name] = btn
        btn.MouseButton1Click:Connect(function() selectTab(name, true) end)
    end

    -- ===== Страница Visual =====
    local V = Config.Visual
    local vis = createPage("Visual")
    createSection(vis, "ESP")
    createToggleCard(vis, "ESP (включить всё)", V, "ESP", {
        sliders = {
            {label = "Дистанция ESP", tbl = V, key = "DistanceLimit", min = 50, max = 2000}
        }
    })
    createSection(vis, "Элементы ESP")
    createToggleCard(vis, "Контур (Outline)", V, "Outline",
        {palettes = {{tbl = V.Colors, key = "Outline"}}})
    createToggleCard(vis, "Show Nickname", V, "ShowNickname",
        {palettes = {{tbl = V.Colors, key = "Nickname"}}})
    createToggleCard(vis, "Show Distance", V, "ShowDistance",
        {palettes = {{tbl = V.Colors, key = "Distance"}}})
    createToggleCard(vis, "Line", V, "Line",
        {palettes = {{tbl = V.Colors, key = "Line"}}})
    createToggleCard(vis, "Box", V, "Box",
        {palettes = {{tbl = V.Colors, key = "Box"}}})
    createToggleCard(vis, "3D Box", V, "Box3D",
        {palettes = {{tbl = V.Colors, key = "Box3D"}}})

    -- ===== Страница Combat =====
    local com = createPage("Combat")
    local CB = Config.Combat
    local smoothProxy = {v = math.floor(CB.AimbotSmoothness * 100 + 0.5)}
    local predProxy = {v = math.floor(CB.Prediction * 100 + 0.5)}

    createSection(com, "Aimbot")
    createToggleCard(com, "Aimbot", CB, "Aimbot", {
        sliders = {
            {label = "FOV", tbl = CB, key = "AimbotFOV", min = 30, max = 500},
            {label = "Скорость наводки %", tbl = smoothProxy, key = "v", min = 1, max = 100,
                onChange = function(v) CB.AimbotSmoothness = v / 100 end},
            {label = "Упреждение (сотые сек)", tbl = predProxy, key = "v", min = 0, max = 30,
                onChange = function(v) CB.Prediction = v / 100 end},
        }
    })
    createToggleCard(com, "FOV circle (Aimbot)", CB, "ShowFOV",
        {palettes = {{tbl = CB.Colors, key = "AimbotFOV"}}})
    createToggleCard(com, "Зажим ПКМ (только ПК)", CB, "HoldToAim")
    createToggleCard(com, "Sticky lock", CB, "Sticky")

    createSection(com, "Silent Aim")
    createToggleCard(com, "Silent Aim", CB, "SilentAim", {
        sliders = {
            {label = "FOV", tbl = CB, key = "SilentFOV", min = 30, max = 500},
            {label = "Hit chance %", tbl = CB, key = "HitChance", min = 1, max = 100},
        }
    })
    createToggleCard(com, "FOV circle (Silent)", CB, "ShowSilentFOV",
        {palettes = {{tbl = CB.Colors, key = "SilentFOV"}}})

    createSection(com, "Общие")
    createToggleCard(com, "Цель: голова", CB, "TargetHead")
    createToggleCard(com, "Team check", CB, "TeamCheck")
    createToggleCard(com, "Проверка видимости", CB, "VisibleCheck")

    -- ===== Страница Player =====
    local plr = createPage("Player")
    createSection(plr, "Движение")
    createSliderCard(plr, "WalkSpeed", Config.Player, "WalkSpeed", 16, 200)
    createSliderCard(plr, "JumpPower", Config.Player, "JumpPower", 50, 300)
    createToggleCard(plr, "Noclip", Config.Player, "Noclip")
    createToggleCard(plr, "Fly", Config.Player, "Fly", {
        sliders = {
            {label = "Скорость полёта", tbl = Config.Player, key = "FlySpeed", min = 10, max = 200}
        }
    })
    createSection(plr, "Камера")
    createToggleCard(plr, "Third Person", Config.Player, "ThirdPerson", {
        onChange = function(on)
            if on then
                LocalPlayer.CameraMode = Enum.CameraMode.Classic
                LocalPlayer.CameraMaxZoomDistance = 128
                LocalPlayer.CameraMinZoomDistance = 0.5
            else
                LocalPlayer.CameraMaxZoomDistance = 0.5
            end
        end
    })

    -- ===== Страница Profile =====
    local prof = createPage("Profile")
    createSection(prof, "Игрок")

    -- Карточка игрока: аватарка + ник
    local pCard = Instance.new("Frame")
    pCard.Size = UDim2.new(1, 0, 0, 96)
    pCard.BackgroundColor3 = THEME.Card
    pCard.LayoutOrder = nextOrder()
    pCard.Parent = prof
    corner(pCard, 10)
    addStroke(pCard, THEME.Stroke, 1)

    -- вращающееся градиентное кольцо вокруг аватарки
    local ring = Instance.new("Frame")
    ring.Size = UDim2.new(0, 68, 0, 68)
    ring.Position = UDim2.new(0, 14, 0, 14)
    ring.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ring.BorderSizePixel = 0
    ring.Parent = pCard
    corner(ring, 34)
    local ringGrad = accentGradient(ring, 0)

    local avatar = Instance.new("ImageLabel")
    avatar.Size = UDim2.new(0, 62, 0, 62)
    avatar.Position = UDim2.new(0, 3, 0, 3)
    avatar.BackgroundColor3 = THEME.Bg
    avatar.BorderSizePixel = 0
    avatar.ImageTransparency = 1
    avatar.Parent = ring
    corner(avatar, 31)

    -- загрузка headshot по UserId (в отдельном потоке, чтобы не зависать)
    task.spawn(function()
        local ok, img = pcall(function()
            return Players:GetUserThumbnailAsync(
                LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        end)
        if not (ok and img) then
            img = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"
        end
        avatar.Image = img
        tween(avatar, {ImageTransparency = 0}, 0.5)
    end)

    local nameLbl = makeLabel(pCard, LocalPlayer.DisplayName, 17, THEME.Text, Enum.Font.GothamBold)
    nameLbl.Size = UDim2.new(1, -106, 0, 24)
    nameLbl.Position = UDim2.new(0, 94, 0, 14)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    local userLbl = makeLabel(pCard, "@" .. LocalPlayer.Name, 13, THEME.Dim, Enum.Font.Gotham)
    userLbl.Size = UDim2.new(1, -106, 0, 18)
    userLbl.Position = UDim2.new(0, 94, 0, 39)
    userLbl.TextXAlignment = Enum.TextXAlignment.Left
    userLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- плашка статуса
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 78, 0, 20)
    pill.Position = UDim2.new(0, 94, 0, 62)
    pill.BackgroundColor3 = GREEN
    pill.BackgroundTransparency = 0.8
    pill.BorderSizePixel = 0
    pill.Parent = pCard
    corner(pill, 10)
    local pillLbl = makeLabel(pill, "АКТИВЕН", 11, GREEN, Enum.Font.GothamBold)
    pillLbl.Size = UDim2.new(1, 0, 1, 0)

    createSection(prof, "Лицензия")

    -- Вспомогательная функция: карточка "название — значение"
    local function infoCard(titleText, h)
        local c = Instance.new("Frame")
        c.Size = UDim2.new(1, 0, 0, h or 44)
        c.BackgroundColor3 = THEME.Card
        c.LayoutOrder = nextOrder()
        c.Parent = prof
        corner(c, 10)
        addStroke(c, THEME.Stroke, 1)

        local t = makeLabel(c, titleText, 13, THEME.Dim, Enum.Font.Gotham)
        t.Size = UDim2.new(0.5, 0, 0, 44)
        t.Position = UDim2.new(0, 14, 0, 0)
        t.TextXAlignment = Enum.TextXAlignment.Left

        local v = makeLabel(c, "—", 14, THEME.Accent, Enum.Font.GothamBold)
        v.Size = UDim2.new(0.5, -14, 0, 44)
        v.Position = UDim2.new(0.5, 0, 0, 0)
        v.TextXAlignment = Enum.TextXAlignment.Right
        return c, v
    end

    local _, keyVal = infoCard("Активный ключ")
    local _, durVal = infoCard("Срок ключа")
    local leftCard, leftVal = infoCard("Осталось", 64)
    local _, untilVal = infoCard("Действует до")

    -- полоса прогресса оставшегося времени
    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -28, 0, 6)
    barBg.Position = UDim2.new(0, 14, 0, 46)
    barBg.BackgroundColor3 = THEME.Off
    barBg.BorderSizePixel = 0
    barBg.Parent = leftCard
    corner(barBg, 3)

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    corner(barFill, 3)
    local barFillGrad = accentGradient(barFill, 0)

    -- Кнопка смены ключа
    local swapBtn = Instance.new("TextButton")
    swapBtn.Size = UDim2.new(1, 0, 0, 38)
    swapBtn.BackgroundColor3 = THEME.Card
    swapBtn.Text = "Сменить ключ"
    swapBtn.TextSize = 14
    swapBtn.TextColor3 = THEME.Dim
    swapBtn.Font = Enum.Font.GothamMedium
    swapBtn.AutoButtonColor = false
    swapBtn.LayoutOrder = nextOrder()
    swapBtn.Parent = prof
    corner(swapBtn, 10)
    addStroke(swapBtn, THEME.Stroke, 1)
    swapBtn.MouseEnter:Connect(function()
        tween(swapBtn, {BackgroundColor3 = THEME.CardHover, TextColor3 = THEME.Text}, 0.15)
    end)
    swapBtn.MouseLeave:Connect(function()
        tween(swapBtn, {BackgroundColor3 = THEME.Card, TextColor3 = THEME.Dim}, 0.15)
    end)
    swapBtn.MouseButton1Click:Connect(function() Lic.Logout() end)

    -- Обновление всех значений профиля
    refreshProfile = function()
        keyVal.Text = Lic.Key or "—"
        durVal.Text = Lic.Days > 0 and (Lic.Days .. " дн.") or "—"

        local rem = math.max(0, Lic.Expires - os.time())
        leftVal.Text = Lic.FormatLeft(rem)
        untilVal.Text = Lic.Expires > 0 and os.date("%d.%m.%Y %H:%M", Lic.Expires) or "—"

        local total = math.max(1, Lic.Days * 86400)
        barFill.Size = UDim2.new(math.clamp(rem / total, 0, 1), 0, 1, 0)
        -- меньше суток — полоса краснеет
        if rem < 86400 then
            barFillGrad.Color = ColorSequence.new(RED, THEME.Accent2)
            leftVal.TextColor3 = RED
        else
            barFillGrad.Color = ColorSequence.new(THEME.Accent, THEME.Accent2)
            leftVal.TextColor3 = THEME.Accent
        end
    end

    -- Анимация кольца + обновление раз в секунду (только когда вкладка видна)
    do
        local acc = 0
        track(RunService.Heartbeat:Connect(function(dt)
            if not (isMenuOpen and pages.Profile.Visible) then return end
            ringGrad.Rotation = (os.clock() * 120) % 360
            acc = acc + dt
            if acc >= 1 then
                acc = 0
                refreshProfile()
            end
        end))
    end

    selectTab("Visual", false)

    -- ===== Кнопка-лаунчер =====
    local launcher = Instance.new("TextButton")
    launcher.Name = "Launcher"
    launcher.Size = UDim2.new(0, 48, 0, 48)
    launcher.Position = UDim2.new(0.06, 0, 0.5, 0)
    launcher.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    launcher.Text = "N"
    launcher.TextSize = 24
    launcher.TextColor3 = Color3.fromRGB(20, 20, 20)
    launcher.Font = Enum.Font.GothamBlack
    launcher.AutoButtonColor = false
    launcher.Parent = screenGui
    corner(launcher, 24)
    accentGradient(launcher, 45)
    addStroke(launcher, Color3.fromRGB(255, 255, 255), 2, 0.6)

    local launcherScale = Instance.new("UIScale")
    launcherScale.Parent = launcher

    launcher.MouseEnter:Connect(function() tween(launcherScale, {Scale = 1.1}, 0.15) end)
    launcher.MouseLeave:Connect(function() tween(launcherScale, {Scale = 1}, 0.15) end)
    launcher.MouseButton1Down:Connect(function() tween(launcherScale, {Scale = 0.92}, 0.1) end)
    launcher.MouseButton1Up:Connect(function() tween(launcherScale, {Scale = 1}, 0.15, Enum.EasingStyle.Back) end)

    local launcherDrag = makeDraggable(launcher, launcher)
    makeDraggable(header, root)

    local function setMenu(open)
        -- без активного ключа меню открыть нельзя
        if open and not Lic.Active then return end
        isMenuOpen = open
        if open then
            local vp = Camera.ViewportSize
            local fit = math.min(1, (vp.X - 20) / 460, (vp.Y - 20) / 310)
            fit = math.max(fit, 0.4)

            root.Visible = true
            rootScale.Scale = fit * 0.85
            window.GroupTransparency = 1
            shadow.BackgroundTransparency = 1

            tween(rootScale, {Scale = fit}, 0.4, Enum.EasingStyle.Back)
            tween(window, {GroupTransparency = 0}, 0.25)
            tween(shadow, {BackgroundTransparency = 0.65}, 0.35)
        else
            tween(rootScale, {Scale = rootScale.Scale * 0.92}, 0.2)
            tween(window, {GroupTransparency = 1}, 0.2)
            tween(shadow, {BackgroundTransparency = 1}, 0.2)
            task.delay(0.22, function()
                if not isMenuOpen then root.Visible = false end
            end)
        end
    end

    launcher.MouseButton1Click:Connect(function()
        if launcherDrag.moved then launcherDrag.moved = false return end
        setMenu(not isMenuOpen)
    end)
    closeBtn.MouseButton1Click:Connect(function() setMenu(false) end)

    track(UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            setMenu(not isMenuOpen)
        end
    end))

    return {
        gui = screenGui,
        setMenu = setMenu,
        refreshProfile = function() refreshProfile() end,
    }
end

local UI = createGUI()
UI.gui.Enabled = false -- меню скрыто, пока не введён верный ключ

-- Ключ принят -> показываем меню (окно ключа к этому моменту уже плавно закрылось)
Lic.OnUnlock = function()
    UI.gui.Enabled = true
    UI.refreshProfile()
    UI.setMenu(true)
end

-- Срок истёк / смена ключа -> прячем меню
Lic.OnLock = function()
    UI.setMenu(false)
    UI.gui.Enabled = false
end

-- ==========================================================
-- 3. ВИЗУАЛЬНАЯ ЧАСТЬ (ESP без Drawing)
--    Outline  -> Highlight
--    Nick/Dist-> BillboardGui
--    3D Box   -> SelectionBox
--    Box/Line -> Frame'ы на отдельном ScreenGui
-- ==========================================================

local espGui = Instance.new("ScreenGui")
espGui.Name = "NurHubESPGui"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.DisplayOrder = 1
espGui.Parent = getGuiParent()

local function clearESP(player)
    local obj = espObjects[player]
    if obj then
        for _, k in ipairs({"Highlight", "Billboard", "Selection", "BoxFrame", "LineFrame"}) do
            if obj[k] then pcall(function() obj[k]:Destroy() end) end
        end
        espObjects[player] = nil
    end
end

local function createESP(player, char, head)
    local highlight = Instance.new("Highlight")
    highlight.Name = "NurHub_ESP"
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = char
    highlight.Enabled = false
    highlight.Parent = char

    local selection = Instance.new("SelectionBox")
    selection.Name = "NurHub_Box3D"
    selection.LineThickness = 0.04
    selection.SurfaceTransparency = 1
    selection.Adornee = nil
    selection.Parent = char

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NurHub_Billboard"
    billboard.Size = UDim2.new(0, 200, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = false
    billboard.Parent = head

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = billboard

    local nickname = Instance.new("TextLabel")
    nickname.Name = "Nickname"
    nickname.Size = UDim2.new(1, 0, 0, 20)
    nickname.LayoutOrder = 1
    nickname.BackgroundTransparency = 1
    nickname.Text = player.DisplayName
    nickname.TextStrokeTransparency = 0
    nickname.Font = Enum.Font.GothamBold
    nickname.TextSize = 14
    nickname.Parent = billboard

    local distance = Instance.new("TextLabel")
    distance.Name = "Distance"
    distance.Size = UDim2.new(1, 0, 0, 20)
    distance.LayoutOrder = 2
    distance.BackgroundTransparency = 1
    distance.TextStrokeTransparency = 0
    distance.Font = Enum.Font.Gotham
    distance.TextSize = 13
    distance.Parent = billboard

    -- 2D Box
    local boxFrame = Instance.new("Frame")
    boxFrame.BackgroundTransparency = 1
    boxFrame.BorderSizePixel = 0
    boxFrame.Visible = false
    boxFrame.Parent = espGui
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 1.5
    boxStroke.Parent = boxFrame

    -- Line
    local lineFrame = Instance.new("Frame")
    lineFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    lineFrame.BorderSizePixel = 0
    lineFrame.Visible = false
    lineFrame.Parent = espGui

    local obj = {
        Char = char, Highlight = highlight, Selection = selection,
        Billboard = billboard, Nickname = nickname, Distance = distance,
        BoxFrame = boxFrame, BoxStroke = boxStroke, LineFrame = lineFrame,
    }
    espObjects[player] = obj
    return obj
end

local function hideAll(obj)
    obj.Highlight.Enabled = false
    obj.Billboard.Enabled = false
    obj.Selection.Adornee = nil
    obj.BoxFrame.Visible = false
    obj.LineFrame.Visible = false
end

local function updateESP()
    local V = Config.Visual
    local C = V.Colors
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local vp = Camera.ViewportSize

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local obj = espObjects[player]

            if not (hrp and head and hum) then
                if obj then clearESP(player) end
            else
                if obj and (obj.Char ~= char or not obj.Highlight.Parent or not obj.Billboard.Parent) then
                    clearESP(player)
                    obj = nil
                end
                if not obj then obj = createESP(player, char, head) end

                local origin = myHrp and myHrp.Position or Camera.CFrame.Position
                local dist = (hrp.Position - origin).Magnitude
                local show = V.ESP and hum.Health > 0 and dist <= V.DistanceLimit

                if not show then
                    hideAll(obj)
                else
                    -- Outline
                    obj.Highlight.Enabled = V.Outline
                    obj.Highlight.OutlineColor = C.Outline

                    -- Nickname / Distance
                    obj.Billboard.Enabled = V.ShowNickname or V.ShowDistance
                    obj.Nickname.Visible = V.ShowNickname
                    obj.Nickname.TextColor3 = C.Nickname
                    obj.Distance.Visible = V.ShowDistance
                    obj.Distance.TextColor3 = C.Distance
                    if V.ShowDistance then
                        obj.Distance.Text = math.floor(dist) .. " studs"
                    end

                    -- 3D Box
                    if V.Box3D then
                        obj.Selection.Color3 = C.Box3D
                        obj.Selection.Adornee = char
                    else
                        obj.Selection.Adornee = nil
                    end

                    -- 2D Box + Line (проекция bounding box на экран)
                    local boxOn, lineOn = false, false
                    if V.Box or V.Line then
                        local cf, size = char:GetBoundingBox()
                        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                        local allFront = true
                        for i = 0, 7 do
                            local sx = (i % 2 == 0) and 1 or -1
                            local sy = (math.floor(i / 2) % 2 == 0) and 1 or -1
                            local sz = (math.floor(i / 4) % 2 == 0) and 1 or -1
                            local wp = (cf * CFrame.new(size.X / 2 * sx, size.Y / 2 * sy, size.Z / 2 * sz)).Position
                            local p = Camera:WorldToViewportPoint(wp)
                            if p.Z <= 0 then allFront = false break end
                            minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
                            minY = math.min(minY, p.Y); maxY = math.max(maxY, p.Y)
                        end

                        if allFront then
                            if V.Box then
                                boxOn = true
                                obj.BoxFrame.Position = UDim2.fromOffset(minX, minY)
                                obj.BoxFrame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
                                obj.BoxStroke.Color = C.Box
                            end
                            if V.Line then
                                lineOn = true
                                local a = Vector2.new(vp.X / 2, vp.Y)
                                local b = Vector2.new((minX + maxX) / 2, maxY)
                                local d = b - a
                                obj.LineFrame.BackgroundColor3 = C.Line
                                obj.LineFrame.Size = UDim2.fromOffset(d.Magnitude, 2)
                                obj.LineFrame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                                obj.LineFrame.Rotation = math.deg(math.atan2(d.Y, d.X))
                            end
                        end
                    end
                    obj.BoxFrame.Visible = boxOn
                    obj.LineFrame.Visible = lineOn
                end
            end
        end
    end
end

-- ==========================================================
-- 4. БОЕВАЯ ЧАСТЬ (COMBAT)
-- ==========================================================

local AimState = {Aiming = false, Locked = nil}

-- Состояние для silent aim (хуки ставятся один раз, состояние живёт в ENV)
local SilentState = ENV.NurHubSilentState or {}
ENV.NurHubSilentState = SilentState
SilentState.Mouse = LocalPlayer:GetMouse()
SilentState.Enabled = false
SilentState.Target = nil
SilentState.Pos = Vector3.zero
SilentState.Chance = 100

local function touchOnly()
    return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function getAimPoint()
    if touchOnly() then return Camera.ViewportSize / 2 end
    return UserInputService:GetMouseLocation()
end

local function isVisible(targetPart)
    if not Config.Combat.VisibleCheck then return true end
    local ignore = {targetPart.Parent}
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = ignore
    params.FilterType = Enum.RaycastFilterType.Exclude

    local origin = Camera.CFrame.Position
    return workspace:Raycast(origin, targetPart.Position - origin, params) == nil
end

local function getTargetPart(char)
    if Config.Combat.TargetHead then return char:FindFirstChild("Head") end
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
end

local function isEnemy(player)
    if not Config.Combat.TeamCheck then return true end
    if LocalPlayer.Team == nil or player.Team == nil then return true end
    return player.Team ~= LocalPlayer.Team
end

local function predictedPos(part)
    return part.Position + part.AssemblyLinearVelocity * Config.Combat.Prediction
end

-- Ближайшая к прицелу цель внутри FOV
local function getTarget(fov)
    local closest, shortest = nil, fov
    local aimPoint = getAimPoint()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and isEnemy(player) then
            local part = getTargetPart(player.Character)
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local d = (Vector2.new(sp.X, sp.Y) - aimPoint).Magnitude
                    if d < shortest and isVisible(part) then
                        shortest = d
                        closest = part
                    end
                end
            end
        end
    end
    return closest
end

local function stillValid(part, fov)
    if not part or not part.Parent then return false end
    local hum = part.Parent:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return false end
    if (Vector2.new(sp.X, sp.Y) - getAimPoint()).Magnitude > fov * 1.25 then return false end
    return isVisible(part)
end

-- ===== Aimbot =====
track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then AimState.Aiming = true end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimState.Aiming = false
        AimState.Locked = nil
    end
end))

local function updateAimbot(dt)
    local C = Config.Combat
    if not C.Aimbot then AimState.Locked = nil return end

    local holding = (not C.HoldToAim) or touchOnly() or AimState.Aiming
    if not holding then AimState.Locked = nil return end

    local target
    if C.Sticky and stillValid(AimState.Locked, C.AimbotFOV) then
        target = AimState.Locked
    else
        target = getTarget(C.AimbotFOV)
        AimState.Locked = target
    end

    if target then
        local cur = Camera.CFrame
        -- сглаживание не зависит от FPS
        local alpha = 1 - (1 - C.AimbotSmoothness) ^ (math.clamp(dt, 0, 0.1) * 60)
        Camera.CFrame = cur:Lerp(CFrame.new(cur.Position, predictedPos(target)), alpha)
    end
end

-- ===== Silent Aim (реальные хуки) =====
local function updateSilent()
    local C = Config.Combat
    SilentState.Enabled = C.SilentAim
    SilentState.Chance = C.HitChance
    if C.SilentAim then
        local t = getTarget(C.SilentFOV)
        SilentState.Target = t
        if t then SilentState.Pos = predictedPos(t) end
    else
        SilentState.Target = nil
    end
end

if not ENV.NurHubHooked then
    local ok = pcall(function()
        assert(hookmetamethod and getnamecallmethod and checkcaller)
        local S = SilentState
        local function roll() return math.random(1, 100) <= S.Chance end

        local oldIndex
        oldIndex = hookmetamethod(game, "__index", function(self, key)
            if S.Enabled and S.Target and self == S.Mouse and not checkcaller()
                and (key == "Hit" or key == "Target") and roll() then
                if key == "Hit" then return CFrame.new(S.Pos) end
                return S.Target
            end
            return oldIndex(self, key)
        end)

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if S.Enabled and S.Target and self == workspace and not checkcaller() then
                local method = getnamecallmethod()
                if method == "Raycast" then
                    local origin, dir, params = ...
                    if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" and roll() then
                        return oldNamecall(self, origin, (S.Pos - origin).Unit * dir.Magnitude, params)
                    end
                elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList"
                    or method == "FindPartOnRayWithWhitelist" then
                    local ray, a, b, c = ...
                    if typeof(ray) == "Ray" and roll() then
                        local o = ray.Origin
                        return oldNamecall(self, Ray.new(o, (S.Pos - o).Unit * ray.Direction.Magnitude), a, b, c)
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end)
    if ok then
        ENV.NurHubHooked = true
    else
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "NurHub", Text = "Silent Aim не поддерживается этим экзекутором", Duration = 6
            })
        end)
    end
end

-- ===== FOV circles (Frame + UIStroke, без Drawing) =====
local function makeCircle()
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = espGui
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = f
    local s = Instance.new("UIStroke")
    s.Thickness = 1.5
    s.Parent = f
    return f, s
end
local aimCircle, aimStroke = makeCircle()
local silentCircle, silentStroke = makeCircle()

local function updateCircles()
    local C = Config.Combat
    local ap = getAimPoint()

    aimCircle.Visible = C.Aimbot and C.ShowFOV
    if aimCircle.Visible then
        aimCircle.Size = UDim2.fromOffset(C.AimbotFOV * 2, C.AimbotFOV * 2)
        aimCircle.Position = UDim2.fromOffset(ap.X, ap.Y)
        aimStroke.Color = C.Colors.AimbotFOV
        -- толще, когда цель захвачена
        aimStroke.Thickness = AimState.Locked and 2.5 or 1.5
    end

    silentCircle.Visible = C.SilentAim and C.ShowSilentFOV
    if silentCircle.Visible then
        silentCircle.Size = UDim2.fromOffset(C.SilentFOV * 2, C.SilentFOV * 2)
        silentCircle.Position = UDim2.fromOffset(ap.X, ap.Y)
        silentStroke.Color = C.Colors.SilentFOV
        silentStroke.Thickness = SilentState.Target and 2.5 or 1.5
    end
end

-- ==========================================================
-- 5. ИГРОК (PLAYER)
-- ==========================================================

local modded = {speed = false, jump = false}

local function applyPlayerMods()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- Значение по умолчанию тоже применяется один раз, чтобы можно было вернуть скорость назад
    if Config.Player.WalkSpeed ~= 16 then
        modded.speed = true
        if humanoid.WalkSpeed ~= Config.Player.WalkSpeed then
            humanoid.WalkSpeed = Config.Player.WalkSpeed
        end
    elseif modded.speed then
        modded.speed = false
        humanoid.WalkSpeed = 16
    end

    if Config.Player.JumpPower ~= 50 then
        modded.jump = true
        humanoid.UseJumpPower = true
        if humanoid.JumpPower ~= Config.Player.JumpPower then
            humanoid.JumpPower = Config.Player.JumpPower
        end
    elseif modded.jump then
        modded.jump = false
        humanoid.UseJumpPower = true
        humanoid.JumpPower = 50
    end
end

local wasNoclip = false
track(RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    -- без активного ключа noclip не работает
    if Config.Player.Noclip and Lic.Active then
        wasNoclip = true
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    elseif wasNoclip then
        wasNoclip = false
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CanCollide = true end
    end
end))

local function stopFly()
    if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
    if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local function updateFly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end

    if Config.Player.Fly then
        if not flyBodyVelocity or flyBodyVelocity.Parent ~= hrp then
            stopFly()
            flyBodyVelocity = Instance.new("BodyVelocity")
            flyBodyVelocity.Name = "NurHub_Fly"
            flyBodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBodyVelocity.Velocity = Vector3.zero
            flyBodyVelocity.Parent = hrp

            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.Name = "NurHub_Fly"
            flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyBodyGyro.P = 1000
            flyBodyGyro.Parent = hrp
        end

        hum.PlatformStand = true
        local moveLocal = Camera.CFrame:VectorToObjectSpace(hum.MoveDirection)
        local dir = Camera.CFrame:VectorToWorldSpace(Vector3.new(moveLocal.X, 0, moveLocal.Z))
        if dir.Magnitude > 0 then dir = dir.Unit end

        flyBodyVelocity.Velocity = dir * Config.Player.FlySpeed
        flyBodyGyro.CFrame = Camera.CFrame
    elseif flyBodyVelocity or flyBodyGyro then
        stopFly()
    end
end

track(LocalPlayer.CharacterAdded:Connect(function()
    flyBodyVelocity, flyBodyGyro = nil, nil
    modded.speed, modded.jump = false, false
end))

-- ==========================================================
-- 5.5 ОТКЛЮЧЕНИЕ ФУНКЦИЙ БЕЗ ЛИЦЕНЗИИ
--     Вызывается каждый кадр, пока ключ не активен / срок истёк
-- ==========================================================

local function suspendAll()
    espGui.Enabled = false
    for _, obj in pairs(espObjects) do pcall(hideAll, obj) end

    SilentState.Enabled = false
    SilentState.Target = nil
    AimState.Locked = nil

    if flyBodyVelocity or flyBodyGyro then stopFly() end

    -- возвращаем стандартную скорость и прыжок
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if modded.speed then modded.speed = false hum.WalkSpeed = 16 end
        if modded.jump then modded.jump = false hum.JumpPower = 50 end
    end
end

-- ==========================================================
-- 6. ГЛАВНЫЙ ЦИКЛ
-- ==========================================================

RunService:BindToRenderStep("NurHubLoop", Enum.RenderPriority.Camera.Value + 1, function(dt)
    -- нет активного ключа -> чит не работает
    if not Lic.Active then
        pcall(suspendAll)
        return
    end

    espGui.Enabled = true
    pcall(updateESP)
    pcall(updateAimbot, dt)
    pcall(updateSilent)
    pcall(updateCircles)
    pcall(applyPlayerMods)
    pcall(updateFly)
end)

track(Players.PlayerRemoving:Connect(clearESP))

-- Запуск системы ключей (окно с анимацией)
Lic.Start()

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "NurHub",
        Text = "Скрипт загружен! Введите ключ.",
        Duration = 5
    })
end)
