local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Config = require(ReplicatedStorage.Shared.Config)

local HUDController = Knit.CreateController({
    Name = "HUDController",
})

local function createTextLabel(
    parent: Instance,
    text: string,
    font: Enum.Font,
    textSize: number,
    alignment: Enum.TextXAlignment,
    name: string?
)
    local label = Instance.new("TextLabel")
    label.Name = name or "TextLabel"
    label.BackgroundTransparency = 1
    label.Text = text
    label.Font = font
    label.TextScaled = false
    label.TextSize = textSize
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextXAlignment = alignment or Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextStrokeTransparency = 0.6
    label.Parent = parent
    return label
end

local function createCooldownSlot(parent: Instance, props)
    local size = props.Size or 72
    local container = Instance.new("Frame")
    container.Name = props.Name or "CooldownSlot"
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0, size, 0, size)
    container.LayoutOrder = props.LayoutOrder or 0
    container.Parent = parent

    local slot = Instance.new("Frame")
    slot.Name = "Slot"
    slot.BackgroundTransparency = 1
    slot.Size = UDim2.fromScale(1, 1)
    slot.Parent = container

    local gauge = Instance.new("Frame")
    gauge.Name = "Gauge"
    gauge.Size = UDim2.fromScale(1, 1)
    gauge.BackgroundColor3 = props.BackgroundColor or Color3.fromRGB(18, 24, 32)
    gauge.BackgroundTransparency = props.BackgroundTransparency or 0.25
    gauge.BorderSizePixel = 0
    gauge.Parent = slot

    local gaugeCorner = Instance.new("UICorner")
    gaugeCorner.CornerRadius = UDim.new(1, 0)
    gaugeCorner.Parent = gauge

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = props.StrokeThickness or 2
    stroke.Color = props.StrokeColor or Color3.fromRGB(120, 200, 255)
    stroke.Transparency = props.StrokeTransparency or 0.2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = gauge

    local mask = Instance.new("Frame")
    mask.Name = "Mask"
    mask.BackgroundTransparency = 1
    mask.Size = UDim2.fromScale(1, 1)
    mask.ClipsDescendants = true
    mask.Parent = gauge

    local maskCorner = Instance.new("UICorner")
    maskCorner.CornerRadius = UDim.new(1, 0)
    maskCorner.Parent = mask

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BorderSizePixel = 0
    fill.BackgroundColor3 = props.FillColor or Color3.fromRGB(120, 200, 255)
    fill.BackgroundTransparency = props.FillTransparency or 0.15
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Parent = mask

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local boldFont = props.BoldFont or Enum.Font.GothamBold
    local textSize = props.TextSize or 16

    local keyLabel = createTextLabel(
        gauge,
        props.KeyText or "",
        boldFont,
        textSize,
        Enum.TextXAlignment.Center,
        "KeyLabel"
    )
    keyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    keyLabel.Position = UDim2.new(0.5, 0, props.KeyLabelY or 0.32, 0)
    keyLabel.TextScaled = true

    local cooldownLabel = createTextLabel(
        gauge,
        props.ReadyText or "Ready",
        boldFont,
        textSize,
        Enum.TextXAlignment.Center,
        "CooldownLabel"
    )
    cooldownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    cooldownLabel.Position = UDim2.new(0.5, 0, props.CooldownLabelY or 0.72, 0)
    cooldownLabel.TextScaled = true
    cooldownLabel.TextColor3 = props.ReadyColor or Color3.fromRGB(180, 255, 205)

    return {
        Container = container,
        Gauge = gauge,
        Fill = fill,
        CooldownLabel = cooldownLabel,
        KeyLabel = keyLabel,
    }
end

function HUDController:KnitInit()
    self.Elements = {}
    self.PartyEntries = {}
    self.LastMessageTask = nil
    self.AlertTasks = {}
end

function HUDController:KnitStart()
    local player = Players.LocalPlayer
    if not player then
        return
    end

    local playerGui = player:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("SkillSurvivalHUD")
    if existing and existing:IsA("ScreenGui") then
        self:UseExistingInterface(existing)
    else
        self:CreateInterface(playerGui)
    end
end

local function resolveCooldownSlot(root: Instance?)
    if not root then
        return nil
    end

    local slot = root:FindFirstChild("Slot")
    local gauge = slot and slot:FindFirstChild("Gauge")
    local mask = gauge and gauge:FindFirstChild("Mask")
    local fill = mask and mask:FindFirstChild("Fill")
    local cooldownLabel = gauge and gauge:FindFirstChild("CooldownLabel")
    local keyLabel = gauge and gauge:FindFirstChild("KeyLabel")

    if not (slot and gauge and mask and fill and cooldownLabel and keyLabel) then
        return nil
    end

    return {
        Container = root,
        Gauge = gauge,
        Fill = fill,
        CooldownLabel = cooldownLabel,
        KeyLabel = keyLabel,
    }
end

function HUDController:CaptureInterfaceElements(screen: ScreenGui, abilityConfig, dashConfig, uiConfig)
    uiConfig = uiConfig or {}
    abilityConfig = abilityConfig or {}
    dashConfig = dashConfig or {}

    local safeFrame = screen:FindFirstChild("SafeFrame")
    if not safeFrame then
        warn("HUDController: SafeFrame missing from HUD")
        return
    end

    local leftColumn = safeFrame:FindFirstChild("LeftColumn")
    local statusPanel = leftColumn and leftColumn:FindFirstChild("StatusPanel")
    local xpPanel = leftColumn and leftColumn:FindFirstChild("XPPanel")
    local waveLabel = statusPanel and statusPanel:FindFirstChild("WaveLabel")
    local enemyLabel = statusPanel and statusPanel:FindFirstChild("EnemyLabel")
    local timerLabel = statusPanel and statusPanel:FindFirstChild("TimerLabel")
    local goldLabel = statusPanel and statusPanel:FindFirstChild("GoldLabel")

    local xpHeader = xpPanel and xpPanel:FindFirstChild("XPHeader")
    local xpLabel = xpHeader and xpHeader:FindFirstChild("XPText")
    local levelLabel = xpHeader and xpHeader:FindFirstChild("LevelLabel")
    local xpBar = xpPanel and xpPanel:FindFirstChild("XPBar")
    local xpFill = xpBar and xpBar:FindFirstChild("Fill")

    local alertArea = safeFrame:FindFirstChild("AlertArea")
    local waveAnnouncement = alertArea and alertArea:FindFirstChild("WaveAnnouncement")
    local messageLabel = alertArea and alertArea:FindFirstChild("MessageLabel")
    local reservedAlert = alertArea and alertArea:FindFirstChild("ReservedAlerts")
    local reservedLabel = reservedAlert and reservedAlert:FindFirstChild("ReservedLabel")

    local partyContainer = safeFrame:FindFirstChild("PartyContainer")
    local partyEmptyLabel = partyContainer and partyContainer:FindFirstChild("PartyEmptyLabel")

    local abilityFrame = safeFrame:FindFirstChild("AbilityFrame")
    local skillSlot = abilityFrame and abilityFrame:FindFirstChild("SkillSlot")
    local dashSlot = abilityFrame and abilityFrame:FindFirstChild("DashSlot")

    local skill = resolveCooldownSlot(skillSlot)
    local dash = resolveCooldownSlot(dashSlot)

    if not (skill and dash) then
        warn("HUDController: Ability slots missing or malformed")
        return
    end

    local safeMargin = uiConfig.SafeMargin or 24
    local infoTextSize = uiConfig.InfoTextSize or 18
    local smallTextSize = uiConfig.SmallTextSize or 16
    local alertTextSize = uiConfig.AlertTextSize or 20
    local sidePanelWidth = uiConfig.SidePanelWidth or uiConfig.TopInfoWidth or 260
    local sectionSpacing = uiConfig.SectionSpacing or 12
    local panelBackground = uiConfig.PanelBackgroundColor or uiConfig.TopBarBackgroundColor or Color3.fromRGB(18, 24, 32)
    local panelTransparency = uiConfig.PanelBackgroundTransparency or uiConfig.TopBarTransparency or 0.35
    local panelCornerRadius = uiConfig.PanelCornerRadius or 12
    local panelStrokeColor = uiConfig.PanelStrokeColor or Color3.fromRGB(80, 120, 160)
    local panelStrokeThickness = uiConfig.PanelStrokeThickness or 1.5
    local panelStrokeTransparency = uiConfig.PanelStrokeTransparency or 0.45
    local panelPadding = uiConfig.PanelPadding or 12

    local dashSize = dashConfig.Size or 72
    local abilityWidth = abilityConfig.Width or 260
    local abilityHeight = abilityConfig.Height or 90
    local abilitySpacing = abilityConfig.Spacing or 12
    local abilityBottomOffset = abilityConfig.BottomOffset or 0
    local skillSlotSize = abilityConfig.SkillSize or dashSize

    abilityWidth = math.max(abilityWidth, skillSlotSize + abilitySpacing + dashSize)
    abilityHeight = math.max(abilityHeight, math.max(skillSlotSize, dashSize))

    local reservedBottom = math.max(0, abilityHeight + abilityBottomOffset + sectionSpacing)

    safeFrame.Size = UDim2.new(1, -safeMargin * 2, 1, -safeMargin * 2)
    safeFrame.Position = UDim2.new(0, safeMargin, 0, safeMargin)

    if leftColumn then
        leftColumn.Size = UDim2.new(0, sidePanelWidth, 1, -reservedBottom)
        local leftLayout = leftColumn:FindFirstChildWhichIsA("UIListLayout")
        if leftLayout then
            leftLayout.Padding = UDim.new(0, sectionSpacing)
        end
    end

    if statusPanel then
        statusPanel.BackgroundColor3 = panelBackground
        statusPanel.BackgroundTransparency = panelTransparency
        local statusCorner = statusPanel:FindFirstChildWhichIsA("UICorner")
        if statusCorner then
            statusCorner.CornerRadius = UDim.new(0, panelCornerRadius)
        end
        local statusStroke = statusPanel:FindFirstChildWhichIsA("UIStroke")
        if statusStroke then
            statusStroke.Color = panelStrokeColor
            statusStroke.Thickness = panelStrokeThickness
            statusStroke.Transparency = panelStrokeTransparency
            statusStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        end
        local statusPadding = statusPanel:FindFirstChildWhichIsA("UIPadding")
        if statusPadding then
            statusPadding.PaddingTop = UDim.new(0, panelPadding)
            statusPadding.PaddingBottom = UDim.new(0, panelPadding)
            statusPadding.PaddingLeft = UDim.new(0, panelPadding)
            statusPadding.PaddingRight = UDim.new(0, panelPadding)
        end
        if waveLabel then
            waveLabel.TextSize = uiConfig.TopLabelTextSize or 20
        end
        if enemyLabel then
            enemyLabel.TextSize = infoTextSize
        end
        if timerLabel then
            timerLabel.TextSize = infoTextSize
        end
        if goldLabel then
            goldLabel.TextSize = infoTextSize
        end
    end

    if xpPanel then
        xpPanel.BackgroundColor3 = panelBackground
        xpPanel.BackgroundTransparency = panelTransparency
        local xpCorner = xpPanel:FindFirstChildWhichIsA("UICorner")
        if xpCorner then
            xpCorner.CornerRadius = UDim.new(0, panelCornerRadius)
        end
        local xpStroke = xpPanel:FindFirstChildWhichIsA("UIStroke")
        if xpStroke then
            xpStroke.Color = panelStrokeColor
            xpStroke.Thickness = panelStrokeThickness
            xpStroke.Transparency = panelStrokeTransparency
            xpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        end
        local xpPadding = xpPanel:FindFirstChildWhichIsA("UIPadding")
        if xpPadding then
            xpPadding.PaddingTop = UDim.new(0, panelPadding)
            xpPadding.PaddingBottom = UDim.new(0, panelPadding)
            xpPadding.PaddingLeft = UDim.new(0, panelPadding)
            xpPadding.PaddingRight = UDim.new(0, panelPadding)
        end
        local xpHeader = xpPanel:FindFirstChild("XPHeader")
        if xpHeader then
            xpHeader.Size = UDim2.new(1, 0, 0, uiConfig.XP and uiConfig.XP.LabelHeight or 24)
        end
        if xpLabel then
            xpLabel.TextSize = uiConfig.XP and uiConfig.XP.LabelTextSize or infoTextSize
        end
        if levelLabel then
            levelLabel.TextSize = uiConfig.XP and uiConfig.XP.LevelTextSize or alertTextSize
            levelLabel.Size = UDim2.new(0, (uiConfig.XP and uiConfig.XP.LevelWidth) or 60, 1, 0)
        end
        if xpBar then
            xpBar.BackgroundColor3 = uiConfig.XP and uiConfig.XP.BackgroundColor or panelBackground
            xpBar.BackgroundTransparency = uiConfig.XP and uiConfig.XP.BackgroundTransparency or 0.45
            xpBar.Size = UDim2.new(1, 0, 0, (uiConfig.XP and uiConfig.XP.BarHeight) or 18)
            local barCorner = xpBar:FindFirstChildWhichIsA("UICorner")
            if barCorner then
                barCorner.CornerRadius = UDim.new(0, (uiConfig.XP and uiConfig.XP.CornerRadius) or 9)
            end
        end
        if xpFill then
            xpFill.BackgroundColor3 = uiConfig.XP and uiConfig.XP.FillColor or Color3.fromRGB(88, 182, 255)
            xpFill.BackgroundTransparency = uiConfig.XP and uiConfig.XP.FillTransparency or 0.05
            local fillCorner = xpFill:FindFirstChildWhichIsA("UICorner")
            if fillCorner then
                fillCorner.CornerRadius = UDim.new(0, (uiConfig.XP and uiConfig.XP.CornerRadius) or 9)
            end
        end
    end

    if alertArea then
        alertArea.Position = UDim2.new(0, sidePanelWidth + sectionSpacing, 0, uiConfig.AlertAreaOffset or 12)
        alertArea.Size = UDim2.new(1, -(sidePanelWidth + sectionSpacing), 0, uiConfig.AlertAreaHeight or 160)
        local alertLayout = alertArea:FindFirstChildWhichIsA("UIListLayout")
        if alertLayout then
            alertLayout.Padding = UDim.new(0, uiConfig.AlertPadding or 8)
        end
        if waveAnnouncement then
            waveAnnouncement.TextSize = alertTextSize
            waveAnnouncement.Size = UDim2.new(1, 0, 0, uiConfig.WaveAnnouncementHeight or 48)
        end
        if messageLabel then
            messageLabel.TextSize = alertTextSize
            messageLabel.Size = UDim2.new(1, 0, 0, uiConfig.MessageHeight or 40)
        end
        if reservedAlert then
            reservedAlert.BackgroundColor3 = uiConfig.AlertBackgroundColor or panelBackground
            reservedAlert.BackgroundTransparency = uiConfig.AlertBackgroundTransparency or 0.35
            reservedAlert.Size = UDim2.new(1, 0, 0, uiConfig.ReservedAlertHeight or 52)
            local reservedCorner = reservedAlert:FindFirstChildWhichIsA("UICorner")
            if reservedCorner then
                reservedCorner.CornerRadius = UDim.new(0, uiConfig.ReservedAlertCornerRadius or 10)
            end
        end
        if reservedLabel then
            reservedLabel.TextSize = alertTextSize
        end
    end

    if partyContainer then
        partyContainer.Size = UDim2.new(0, uiConfig.Party and uiConfig.Party.Width or 220, 0, 10)
        partyContainer.Position = UDim2.new(1, 0, 0, sectionSpacing)
        local partyLayout = partyContainer:FindFirstChildWhichIsA("UIListLayout")
        if partyLayout then
            partyLayout.Padding = UDim.new(0, uiConfig.Party and uiConfig.Party.Padding or 6)
        end
        if partyEmptyLabel then
            partyEmptyLabel.TextSize = uiConfig.Party and uiConfig.Party.NameTextSize or smallTextSize
        end
    end

    if abilityFrame then
        abilityFrame.AnchorPoint = Vector2.new(0, 1)
        abilityFrame.Position = UDim2.new(0, 0, 1, -abilityBottomOffset)
        abilityFrame.Size = UDim2.new(0, abilityWidth, 0, abilityHeight)
        local abilityLayout = abilityFrame:FindFirstChildWhichIsA("UIListLayout")
        if abilityLayout then
            abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
            abilityLayout.Padding = UDim.new(0, abilitySpacing)
        end
    end

    skill.Container.Size = UDim2.new(0, skillSlotSize, 0, skillSlotSize)
    dash.Container.Size = UDim2.new(0, dashSize, 0, dashSize)

    skill.Gauge.BackgroundColor3 = abilityConfig.SkillBackgroundColor or Color3.fromRGB(18, 24, 32)
    skill.Gauge.BackgroundTransparency = abilityConfig.SkillBackgroundTransparency or 0.25
    local skillStroke = skill.Gauge:FindFirstChildWhichIsA("UIStroke")
    if skillStroke then
        skillStroke.Color = abilityConfig.SkillStrokeColor or Color3.fromRGB(255, 196, 110)
        skillStroke.Thickness = abilityConfig.SkillStrokeThickness or 2
        skillStroke.Transparency = abilityConfig.SkillStrokeTransparency or 0.2
        skillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    end
    if skill.Fill then
        skill.Fill.BackgroundColor3 = abilityConfig.SkillFillColor or Color3.fromRGB(255, 196, 110)
        skill.Fill.BackgroundTransparency = abilityConfig.SkillFillTransparency or 0.15
    end

    dash.Gauge.BackgroundColor3 = dashConfig.BackgroundColor or Color3.fromRGB(18, 24, 32)
    dash.Gauge.BackgroundTransparency = dashConfig.BackgroundTransparency or 0.25
    local dashStroke = dash.Gauge:FindFirstChildWhichIsA("UIStroke")
    if dashStroke then
        dashStroke.Color = dashConfig.StrokeColor or Color3.fromRGB(120, 200, 255)
        dashStroke.Thickness = dashConfig.StrokeThickness or 2
        dashStroke.Transparency = dashConfig.StrokeTransparency or 0.2
        dashStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    end
    if dash.Fill then
        dash.Fill.BackgroundColor3 = dashConfig.FillColor or Color3.fromRGB(120, 200, 255)
        dash.Fill.BackgroundTransparency = dashConfig.FillTransparency or 0.15
    end

    self.Screen = screen
    self.SkillDisplayKey = abilityConfig.SkillKey or "Q"
    self.SkillReadyText = abilityConfig.SkillReadyText or "Ready"
    self.SkillReadyColor = abilityConfig.SkillReadyColor or Color3.fromRGB(255, 235, 200)
    self.PrimarySkillId = abilityConfig.PrimarySkillId or "AOE_Blast"
    self.DashReadyText = dashConfig.ReadyText or "Ready"
    self.DashReadyColor = dashConfig.ReadyColor or Color3.fromRGB(180, 255, 205)

    skill.KeyLabel.Text = self.SkillDisplayKey
    skill.CooldownLabel.Text = self.SkillReadyText
    skill.CooldownLabel.TextColor3 = self.SkillReadyColor
    dash.KeyLabel.Text = dashConfig.KeyText or "E"
    dash.CooldownLabel.Text = self.DashReadyText
    dash.CooldownLabel.TextColor3 = self.DashReadyColor

    self.Elements = {
        WaveLabel = waveLabel,
        EnemyLabel = enemyLabel,
        TimerLabel = timerLabel,
        GoldLabel = goldLabel,
        SkillFill = skill.Fill,
        SkillCooldownLabel = skill.CooldownLabel,
        SkillKeyLabel = skill.KeyLabel,
        DashFill = dash.Fill,
        DashCooldownLabel = dash.CooldownLabel,
        MessageLabel = messageLabel,
        WaveAnnouncement = waveAnnouncement,
        ReservedAlert = reservedAlert,
        ReservedAlertLabel = reservedLabel,
        PartyContainer = partyContainer,
        PartyEmptyLabel = partyEmptyLabel,
        XPFill = xpFill,
        XPTextLabel = xpLabel,
        LevelLabel = levelLabel,
        XPBar = xpBar,
    }
end

function HUDController:UseExistingInterface(screen: ScreenGui)
    local uiConfig = Config.UI or {}
    local abilityConfig = uiConfig.Abilities or {}
    local dashConfig = uiConfig.Dash or {}

    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = false
    screen.DisplayOrder = (uiConfig.DisplayOrder and uiConfig.DisplayOrder.HUD) or 0

    self:CaptureInterfaceElements(screen, abilityConfig, dashConfig, uiConfig)
end

function HUDController:CreateInterface(playerGui: PlayerGui)
    local uiConfig = Config.UI or {}
    local font = uiConfig.Font or Enum.Font.Gotham
    local boldFont = uiConfig.BoldFont or Enum.Font.GothamBold
    local safeMargin = uiConfig.SafeMargin or 24
    local infoTextSize = uiConfig.InfoTextSize or 18
    local smallTextSize = uiConfig.SmallTextSize or 16
    local alertTextSize = uiConfig.AlertTextSize or 20
    local sidePanelWidth = uiConfig.SidePanelWidth or uiConfig.TopInfoWidth or 260
    local sectionSpacing = uiConfig.SectionSpacing or 12
    local panelBackground = uiConfig.PanelBackgroundColor or uiConfig.TopBarBackgroundColor or Color3.fromRGB(18, 24, 32)
    local panelTransparency = uiConfig.PanelBackgroundTransparency or uiConfig.TopBarTransparency or 0.35
    local panelCornerRadius = uiConfig.PanelCornerRadius or 12
    local panelStrokeColor = uiConfig.PanelStrokeColor or Color3.fromRGB(80, 120, 160)
    local panelStrokeThickness = uiConfig.PanelStrokeThickness or 1.5
    local panelStrokeTransparency = uiConfig.PanelStrokeTransparency or 0.45
    local panelPadding = uiConfig.PanelPadding or 12

    local screen = Instance.new("ScreenGui")
    screen.Name = "SkillSurvivalHUD"
    screen.IgnoreGuiInset = false
    screen.ResetOnSpawn = false
    screen.DisplayOrder = (uiConfig.DisplayOrder and uiConfig.DisplayOrder.HUD) or 0
    screen.Parent = playerGui

    local safeFrame = Instance.new("Frame")
    safeFrame.Name = "SafeFrame"
    safeFrame.BackgroundTransparency = 1
    safeFrame.Size = UDim2.new(1, -safeMargin * 2, 1, -safeMargin * 2)
    safeFrame.Position = UDim2.new(0, safeMargin, 0, safeMargin)
    safeFrame.Parent = screen

    local abilityConfig = uiConfig.Abilities or {}
    local dashConfig = uiConfig.Dash or {}
    local dashSize = dashConfig.Size or 72
    local abilityWidth = abilityConfig.Width or 260
    local abilityHeight = abilityConfig.Height or 90
    local abilitySpacing = abilityConfig.Spacing or 12
    local abilityBottomOffset = abilityConfig.BottomOffset or 0
    local skillSlotSize = abilityConfig.SkillSize or dashSize

    abilityWidth = math.max(abilityWidth, skillSlotSize + abilitySpacing + dashSize)
    abilityHeight = math.max(abilityHeight, math.max(skillSlotSize, dashSize))

    local reservedBottom = math.max(0, abilityHeight + abilityBottomOffset + sectionSpacing)

    local leftColumn = Instance.new("Frame")
    leftColumn.Name = "LeftColumn"
    leftColumn.BackgroundTransparency = 1
    leftColumn.Size = UDim2.new(0, sidePanelWidth, 1, -reservedBottom)
    leftColumn.Parent = safeFrame

    local leftLayout = Instance.new("UIListLayout")
    leftLayout.FillDirection = Enum.FillDirection.Vertical
    leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
    leftLayout.Padding = UDim.new(0, sectionSpacing)
    leftLayout.Parent = leftColumn

    local statusPanel = Instance.new("Frame")
    statusPanel.Name = "StatusPanel"
    statusPanel.BackgroundColor3 = panelBackground
    statusPanel.BackgroundTransparency = panelTransparency
    statusPanel.BorderSizePixel = 0
    statusPanel.Size = UDim2.new(1, 0, 0, 0)
    statusPanel.AutomaticSize = Enum.AutomaticSize.Y
    statusPanel.Parent = leftColumn

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, panelCornerRadius)
    statusCorner.Parent = statusPanel

    local statusStroke = Instance.new("UIStroke")
    statusStroke.Color = panelStrokeColor
    statusStroke.Thickness = panelStrokeThickness
    statusStroke.Transparency = panelStrokeTransparency
    statusStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    statusStroke.Parent = statusPanel

    local statusPadding = Instance.new("UIPadding")
    statusPadding.PaddingTop = UDim.new(0, panelPadding)
    statusPadding.PaddingBottom = UDim.new(0, panelPadding)
    statusPadding.PaddingLeft = UDim.new(0, panelPadding)
    statusPadding.PaddingRight = UDim.new(0, panelPadding)
    statusPadding.Parent = statusPanel

    local statusLayout = Instance.new("UIListLayout")
    statusLayout.FillDirection = Enum.FillDirection.Vertical
    statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
    statusLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    statusLayout.Padding = UDim.new(0, 6)
    statusLayout.Parent = statusPanel

    local waveLabel = createTextLabel(
        statusPanel,
        "Wave 0",
        boldFont,
        uiConfig.TopLabelTextSize or 20,
        Enum.TextXAlignment.Left,
        "WaveLabel"
    )
    waveLabel.LayoutOrder = 1
    waveLabel.Size = UDim2.new(1, 0, 0, (uiConfig.TopLabelTextSize or 20) + 6)

    local enemyLabel = createTextLabel(
        statusPanel,
        "Enemies: 0",
        font,
        infoTextSize,
        Enum.TextXAlignment.Left,
        "EnemyLabel"
    )
    enemyLabel.LayoutOrder = 2
    enemyLabel.Size = UDim2.new(1, 0, 0, infoTextSize + 6)

    local timerLabel = createTextLabel(
        statusPanel,
        "Time: ∞",
        font,
        infoTextSize,
        Enum.TextXAlignment.Left,
        "TimerLabel"
    )
    timerLabel.LayoutOrder = 3
    timerLabel.Size = UDim2.new(1, 0, 0, infoTextSize + 6)

    local goldLabel = createTextLabel(
        statusPanel,
        "Gold: 0",
        font,
        infoTextSize,
        Enum.TextXAlignment.Left,
        "GoldLabel"
    )
    goldLabel.LayoutOrder = 4
    goldLabel.Size = UDim2.new(1, 0, 0, infoTextSize + 6)

    local xpConfig = uiConfig.XP or {}

    local xpPanel = Instance.new("Frame")
    xpPanel.Name = "XPPanel"
    xpPanel.BackgroundColor3 = panelBackground
    xpPanel.BackgroundTransparency = panelTransparency
    xpPanel.BorderSizePixel = 0
    xpPanel.Size = UDim2.new(1, 0, 0, 0)
    xpPanel.AutomaticSize = Enum.AutomaticSize.Y
    xpPanel.Parent = leftColumn

    local xpCorner = Instance.new("UICorner")
    xpCorner.CornerRadius = UDim.new(0, panelCornerRadius)
    xpCorner.Parent = xpPanel

    local xpStroke = Instance.new("UIStroke")
    xpStroke.Color = panelStrokeColor
    xpStroke.Thickness = panelStrokeThickness
    xpStroke.Transparency = panelStrokeTransparency
    xpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    xpStroke.Parent = xpPanel

    local xpPadding = Instance.new("UIPadding")
    xpPadding.PaddingTop = UDim.new(0, panelPadding)
    xpPadding.PaddingBottom = UDim.new(0, panelPadding)
    xpPadding.PaddingLeft = UDim.new(0, panelPadding)
    xpPadding.PaddingRight = UDim.new(0, panelPadding)
    xpPadding.Parent = xpPanel

    local xpLayout = Instance.new("UIListLayout")
    xpLayout.FillDirection = Enum.FillDirection.Vertical
    xpLayout.SortOrder = Enum.SortOrder.LayoutOrder
    xpLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    xpLayout.Padding = UDim.new(0, 6)
    xpLayout.Parent = xpPanel

    local xpHeader = Instance.new("Frame")
    xpHeader.Name = "XPHeader"
    xpHeader.BackgroundTransparency = 1
    xpHeader.Size = UDim2.new(1, 0, 0, xpConfig.LabelHeight or 24)
    xpHeader.LayoutOrder = 1
    xpHeader.Parent = xpPanel

    local levelWidth = xpConfig.LevelWidth or 54
    local levelSpacing = xpConfig.LevelSpacing or 10
    local xpLabel = createTextLabel(
        xpHeader,
        (xpConfig.LabelPrefix or "XP") .. " 0",
        font,
        xpConfig.LabelTextSize or infoTextSize,
        Enum.TextXAlignment.Left,
        "XPText"
    )
    xpLabel.Size = UDim2.new(1, -(levelWidth + levelSpacing), 1, 0)

    local levelLabel = createTextLabel(
        xpHeader,
        "Lv 1",
        boldFont,
        xpConfig.LevelTextSize or alertTextSize,
        Enum.TextXAlignment.Right,
        "LevelLabel"
    )
    levelLabel.AnchorPoint = Vector2.new(1, 0.5)
    levelLabel.Position = UDim2.new(1, 0, 0.5, 0)
    levelLabel.Size = UDim2.new(0, levelWidth, 1, 0)

    local xpBar = Instance.new("Frame")
    xpBar.Name = "XPBar"
    xpBar.BackgroundColor3 = xpConfig.BackgroundColor or Color3.fromRGB(18, 24, 32)
    xpBar.BackgroundTransparency = xpConfig.BackgroundTransparency or 0.45
    xpBar.BorderSizePixel = 0
    xpBar.Size = UDim2.new(1, 0, 0, xpConfig.BarHeight or 18)
    xpBar.LayoutOrder = 2
    xpBar.Parent = xpPanel

    local xpBarCorner = Instance.new("UICorner")
    xpBarCorner.CornerRadius = UDim.new(0, xpConfig.CornerRadius or 9)
    xpBarCorner.Parent = xpBar

    local xpFill = Instance.new("Frame")
    xpFill.Name = "Fill"
    xpFill.BackgroundColor3 = xpConfig.FillColor or Color3.fromRGB(88, 182, 255)
    xpFill.BackgroundTransparency = xpConfig.FillTransparency or 0.05
    xpFill.BorderSizePixel = 0
    xpFill.Size = UDim2.new(0, 0, 1, 0)
    xpFill.Parent = xpBar

    local xpFillCorner = Instance.new("UICorner")
    xpFillCorner.CornerRadius = UDim.new(0, xpConfig.CornerRadius or 9)
    xpFillCorner.Parent = xpFill

    local alertArea = Instance.new("Frame")
    alertArea.Name = "AlertArea"
    alertArea.BackgroundTransparency = 1
    alertArea.Position = UDim2.new(0, sidePanelWidth + sectionSpacing, 0, uiConfig.AlertAreaOffset or 12)
    alertArea.Size = UDim2.new(1, -(sidePanelWidth + sectionSpacing), 0, uiConfig.AlertAreaHeight or 160)
    alertArea.Parent = safeFrame

    local alertLayout = Instance.new("UIListLayout")
    alertLayout.FillDirection = Enum.FillDirection.Vertical
    alertLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    alertLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    alertLayout.Padding = UDim.new(0, 8)
    alertLayout.Parent = alertArea

    local waveAnnouncement = createTextLabel(
        alertArea,
        "",
        boldFont,
        alertTextSize,
        Enum.TextXAlignment.Center,
        "WaveAnnouncement"
    )
    waveAnnouncement.LayoutOrder = 1
    waveAnnouncement.TextTransparency = 1
    waveAnnouncement.Size = UDim2.new(1, 0, 0, uiConfig.WaveAnnouncementHeight or 48)

    local messageLabel = createTextLabel(
        alertArea,
        "",
        boldFont,
        alertTextSize,
        Enum.TextXAlignment.Center,
        "MessageLabel"
    )
    messageLabel.LayoutOrder = 2
    messageLabel.TextTransparency = 1
    messageLabel.Size = UDim2.new(1, 0, 0, uiConfig.MessageHeight or 40)

    local reservedAlert = Instance.new("Frame")
    reservedAlert.Name = "ReservedAlerts"
    reservedAlert.BackgroundTransparency = uiConfig.AlertBackgroundTransparency or 0.35
    reservedAlert.BackgroundColor3 = uiConfig.AlertBackgroundColor or Color3.fromRGB(18, 24, 32)
    reservedAlert.BorderSizePixel = 0
    reservedAlert.Size = UDim2.new(1, 0, 0, uiConfig.ReservedAlertHeight or 52)
    reservedAlert.LayoutOrder = 0
    reservedAlert.Parent = alertArea

    local reservedLabel = createTextLabel(
        reservedAlert,
        "",
        font,
        alertTextSize,
        Enum.TextXAlignment.Center,
        "ReservedLabel"
    )
    reservedLabel.Text = ""

    local partyContainer = Instance.new("Frame")
    partyContainer.Name = "PartyContainer"
    partyContainer.BackgroundTransparency = 1
    partyContainer.AnchorPoint = Vector2.new(1, 0)
    partyContainer.Position = UDim2.new(1, 0, 0, sectionSpacing)
    partyContainer.Size = UDim2.new(0, uiConfig.Party and uiConfig.Party.Width or 220, 0, 10)
    partyContainer.AutomaticSize = Enum.AutomaticSize.Y
    partyContainer.Parent = safeFrame

    local partyLayout = Instance.new("UIListLayout")
    partyLayout.FillDirection = Enum.FillDirection.Vertical
    partyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    partyLayout.Padding = UDim.new(0, uiConfig.Party and uiConfig.Party.Padding or 6)
    partyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    partyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    partyLayout.Parent = partyContainer

    local partyEmptyLabel = createTextLabel(
        partyContainer,
        "",
        font,
        smallTextSize,
        Enum.TextXAlignment.Right,
        "PartyEmptyLabel"
    )
    partyEmptyLabel.LayoutOrder = -1
    partyEmptyLabel.TextTransparency = 0.45
    partyEmptyLabel.Text = ""

    local abilityFrame = Instance.new("Frame")
    abilityFrame.Name = "AbilityFrame"
    abilityFrame.BackgroundTransparency = 1
    abilityFrame.AnchorPoint = Vector2.new(0, 1)
    abilityFrame.Position = UDim2.new(0, 0, 1, -abilityBottomOffset)
    abilityFrame.Size = UDim2.new(0, abilityWidth, 0, abilityHeight)
    abilityFrame.Parent = safeFrame

    local abilityLayout = Instance.new("UIListLayout")
    abilityLayout.FillDirection = Enum.FillDirection.Horizontal
    abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
    abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    abilityLayout.Padding = UDim.new(0, abilitySpacing)
    abilityLayout.Parent = abilityFrame

    local skillSlot = createCooldownSlot(abilityFrame, {
        Name = "SkillSlot",
        Size = skillSlotSize,
        BoldFont = boldFont,
        TextSize = abilityConfig.SkillTextSize or infoTextSize,
        KeyText = abilityConfig.SkillKey or "Q",
        ReadyText = abilityConfig.SkillReadyText or "Ready",
        ReadyColor = abilityConfig.SkillReadyColor or Color3.fromRGB(255, 235, 200),
        BackgroundColor = abilityConfig.SkillBackgroundColor or Color3.fromRGB(18, 24, 32),
        BackgroundTransparency = abilityConfig.SkillBackgroundTransparency or 0.25,
        FillColor = abilityConfig.SkillFillColor or Color3.fromRGB(255, 196, 110),
        FillTransparency = abilityConfig.SkillFillTransparency or 0.15,
        StrokeColor = abilityConfig.SkillStrokeColor or Color3.fromRGB(255, 196, 110),
        StrokeThickness = abilityConfig.SkillStrokeThickness or 2,
        StrokeTransparency = abilityConfig.SkillStrokeTransparency or 0.2,
        LayoutOrder = 1,
        KeyLabelY = abilityConfig.SkillKeyLabelY or 0.32,
        CooldownLabelY = abilityConfig.SkillCooldownLabelY or 0.72,
    })

    local dashSlot = createCooldownSlot(abilityFrame, {
        Name = "DashSlot",
        Size = dashSize,
        BoldFont = boldFont,
        TextSize = smallTextSize,
        KeyText = dashConfig.KeyText or "E",
        ReadyText = dashConfig.ReadyText or "Ready",
        ReadyColor = dashConfig.ReadyColor or Color3.fromRGB(180, 255, 205),
        BackgroundColor = dashConfig.BackgroundColor or Color3.fromRGB(18, 24, 32),
        BackgroundTransparency = dashConfig.BackgroundTransparency or 0.25,
        FillColor = dashConfig.FillColor or Color3.fromRGB(120, 200, 255),
        FillTransparency = dashConfig.FillTransparency or 0.15,
        StrokeColor = dashConfig.StrokeColor or Color3.fromRGB(120, 200, 255),
        StrokeThickness = dashConfig.StrokeThickness or 2,
        StrokeTransparency = dashConfig.StrokeTransparency or 0.2,
        LayoutOrder = 2,
        KeyLabelY = dashConfig.KeyLabelY or 0.32,
        CooldownLabelY = dashConfig.CooldownLabelY or 0.72,
    })

    self:CaptureInterfaceElements(screen, abilityConfig, dashConfig, uiConfig)
end
local function formatTime(seconds: number): string
    seconds = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(seconds / 60)
    local remaining = seconds % 60
    return string.format("%02d:%02d", minutes, remaining)
end

function HUDController:Update(state)
    if not self.Elements.WaveLabel then
        return
    end

    local wave = state.Wave or 0
    self.Elements.WaveLabel.Text = string.format("Wave %d", wave)

    local enemies = state.RemainingEnemies or 0
    if typeof(enemies) == "number" then
        enemies = math.max(0, math.floor(enemies + 0.5))
    else
        enemies = 0
    end
    self.Elements.EnemyLabel.Text = string.format("Enemies: %d", enemies)

    if state.Countdown and state.Countdown > 0 then
        self.Elements.TimerLabel.Text = string.format("Start In: %ds", math.ceil(state.Countdown))
    elseif state.TimeRemaining and state.TimeRemaining >= 0 then
        self.Elements.TimerLabel.Text = "Time Left: " .. formatTime(state.TimeRemaining)
    else
        self.Elements.TimerLabel.Text = "Time: ∞"
    end

    local gold = state.Gold or 0
    if typeof(gold) == "number" then
        gold = math.floor(gold + 0.5)
    else
        gold = 0
    end
    self.Elements.GoldLabel.Text = string.format("Gold: %d", gold)

    self:UpdateXP(state)
    self:UpdateSkillCooldowns(state.SkillCooldowns)
    self:UpdateDashCooldown(state.DashCooldown)
    self:UpdateParty(state.Party)
end

function HUDController:UpdateXP(state)
    local xpFill = self.Elements.XPFill
    local xpLabel = self.Elements.XPTextLabel
    local levelLabel = self.Elements.LevelLabel

    if not xpFill or not xpLabel or not levelLabel then
        return
    end

    local xpConfig = Config.UI and Config.UI.XP or {}
    local prefix = xpConfig.LabelPrefix or "XP"

    local levelValue = tonumber(state.Level)
    if levelValue then
        levelLabel.Text = string.format("Lv %d", math.max(1, math.floor(levelValue + 0.5)))
    else
        levelLabel.Text = "Lv 1"
    end

    local progress = state.XPProgress
    local current = 0
    local required = 0
    local ratio = 0

    if typeof(progress) == "table" then
        if typeof(progress.Ratio) == "number" then
            ratio = math.clamp(progress.Ratio, 0, 1)
        end
        local currentValue = progress.Current or progress.XP or progress.Value or progress.Amount
        if typeof(currentValue) == "number" then
            current = currentValue
        end
        local requiredValue = progress.Required or progress.Max or progress.Goal or progress.ToNext
        if typeof(requiredValue) == "number" then
            required = requiredValue
        end
    end

    if ratio <= 0 then
        local fallbackCurrent = state.XP or current
        local fallbackRequired = state.NextLevelXP or state.XPGoal or required
        if typeof(fallbackCurrent) == "number" then
            current = fallbackCurrent
        end
        if typeof(fallbackRequired) == "number" then
            required = fallbackRequired
        end
        if required > 0 then
            ratio = math.clamp(current / required, 0, 1)
        elseif typeof(progress) == "table" and typeof(progress.Total) == "number" and progress.Total > 0 then
            current = progress.Total
            ratio = 1
        else
            ratio = 0
        end
    end

    local totalXP = state.XP or current

    xpFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)

    if required > 0 then
        xpLabel.Text = string.format("%s %d / %d", prefix, math.floor(current + 0.5), math.floor(required + 0.5))
    elseif ratio > 0 then
        xpLabel.Text = string.format("%s %d%%", prefix, math.floor(ratio * 100 + 0.5))
    elseif typeof(totalXP) == "number" then
        xpLabel.Text = string.format("%s %d", prefix, math.floor(totalXP + 0.5))
    else
        xpLabel.Text = prefix
    end
end

function HUDController:UpdateSkillCooldowns(skillTable)
    local skillFill = self.Elements.SkillFill
    local cooldownLabel = self.Elements.SkillCooldownLabel
    local keyLabel = self.Elements.SkillKeyLabel
    if not skillFill or not cooldownLabel then
        return
    end

    if keyLabel then
        keyLabel.Text = self.SkillDisplayKey or "Q"
    end

    local primaryId = self.PrimarySkillId
    if not primaryId then
        local abilityConfig = Config.UI and Config.UI.Abilities
        if abilityConfig then
            primaryId = abilityConfig.PrimarySkillId
        end
        primaryId = primaryId or "AOE_Blast"
    end

    local info
    if typeof(skillTable) == "table" then
        if primaryId and typeof(skillTable[primaryId]) == "table" then
            info = skillTable[primaryId]
        elseif typeof(skillTable.Primary) == "table" then
            info = skillTable.Primary
        else
            for _, entry in pairs(skillTable) do
                if typeof(entry) == "table" then
                    info = entry
                    break
                end
            end
        end
    end

    local readyText = self.SkillReadyText or "Ready"
    local readyColor = self.SkillReadyColor or Color3.fromRGB(255, 235, 200)

    local cooldown = 0
    local remaining = 0

    if info and typeof(info) == "table" then
        if typeof(info.Cooldown) == "number" then
            cooldown = math.max(0, info.Cooldown)
        end
        if typeof(info.ReadyTime) == "number" then
            local now = Workspace:GetServerTimeNow()
            remaining = math.max(0, info.ReadyTime - now)
        elseif typeof(info.Remaining) == "number" then
            remaining = math.max(0, info.Remaining)
        elseif typeof(info.Timestamp) == "number" then
            local now = Workspace:GetServerTimeNow()
            local endTime = info.EndTime
            if typeof(endTime) == "number" then
                remaining = math.max(0, endTime - now)
            else
                local elapsed = now - info.Timestamp
                remaining = math.max(0, cooldown - elapsed)
            end
        end
    end

    local progress
    if cooldown > 0 then
        progress = 1 - math.clamp(remaining / cooldown, 0, 1)
    elseif remaining > 0 then
        progress = 0
    else
        progress = 1
    end

    skillFill.Size = UDim2.new(1, 0, progress, 0)

    if remaining > 0.05 then
        cooldownLabel.Text = string.format("%.1f", remaining)
        cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
    else
        cooldownLabel.Text = readyText
        cooldownLabel.TextColor3 = readyColor
    end
end

function HUDController:UpdateDashCooldown(dashData)
    local dashFill = self.Elements.DashFill
    local dashCooldownLabel = self.Elements.DashCooldownLabel
    if not dashFill or not dashCooldownLabel then
        return
    end

    local remaining = 0
    local cooldown = 0

    if typeof(dashData) == "table" then
        if typeof(dashData.Cooldown) == "number" then
            cooldown = math.max(0, dashData.Cooldown)
        end
        if typeof(dashData.ReadyTime) == "number" then
            local now = Workspace:GetServerTimeNow()
            remaining = math.max(0, dashData.ReadyTime - now)
        elseif typeof(dashData.Remaining) == "number" then
            remaining = math.max(0, dashData.Remaining)
        end
    end

    local progress
    if cooldown > 0 then
        progress = 1 - math.clamp(remaining / cooldown, 0, 1)
    elseif remaining > 0 then
        progress = 0
    else
        progress = 1
    end

    dashFill.Size = UDim2.new(1, 0, progress, 0)

    local readyText = self.DashReadyText or "Ready"
    local readyColor = self.DashReadyColor or Color3.fromRGB(180, 255, 205)

    if remaining <= 0.05 then
        dashCooldownLabel.Text = readyText
        dashCooldownLabel.TextColor3 = readyColor
    else
        dashCooldownLabel.Text = string.format("%.1f", remaining)
        dashCooldownLabel.TextColor3 = Color3.new(1, 1, 1)
    end
end

function HUDController:UpdateParty(partyState)
    local container = self.Elements.PartyContainer
    if not container then
        return
    end

    local entries = self.PartyEntries
    local order = 0
    local used = {}

    local list = {}
    if typeof(partyState) == "table" then
        if #partyState > 0 then
            for index, item in ipairs(partyState) do
                table.insert(list, item)
            end
        else
            for _, item in pairs(partyState) do
                table.insert(list, item)
            end
            table.sort(list, function(a, b)
                local aOrder = typeof(a) == "table" and (a.Order or a.Index or 0) or 0
                local bOrder = typeof(b) == "table" and (b.Order or b.Index or 0) or 0
                return aOrder < bOrder
            end)
        end
    end

    for _, data in ipairs(list) do
        local key = nil
        if typeof(data) == "table" then
            if data.Id then
                key = tostring(data.Id)
            elseif data.UserId then
                key = tostring(data.UserId)
            elseif data.Name then
                key = string.lower(data.Name)
            end
        end
        key = key or tostring(order)

        local entry = entries[key]
        if not entry then
            entry = self:CreatePartyEntry(container)
            entries[key] = entry
        end

        order += 1
        entry.Frame.LayoutOrder = order
        self:ApplyPartyEntry(entry, data)
        entry.Frame.Visible = true
        used[key] = true
    end

    for key, entry in pairs(entries) do
        if not used[key] then
            entry.Frame.Visible = false
        end
    end

    if order == 0 and self.Elements.PartyEmptyLabel then
        self.Elements.PartyEmptyLabel.Text = Config.UI.Party and Config.UI.Party.EmptyText or ""
        self.Elements.PartyEmptyLabel.Visible = (self.Elements.PartyEmptyLabel.Text ~= "")
    elseif self.Elements.PartyEmptyLabel then
        self.Elements.PartyEmptyLabel.Visible = false
    end
end

function HUDController:CreatePartyEntry(parent: Instance)
    local partyConfig = Config.UI and Config.UI.Party or {}
    local entryHeight = partyConfig.EntryHeight or 42
    local entry = Instance.new("Frame")
    entry.Name = "PartyEntry"
    entry.BackgroundColor3 = partyConfig.BackgroundColor or Color3.fromRGB(18, 24, 32)
    entry.BackgroundTransparency = partyConfig.BackgroundTransparency or 0.25
    entry.BorderSizePixel = 0
    entry.Size = UDim2.new(1, 0, 0, entryHeight)
    entry.Visible = false
    entry.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, partyConfig.CornerRadius or 8)
    corner.Parent = entry

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = partyConfig.StrokeThickness or 1.5
    stroke.Color = partyConfig.StrokeColor or Color3.fromRGB(90, 120, 150)
    stroke.Transparency = partyConfig.StrokeTransparency or 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = entry

    local fill = Instance.new("Frame")
    fill.Name = "HealthFill"
    fill.BackgroundColor3 = partyConfig.HealthFillColor or Color3.fromRGB(88, 255, 120)
    fill.BackgroundTransparency = partyConfig.HealthFillTransparency or 0.25
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Parent = entry

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, partyConfig.CornerRadius or 8)
    fillCorner.Parent = fill

    local nameLabel = createTextLabel(entry, "", Config.UI and (Config.UI.Party and Config.UI.Party.Font or Config.UI.Font) or Enum.Font.Gotham, partyConfig.NameTextSize or 16, Enum.TextXAlignment.Left)
    nameLabel.Position = UDim2.new(0, 10, 0, 0)
    nameLabel.Size = UDim2.new(0.5, -10, 1, 0)

    local healthLabel = createTextLabel(entry, "", Config.UI and (Config.UI.Party and Config.UI.Party.Font or Config.UI.Font) or Enum.Font.Gotham, partyConfig.HealthTextSize or 16, Enum.TextXAlignment.Right)
    healthLabel.AnchorPoint = Vector2.new(1, 0)
    healthLabel.Position = UDim2.new(1, -10, 0, 0)
    healthLabel.Size = UDim2.new(0.5, 0, 1, 0)

    return {
        Frame = entry,
        HealthFill = fill,
        NameLabel = nameLabel,
        HealthLabel = healthLabel,
    }
end

function HUDController:ApplyPartyEntry(entry, data)
    local name = "Player"
    local health = 0
    local maxHealth = 0

    if typeof(data) == "table" then
        name = data.DisplayName or data.Name or name
        health = data.Health or data.Current or data.Value or health
        maxHealth = data.MaxHealth or data.Max or data.Capacity or maxHealth
        if data.UserId == Players.LocalPlayer.UserId or data.IsLocal then
            entry.Frame.BackgroundTransparency = 0.18
        else
            entry.Frame.BackgroundTransparency = Config.UI and Config.UI.Party and Config.UI.Party.BackgroundTransparency or 0.25
        end
    end

    entry.NameLabel.Text = name

    local ratio = 0
    if typeof(health) == "number" then
        health = math.max(0, health)
    else
        health = 0
    end
    if typeof(maxHealth) == "number" and maxHealth > 0 then
        maxHealth = math.max(maxHealth, health, 1)
        ratio = math.clamp(health / maxHealth, 0, 1)
    elseif typeof(data) == "table" and typeof(data.Ratio) == "number" then
        ratio = math.clamp(data.Ratio, 0, 1)
        if maxHealth <= 0 then
            maxHealth = math.floor(health / math.max(ratio, 0.0001))
        end
    end

    entry.HealthFill.Size = UDim2.new(ratio, 0, 1, 0)

    if maxHealth > 0 then
        entry.HealthLabel.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))
    elseif ratio > 0 then
        entry.HealthLabel.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
    else
        entry.HealthLabel.Text = "--"
    end
end

function HUDController:ShowMessage(text: string)
    if not self.Elements.MessageLabel then
        return
    end

    if self.LastMessageTask then
        self.LastMessageTask:Cancel()
        self.LastMessageTask = nil
    end

    local messageLabel = self.Elements.MessageLabel
    messageLabel.Text = text
    messageLabel.TextTransparency = 0

    local duration = (Config.UI and Config.UI.MessageDuration) or 3
    local thread = task.spawn(function()
        task.wait(duration)
        messageLabel.TextTransparency = 1
    end)

    self.LastMessageTask = {
        Cancel = function()
            task.cancel(thread)
            messageLabel.TextTransparency = 1
        end,
    }
end

function HUDController:PlayWaveAnnouncement(wave: number)
    local label = self.Elements.WaveAnnouncement
    if not label then
        return
    end

    label.Text = string.format("Wave %d", wave)
    label.TextTransparency = 0

    task.spawn(function()
        task.wait(1.2)
        label.TextTransparency = 1
    end)
end


function HUDController:ShowAOE(position: Vector3, radius: number)
    if typeof(position) ~= "Vector3" then
        return
    end

    radius = typeof(radius) == "number" and radius or 0
    if radius <= 0 then
        return
    end

    local ignore = {}
    local player = Players.LocalPlayer
    if player and player.Character then
        table.insert(ignore, player.Character)
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    if #ignore > 0 then
        params.FilterDescendantsInstances = ignore
    end

    local origin = position + Vector3.new(0, 40, 0)
    local rayResult = Workspace:Raycast(origin, Vector3.new(0, -160, 0), params)
    local groundPosition
    if rayResult then
        groundPosition = Vector3.new(position.X, rayResult.Position.Y + 0.1, position.Z)
    else
        groundPosition = Vector3.new(position.X, position.Y, position.Z)
    end

    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(120, 200, 255)
    ring.Transparency = 0.2
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.TopSurface = Enum.SurfaceType.Smooth
    ring.BottomSurface = Enum.SurfaceType.Smooth
    local height = math.max(0.35, radius * 0.08)
    ring.Size = Vector3.new(radius * 2, height, radius * 2)
    ring.CFrame = CFrame.new(groundPosition) * CFrame.Angles(math.rad(90), 0, 0)
    ring.Parent = Workspace

    local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 1,
        Size = Vector3.new(radius * 2.4, height * 0.6, radius * 2.4),
    })

    tween.Completed:Connect(function()
        ring:Destroy()
    end)

    tween:Play()
end

return HUDController
