local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local LEVELING = Config.Leveling or {}
local LEVELING_UI = LEVELING.UI or {}
local MAX_LEVEL = (LEVELING.MaxLevel and math.floor(LEVELING.MaxLevel)) or 50
local LERP_SPEED = LEVELING_UI.LerpSpeed or 6
local FREEZE_FADE = LEVELING_UI.FreezeFade or 0.25

local controllersFolder = script.Parent and script.Parent:FindFirstChild("Controllers")

local function waitForController(name: string)
    while true do
        controllersFolder = controllersFolder or (script.Parent and script.Parent:FindFirstChild("Controllers"))

        local getController = Knit and Knit.GetController
        if typeof(getController) == "function" then
            local ok, controller = pcall(getController, Knit, name)
            if ok and controller then
                return controller
            end
        end

        if controllersFolder then
            local module = controllersFolder:FindFirstChild(name)
            if module and module:IsA("ModuleScript") then
                local ok, controller = pcall(require, module)
                if ok and controller then
                    return controller
                end
            end
        end

        task.wait()
    end
end

local function waitForControllerState(name: string)
    local controller = waitForController(name)
    while controller do
        local state = controller.State
        if typeof(state) == "table" then
            return controller
        end

        task.wait()
    end

    return nil
end

local inputController: any = nil

task.spawn(function()
    inputController = waitForController("InputController")
end)

local function computeXPToNext(level: number): number
    if level >= MAX_LEVEL then
        return 0
    end
    if typeof(LEVELING.XPToNext) == "function" then
        local ok, value = pcall(LEVELING.XPToNext, level)
        if ok and typeof(value) == "number" then
            return math.max(0, math.floor(value))
        end
    end
    local baseXP = LEVELING.BaseXP or 100
    local growth = LEVELING.Growth or 1.25
    return math.max(0, math.floor(baseXP * (growth ^ (math.max(1, level) - 1))))
end

local uiController: any = nil
local hudReady = false
local pushHUDUpdate
local function markHUDReady()
    if hudReady then
        return
    end
    hudReady = true
    if pushHUDUpdate then
        pushHUDUpdate()
    end
end

task.spawn(function()
    uiController = waitForControllerState("UIController")

    local hudController = waitForController("HUDController")
    if hudController and typeof(hudController.OnInterfaceReady) == "function" then
        hudController:OnInterfaceReady(function()
            markHUDReady()
        end)
    else
        markHUDReady()
    end

    if hudController and hudController.Screen then
        markHUDReady()
    end
end)

local function resolveLevelUpGui(instance: Instance?)
    if not instance then
        return nil
    end

    if instance:IsA("LayerCollector") then
        return instance
    end

    if instance:IsA("Folder") or instance:IsA("Instance") then
        return instance:FindFirstChildWhichIsA("LayerCollector")
    end

    return nil
end

local levelUpContainer = PLAYER_GUI:FindFirstChild("LevelUpModal")
if not levelUpContainer then
    levelUpContainer = PLAYER_GUI:WaitForChild("LevelUpModal", 5)
end

local levelUpGui = resolveLevelUpGui(levelUpContainer)
if not levelUpGui then
    levelUpGui = Instance.new("ScreenGui")
    levelUpGui.Name = "LevelUpModal"
    levelUpGui.ResetOnSpawn = false
    levelUpGui.IgnoreGuiInset = true
    levelUpGui.DisplayOrder = 100
    levelUpGui.Enabled = false

    local fallbackOverlay = Instance.new("Frame")
    fallbackOverlay.Name = "FreezeOverlay"
    fallbackOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
    fallbackOverlay.BackgroundTransparency = 1
    fallbackOverlay.Size = UDim2.fromScale(1, 1)
    fallbackOverlay.ZIndex = 10
    fallbackOverlay.Parent = levelUpGui

    local fallbackConfirmBlocker = Instance.new("TextButton")
    fallbackConfirmBlocker.Name = "ConfirmBlocker"
    fallbackConfirmBlocker.BackgroundTransparency = 1
    fallbackConfirmBlocker.AutoButtonColor = false
    fallbackConfirmBlocker.Text = ""
    fallbackConfirmBlocker.Size = UDim2.fromScale(1, 1)
    fallbackConfirmBlocker.ZIndex = 15
    fallbackConfirmBlocker.Modal = true
    fallbackConfirmBlocker.Parent = levelUpGui

    local fallbackRoot = Instance.new("Frame")
    fallbackRoot.Name = "Root"
    fallbackRoot.AnchorPoint = Vector2.new(0.5, 0.5)
    fallbackRoot.Position = UDim2.fromScale(0.5, 0.5)
    fallbackRoot.Size = UDim2.new(0.6, 0, 0.5, 0)
    fallbackRoot.BackgroundTransparency = 0.2
    fallbackRoot.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    fallbackRoot.BorderSizePixel = 0
    fallbackRoot.ZIndex = 20
    fallbackRoot.Parent = levelUpGui

    local fallbackTitle = Instance.new("TextLabel")
    fallbackTitle.Name = "Title"
    fallbackTitle.BackgroundTransparency = 1
    fallbackTitle.Size = UDim2.new(1, -20, 0, 40)
    fallbackTitle.Position = UDim2.new(0, 10, 0, 10)
    fallbackTitle.Font = Enum.Font.GothamBold
    fallbackTitle.TextSize = 28
    fallbackTitle.TextColor3 = Color3.new(1, 1, 1)
    fallbackTitle.Text = "Choose 1 Upgrade"
    fallbackTitle.ZIndex = 21
    fallbackTitle.Parent = fallbackRoot

    local fallbackOptions = Instance.new("Frame")
    fallbackOptions.Name = "Options"
    fallbackOptions.BackgroundTransparency = 1
    fallbackOptions.Size = UDim2.new(1, -20, 1, -70)
    fallbackOptions.Position = UDim2.new(0, 10, 0, 60)
    fallbackOptions.ZIndex = 21
    fallbackOptions.Parent = fallbackRoot

    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Horizontal
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    listLayout.Padding = UDim.new(0, 10)
    listLayout.Parent = fallbackOptions

    for index = 1, 3 do
        local optionButton = Instance.new("TextButton")
        optionButton.Name = string.format("Option%d", index)
        optionButton.AutoButtonColor = true
        optionButton.Size = UDim2.new(0, 180, 1, -10)
        optionButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        optionButton.BackgroundTransparency = 0.1
        optionButton.BorderSizePixel = 0
        optionButton.TextWrapped = true
        optionButton.TextSize = 20
        optionButton.Font = Enum.Font.Gotham
        optionButton.TextColor3 = Color3.new(1, 1, 1)
        optionButton.Text = "Select"
        optionButton.ZIndex = 22
        optionButton.Parent = fallbackOptions

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(1, -12, 0, 30)
        nameLabel.Position = UDim2.new(0, 6, 0, 6)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 20
        nameLabel.TextWrapped = true
        nameLabel.TextColor3 = Color3.new(1, 1, 1)
        nameLabel.Text = "Upgrade"
        nameLabel.ZIndex = 23
        nameLabel.Parent = optionButton

        local descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.BackgroundTransparency = 1
        descLabel.Size = UDim2.new(1, -12, 0, 60)
        descLabel.Position = UDim2.new(0, 6, 0, 42)
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextSize = 16
        descLabel.TextWrapped = true
        descLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        descLabel.Text = "Description"
        descLabel.ZIndex = 23
        descLabel.Parent = optionButton

        local choiceId = Instance.new("StringValue")
        choiceId.Name = "ChoiceId"
        choiceId.Value = ""
        choiceId.Parent = optionButton
    end

    levelUpGui.Parent = PLAYER_GUI
elseif levelUpContainer ~= levelUpGui and levelUpGui.Parent == levelUpContainer then
    -- keep the resolved ScreenGui reference but ensure it has expected name
    levelUpGui.Name = "LevelUpModal"
end

if levelUpGui then
    local desiredOrder = math.max(LEVELING_UI.DisplayOrder or 0, 200)
    if (levelUpGui.DisplayOrder or 0) < desiredOrder then
        levelUpGui.DisplayOrder = desiredOrder
    end
end

local freezeOverlay = levelUpGui:FindFirstChild("FreezeOverlay")
local rootFrame = levelUpGui:FindFirstChild("Root")
local confirmBlocker = levelUpGui:FindFirstChild("ConfirmBlocker")
local optionsFrame = rootFrame and rootFrame:FindFirstChild("Options")
local statusLabel = rootFrame and rootFrame:FindFirstChild("StatusLabel")

if not statusLabel and rootFrame then
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.BackgroundTransparency = 1
    statusLabel.Size = UDim2.new(1, -20, 0, 40)
    statusLabel.Position = UDim2.new(0, 10, 1, -50)
    statusLabel.ZIndex = 23
    statusLabel.Text = ""
    statusLabel.Visible = false
    statusLabel.TextWrapped = false
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.TextYAlignment = Enum.TextYAlignment.Center
    statusLabel.Parent = rootFrame
end

if statusLabel then
    statusLabel.TextScaled = false
    statusLabel.TextSize = math.max(28, statusLabel.TextSize or 0)
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.TextTransparency = 0
    statusLabel.TextStrokeTransparency = 1
    statusLabel.ZIndex = math.max(statusLabel.ZIndex or 0, (rootFrame and rootFrame.ZIndex or 0) + 5)

end

local optionButtons = {}
local optionDefaults = {}
local FADE_OFFSET = 0.45
if optionsFrame then
    for _, child in ipairs(optionsFrame:GetChildren()) do
        if child:IsA("TextButton") then
            table.insert(optionButtons, child)
        end
    end
    table.sort(optionButtons, function(a, b)
        return a.Name < b.Name
    end)
end

local function captureOptionDefaults(button: TextButton)
    local defaults = {
        BackgroundTransparency = button.BackgroundTransparency,
        TextTransparency = button.TextTransparency,
    }

    local nameLabel = button:FindFirstChild("Name")
    if nameLabel and nameLabel:IsA("TextLabel") then
        defaults.NameTextTransparency = nameLabel.TextTransparency
    end

    local descLabel = button:FindFirstChild("Desc")
    if descLabel and descLabel:IsA("TextLabel") then
        defaults.DescTextTransparency = descLabel.TextTransparency
    end

    optionDefaults[button] = defaults
end

local function restoreOptionVisuals(button: TextButton)
    local defaults = optionDefaults[button]
    if not defaults then
        return
    end

    if defaults.BackgroundTransparency ~= nil then
        button.BackgroundTransparency = defaults.BackgroundTransparency
    end
    if defaults.TextTransparency ~= nil then
        button.TextTransparency = defaults.TextTransparency
    end

    local nameLabel = button:FindFirstChild("Name")
    if nameLabel and nameLabel:IsA("TextLabel") and defaults.NameTextTransparency ~= nil then
        nameLabel.TextTransparency = defaults.NameTextTransparency
    end

    local descLabel = button:FindFirstChild("Desc")
    if descLabel and descLabel:IsA("TextLabel") and defaults.DescTextTransparency ~= nil then
        descLabel.TextTransparency = defaults.DescTextTransparency
    end
end

local function fadeOptionVisuals(button: TextButton)
    local defaults = optionDefaults[button]
    if not defaults then
        return
    end

    local function fade(value: number?)
        if value == nil then
            return nil
        end
        return math.clamp(value + FADE_OFFSET, 0, 1)
    end

    local fadedBackground = fade(defaults.BackgroundTransparency)
    if fadedBackground ~= nil then
        button.BackgroundTransparency = fadedBackground
    end

    local fadedText = fade(defaults.TextTransparency)
    if fadedText ~= nil then
        button.TextTransparency = fadedText
    end

    local nameLabel = button:FindFirstChild("Name")
    if nameLabel and nameLabel:IsA("TextLabel") then
        local target = defaults.NameTextTransparency ~= nil and fade(defaults.NameTextTransparency) or nil
        if target ~= nil then
            nameLabel.TextTransparency = target
        end
    end

    local descLabel = button:FindFirstChild("Desc")
    if descLabel and descLabel:IsA("TextLabel") then
        local target = defaults.DescTextTransparency ~= nil and fade(defaults.DescTextTransparency) or nil
        if target ~= nil then
            descLabel.TextTransparency = target
        end
    end
end

local function applySelectionVisuals(selected: TextButton)
    for _, option in ipairs(optionButtons) do
        if option == selected then
            restoreOptionVisuals(option)
        else
            fadeOptionVisuals(option)
        end
    end
end

for _, button in ipairs(optionButtons) do
    captureOptionDefaults(button)
end

local xpState = {
    level = 1,
    xp = 0,
    xpToNext = computeXPToNext(1),
    currentRatio = 0,
    targetRatio = 0,
}

local worldFrozen = false
local modalActive = false
local choiceSubmitted = false
local activeChoices = nil
local overlayTween: Tween? = nil
local freezeBlockBound = false
local autoSelectionTriggered = false
local autoSelectionArmed = false
local statusState = {
    total = 0,
    committed = 0,
    remaining = 0,
    playerCount = 0,
    lastText = nil,
}

local function refreshStatusLabel(force)
    if not statusLabel then
        return
    end

    if not modalActive or statusState.total <= 0 then
        if statusLabel.Visible then
            statusLabel.Visible = false
        end
        statusState.lastText = nil
        return
    end

    local activeCount = math.max(0, math.floor(statusState.total + 0.5))
    if activeCount <= 0 then
        if statusLabel.Visible then
            statusLabel.Visible = false
        end
        statusState.lastText = nil
        return
    end

    local reportedPlayerCount = math.max(0, math.floor((statusState.playerCount or 0) + 0.5))
    local playerCount = math.max(activeCount, reportedPlayerCount)

    if playerCount <= 0 then
        playerCount = activeCount
    end

    local committedActive = math.max(0, math.floor(statusState.committed + 0.5))
    committedActive = math.clamp(committedActive, 0, activeCount)

    local outstanding = math.max(0, activeCount - committedActive)
    local completed = math.clamp(playerCount - outstanding, 0, playerCount)

    local ratioText = string.format("%d/%d", completed, playerCount)
    local text = ratioText
    local remaining = statusState.remaining or 0
    if remaining > 0 then
        text = string.format("%s (%ds)", ratioText, math.ceil(remaining))
    end

    if force or text ~= statusState.lastText then
        statusLabel.Text = text
        statusState.lastText = text
    end

    statusLabel.Visible = true
end


local function pushHUDUpdate()
    if not uiController or not hudReady then
        return
    end

    local controllerState = uiController.State
    if typeof(controllerState) ~= "table" then
        return
    end

    local progress = {
        Ratio = math.clamp(xpState.currentRatio, 0, 1),
        Current = xpState.xp,
        Required = xpState.xpToNext,
    }

    controllerState.Level = xpState.level
    controllerState.XP = xpState.xp
    controllerState.XPProgress = progress
    uiController:WithHUD("UpdateXP", {
        Level = xpState.level,
        XP = xpState.xp,
        XPProgress = progress,
    })
end

local function setTargetFromXP(xp: number, xpToNext: number)
    xpToNext = math.max(0, xpToNext or 0)
    xp = math.max(0, xp or 0)
    xpState.xp = xp
    xpState.xpToNext = xpToNext
    if xpToNext > 0 then
        xpState.targetRatio = math.clamp(xp / xpToNext, 0, 1)
    else
        xpState.targetRatio = 1
    end
end

local function applyLevel(level: number, xp: number, xpToNext: number)
    xpState.level = math.max(1, math.floor(level or 1))
    setTargetFromXP(xp, xpToNext)
end

local function resetMovementState()
    if not inputController then
        inputController = waitForController("InputController")
    end

    if inputController and typeof(inputController.ResetMovementState) == "function" then
        inputController:ResetMovementState()
    end
end

local function setInputBlocked(enabled: boolean)
    resetMovementState()

    if enabled and not freezeBlockBound then
        local function sink()
            return Enum.ContextActionResult.Sink
        end
        ContextActionService:BindActionAtPriority(
            "SS_LevelUpFreeze",
            sink,
            false,
            Enum.ContextActionPriority.High.Value,
            Enum.KeyCode.W,
            Enum.KeyCode.A,
            Enum.KeyCode.S,
            Enum.KeyCode.D,
            Enum.KeyCode.Q,
            Enum.KeyCode.E,
            Enum.KeyCode.Space,
            Enum.UserInputType.MouseButton1,
            Enum.UserInputType.MouseButton2,
            Enum.UserInputType.Touch
        )
        freezeBlockBound = true
    elseif not enabled and freezeBlockBound then
        ContextActionService:UnbindAction("SS_LevelUpFreeze")
        freezeBlockBound = false
    end
end

local function tweenOverlay(enabled: boolean)
    if not freezeOverlay then
        return
    end

    if overlayTween then
        overlayTween:Cancel()
        overlayTween = nil
    end

    local goal = {BackgroundTransparency = enabled and 0.35 or 1}
    overlayTween = TweenService:Create(
        freezeOverlay,
        TweenInfo.new(FREEZE_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        goal
    )

    overlayTween.Completed:Connect(function()
        if not enabled and not modalActive then
            levelUpGui.Enabled = false
            if rootFrame then
                rootFrame.Visible = false
            end
        end
    end)

    overlayTween:Play()
end

local function resetChoices()
    activeChoices = nil
    choiceSubmitted = false
    autoSelectionTriggered = false
    autoSelectionArmed = false
    if not optionsFrame then
        refreshStatusLabel(true)
        return
    end

    for _, button in ipairs(optionButtons) do
        restoreOptionVisuals(button)
        button.AutoButtonColor = false
        button.Active = false
        button.Selectable = false
        button.Visible = true
        local stroke = button:FindFirstChildWhichIsA("UIStroke")
        if stroke then
            stroke.Transparency = 0.2
        end
        local choiceId = button:FindFirstChild("ChoiceId")
        if choiceId and choiceId:IsA("StringValue") then
            choiceId.Value = ""
        end
        local nameLabel = button:FindFirstChild("Name")
        if nameLabel and nameLabel:IsA("TextLabel") then
            nameLabel.Text = "Loading..."
        end
        local descLabel = button:FindFirstChild("Desc")
        if descLabel and descLabel:IsA("TextLabel") then
            descLabel.Text = ""
        end
    end

    refreshStatusLabel(true)
end

local function populateChoices(choices)
    activeChoices = choices
    if not choices then
        for _, button in ipairs(optionButtons) do
            button.AutoButtonColor = false
            button.Active = false
            local nameLabel = button:FindFirstChild("Name")
            if nameLabel and nameLabel:IsA("TextLabel") then
                nameLabel.Text = "No Options"
            end
            local descLabel = button:FindFirstChild("Desc")
            if descLabel and descLabel:IsA("TextLabel") then
                descLabel.Text = "Please wait for the server."
            end
        end
        return
    end

    for index, button in ipairs(optionButtons) do
        restoreOptionVisuals(button)
        local info = choices[index]
        local choiceId = button:FindFirstChild("ChoiceId")
        if info and typeof(info) == "table" then
            button.AutoButtonColor = true
            button.Active = true
            button.Selectable = true
            local nameLabel = button:FindFirstChild("Name")
            local descLabel = button:FindFirstChild("Desc")
            if nameLabel and nameLabel:IsA("TextLabel") then
                nameLabel.Text = tostring(info.name or info.id or "Unknown")
            end
            if descLabel and descLabel:IsA("TextLabel") then
                descLabel.Text = tostring(info.desc or "")
            end
            if choiceId and choiceId:IsA("StringValue") then
                choiceId.Value = tostring(info.id or "")
            end
        else
            button.AutoButtonColor = false
            button.Active = false
            button.Selectable = false
            if choiceId and choiceId:IsA("StringValue") then
                choiceId.Value = ""
            end
            local nameLabel = button:FindFirstChild("Name")
            if nameLabel and nameLabel:IsA("TextLabel") then
                nameLabel.Text = "Unavailable"
            end
            local descLabel = button:FindFirstChild("Desc")
            if descLabel and descLabel:IsA("TextLabel") then
                descLabel.Text = ""
            end
        end
    end
end

local function requestChoices()
    local remote = Net:GetFunction("GetLevelUpChoices")
    local success, payload = pcall(function()
        return remote:InvokeServer()
    end)
    if not success then
        warn("PlayerProgress: failed to fetch level-up choices", payload)
        populateChoices(nil)
        return
    end

    if typeof(payload) ~= "table" then
        populateChoices(nil)
        return
    end

    if not modalActive then
        return
    end

    populateChoices(payload.Choices)
end

local function onOptionClicked(button: TextButton)
    if choiceSubmitted or not modalActive then
        return
    end

    local choiceId = ""
    local choiceValue = button:FindFirstChild("ChoiceId")
    if choiceValue and choiceValue:IsA("StringValue") then
        choiceId = choiceValue.Value
    end
    if choiceId == "" then
        return
    end

    choiceSubmitted = true
    for _, option in ipairs(optionButtons) do
        option.AutoButtonColor = false
        option.Active = false
        option.Selectable = false
        local stroke = option:FindFirstChildWhichIsA("UIStroke")
        if stroke then
            stroke.Transparency = option == button and 0 or 0.6
        end
    end

    applySelectionVisuals(button)

    Net:GetEvent("CommitLevelUpChoice"):FireServer(choiceId)
end

local function commitDefaultChoice()
    if choiceSubmitted or autoSelectionTriggered then
        return
    end

    for _, button in ipairs(optionButtons) do
        if button.Active and button.Selectable then
            local choiceValue = button:FindFirstChild("ChoiceId")
            local choiceId = ""
            if choiceValue and choiceValue:IsA("StringValue") then
                choiceId = choiceValue.Value
            end

            if choiceId ~= "" then
                autoSelectionTriggered = true
                onOptionClicked(button)
                return
            end
        end
    end
end

for _, button in ipairs(optionButtons) do
    button.MouseButton1Click:Connect(function()
        onOptionClicked(button)
    end)
end

if confirmBlocker and confirmBlocker:IsA("GuiButton") then
    confirmBlocker.AutoButtonColor = false
    confirmBlocker.MouseButton1Click:Connect(function()
        -- intentional no-op to block dismiss
    end)
end

local function playLevelUpAnimation(newLevel: number, carriedXP: number)
    carriedXP = carriedXP or 0
    local previousGoal = xpState.xpToNext > 0 and xpState.xpToNext or computeXPToNext(math.max(1, newLevel - 1))
    xpState.targetRatio = 1
    xpState.xp = previousGoal
    xpState.xpToNext = previousGoal

    task.spawn(function()
        while math.abs(xpState.currentRatio - 1) > 0.01 do
            RunService.RenderStepped:Wait()
        end

        local nextGoal = computeXPToNext(newLevel)
        xpState.level = math.clamp(newLevel, 1, MAX_LEVEL)
        xpState.currentRatio = 0
        xpState.xpToNext = nextGoal
        xpState.xp = math.clamp(carriedXP, 0, nextGoal > 0 and nextGoal or carriedXP)
        if nextGoal > 0 then
            xpState.targetRatio = math.clamp(xpState.xp / nextGoal, 0, 1)
        else
            xpState.targetRatio = 1
        end
        pushHUDUpdate()
    end)
end

local progressFunction = Net:GetFunction("GetProgress")
local xpChangedEvent = Net:GetEvent("XPChanged")
local levelUpEvent = Net:GetEvent("LevelUp")
local freezeEvent = Net:GetEvent("SetWorldFreeze")
local levelUpStatusEvent = Net:GetEvent("LevelUpStatus")

local success, initial = pcall(function()
    return progressFunction:InvokeServer()
end)
if success and typeof(initial) == "table" then
    local level = initial.Level or initial.level or 1
    local xp = initial.XP or initial.xp or 0
    local xpToNext = initial.XPToNext or initial.xpToNext or computeXPToNext(level)
    xpState.currentRatio = xpToNext > 0 and math.clamp(xp / xpToNext, 0, 1) or 1
    applyLevel(level, xp, xpToNext)
    pushHUDUpdate()
else
    warn("PlayerProgress: failed to load initial progress", initial)
end

xpChangedEvent.OnClientEvent:Connect(function(player, xp, xpToNext)
    if player ~= LOCAL_PLAYER then
        return
    end

    setTargetFromXP(xp, xpToNext)
    pushHUDUpdate()
end)

levelUpStatusEvent.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then
        return
    end

    statusState.total = math.max(0, tonumber(payload.Total) or 0)
    statusState.committed = math.max(0, tonumber(payload.Committed) or 0)
    local playerCount = tonumber(payload.PlayerCount) or 0

    if playerCount > 0 then
        statusState.playerCount = math.max(0, math.floor(playerCount + 0.5))
    else
        statusState.playerCount = math.max(statusState.total, 0)
    end

    statusState.playerCount = math.max(statusState.total, math.max(0, playerCount))

    if statusState.total > 0 and typeof(payload.Remaining) == "number" then
        statusState.remaining = math.max(0, payload.Remaining)
        if statusState.remaining > 0 then
            autoSelectionArmed = true
        elseif autoSelectionArmed and not choiceSubmitted then
            commitDefaultChoice()
        end
    else
        statusState.remaining = 0
    end

    if not modalActive then
        statusState.lastText = nil
    end

    refreshStatusLabel(true)
end)

levelUpEvent.OnClientEvent:Connect(function(player, newLevel, carriedXP)
    if player ~= LOCAL_PLAYER then
        return
    end

    modalActive = true
    levelUpGui.Enabled = true
    if rootFrame then
        rootFrame.Visible = true
    end
    setInputBlocked(true)
    tweenOverlay(true)
    resetChoices()
    task.spawn(requestChoices)
    playLevelUpAnimation(newLevel, carriedXP)
    refreshStatusLabel(true)
end)

freezeEvent.OnClientEvent:Connect(function(enabled)
    worldFrozen = not not enabled
    setInputBlocked(worldFrozen)
    if worldFrozen then
        levelUpGui.Enabled = true
        tweenOverlay(true)
    else
        tweenOverlay(false)
        modalActive = false
        if rootFrame then
            rootFrame.Visible = false
        end
        resetChoices()
        refreshStatusLabel(true)
    end
end)

RunService.RenderStepped:Connect(function(dt)
    local diff = xpState.targetRatio - xpState.currentRatio
    if math.abs(diff) > 0.0005 then
        local step = math.clamp(dt * LERP_SPEED, 0, 1)
        xpState.currentRatio += diff * step
    else
        xpState.currentRatio = xpState.targetRatio
    end

    if statusLabel and statusLabel.Visible and statusState.remaining and statusState.remaining > 0 then
        local previous = statusState.remaining
        statusState.remaining = math.max(0, previous - dt)
        if math.ceil(statusState.remaining) ~= math.ceil(previous) then
            refreshStatusLabel(false)
        end
        if statusState.remaining <= 0 and autoSelectionArmed and not autoSelectionTriggered then
            commitDefaultChoice()
        end
    end

    if modalActive and autoSelectionArmed and not autoSelectionTriggered and not choiceSubmitted and (statusState.remaining or 0) <= 0 then
        commitDefaultChoice()
    end

    pushHUDUpdate()
end)
