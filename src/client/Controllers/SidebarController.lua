local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local SIDEBAR_ROW_COLOR = Color3.fromRGB(18, 24, 32)
local STATS_ICON_COLOR = Color3.fromRGB(155, 91, 217)

local STAT_CHOICE_CONFIG = {
    AttackPower = {
        label = "공격력",
        kind = "percent",
        decimals = 0,
        totalDecimals = 0,
        total = function(stats)
            local value = stats and stats.AttackPowerBonus
            if typeof(value) == "number" then
                return value * 100
            end
        end,
    },
    CritChance = {
        label = "치명타 확률",
        kind = "percent",
        decimals = 1,
        totalDecimals = 1,
        total = function(stats)
            local value = stats and stats.CritChance
            if typeof(value) == "number" then
                return value * 100
            end
        end,
    },
    CritDamage = {
        label = "치명타 피해",
        kind = "percent",
        decimals = 1,
        totalDecimals = 1,
        total = function(stats)
            local value = stats and stats.CritDamageMultiplier
            if typeof(value) == "number" then
                return (value - 1) * 100
            end
        end,
    },
    Lifesteal = {
        label = "흡혈",
        kind = "percent",
        decimals = 1,
        totalDecimals = 1,
        total = function(stats)
            local value = stats and stats.Lifesteal
            if typeof(value) == "number" then
                return value * 100
            end
        end,
    },
    AttackRange = {
        label = "사거리",
        kind = "number",
        decimals = 1,
        totalDecimals = 1,
        total = function(stats)
            local value = stats and stats.AttackRangeBonus
            if typeof(value) == "number" then
                return value
            end
        end,
    },
    MaxHealth = {
        label = "체력",
        kind = "percent",
        decimals = 0,
        totalDecimals = 0,
        total = function(stats)
            local value = stats and stats.MaxHealthBonus
            if typeof(value) == "number" then
                return value * 100
            end
        end,
    },
    MoveSpeed = {
        label = "이동 속도",
        kind = "percent",
        decimals = 1,
        totalDecimals = 1,
        total = function(stats)
            local value = stats and stats.MoveSpeedBonus
            if typeof(value) == "number" then
                return value * 100
            end
        end,
    },
    SkillCooldown = {
        label = "Q 쿨타임",
        kind = "percent",
        decimals = 1,
        totalDecimals = 1,
        invert = true,
        total = function(stats)
            local multiplier = stats and stats.SkillCooldownMultiplier
            if typeof(multiplier) == "number" and multiplier < 0.999 then
                local reduction = (1 - multiplier) * 100
                if reduction > 0 then
                    return -reduction
                end
            end
        end,
    },
}

local STAT_SUMMARY_ORDER = {
    "AttackPower",
    "CritChance",
    "CritDamage",
    "Lifesteal",
    "AttackRange",
    "MaxHealth",
    "SkillCooldown",
    "MoveSpeed",
}

local VALUE_EPSILON = 1e-4

local function formatStatValue(value, decimals, kind)
    decimals = decimals or 0
    local format = "%+." .. tostring(decimals) .. "f"
    local text = string.format(format, value)
    if kind == "percent" then
        text ..= "%"
    end
    return text
end

local function buildSummaryLines(stats)
    local lines = {}
    if typeof(stats) ~= "table" then
        return lines
    end

    for _, key in ipairs(STAT_SUMMARY_ORDER) do
        local config = STAT_CHOICE_CONFIG[key]
        if config and typeof(config.total) == "function" then
            local totalValue = config.total(stats)
            if typeof(totalValue) == "number" and math.abs(totalValue) > VALUE_EPSILON then
                local decimals = config.totalDecimals or config.decimals or 0
                local valueText = formatStatValue(totalValue, decimals, config.kind)
                table.insert(lines, string.format("%s %s", config.label, valueText))
            end
        end
    end

    return lines
end

local function formatLastChoice(stats, choice)
    if typeof(choice) ~= "table" then
        return nil
    end

    if choice.kind ~= "stat" then
        if typeof(choice.name) == "string" and choice.name ~= "" then
            return choice.name
        end
        if typeof(choice.desc) == "string" and choice.desc ~= "" then
            return choice.desc
        end
        return nil
    end

    local statKey = choice.stat
    if typeof(statKey) ~= "string" then
        if typeof(choice.name) == "string" and choice.name ~= "" then
            return choice.name
        end
        if typeof(choice.desc) == "string" and choice.desc ~= "" then
            return choice.desc
        end
        return nil
    end

    local config = STAT_CHOICE_CONFIG[statKey]
    if not config then
        if typeof(choice.name) == "string" and choice.name ~= "" then
            return choice.name
        end
        if typeof(choice.desc) == "string" and choice.desc ~= "" then
            return choice.desc
        end
        return nil
    end

    local value = tonumber(choice.value)
    if not value or math.abs(value) <= VALUE_EPSILON then
        if typeof(choice.name) == "string" and choice.name ~= "" then
            return choice.name
        end
        if typeof(choice.desc) == "string" and choice.desc ~= "" then
            return choice.desc
        end
        return nil
    end

    local kind = config.kind or "percent"
    local decimals = config.decimals or 0
    local displayValue = kind == "percent" and (value * 100) or value
    if config.invert then
        displayValue = -displayValue
    end

    local result = string.format("%s %s", config.label, formatStatValue(displayValue, decimals, kind))

    if typeof(config.total) == "function" then
        local totalValue = config.total(stats)
        if typeof(totalValue) == "number" and math.abs(totalValue) > VALUE_EPSILON then
            local totalDecimals = config.totalDecimals or decimals
            local totalText = formatStatValue(totalValue, totalDecimals, kind)
            result = string.format("%s (총 %s)", result, totalText)
        end
    end

    return result
end

local function createStatsRow(container: Instance)
    if not container or not container:IsA("Frame") then
        return nil
    end

    local row = Instance.new("Frame")
    row.Name = "StatsRow"
    row.BackgroundColor3 = SIDEBAR_ROW_COLOR
    row.BackgroundTransparency = 0.25
    row.BorderSizePixel = 0
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.Size = UDim2.new(0, 260, 0, 0)
    row.LayoutOrder = 4
    row.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = row

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = row

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding = UDim.new(0, 10)
    layout.Parent = row

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.new(0, 20, 0, 20)
    icon.Image = "rbxassetid://0"
    icon.ImageColor3 = STATS_ICON_COLOR
    icon.Parent = row

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.Text = "강화: 없음"
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextSize = 16
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Size = UDim2.new(1, -30, 0, 0)
    label.Parent = row

    return row
end

local SidebarController = Knit.CreateController({
    Name = "SidebarController",
})

function SidebarController:KnitInit()
    self.Screen = nil
    self.PlayerGui = nil
    self.Rows = {}
    self.DownCount = 0
    self.RushResetToken = 0
    self.ActiveTweens = {}
    self.LastSessionResetClock = 0
    self.LastStatsText = nil
    self.PendingStatsText = nil
end

local function isSidebar(screen: Instance): boolean
    return screen and screen:IsA("ScreenGui") and screen.Name == "Sidebar"
end

local function waitForChildOfClass(parent: Instance?, name: string, className: string, timeout: number?)
    if not parent then
        return nil
    end

    local child = parent:FindFirstChild(name)
    if child and child:IsA(className) then
        return child
    end

    local startTime = os.clock()
    local remaining = timeout

    while true do
        if timeout then
            remaining = math.max(0, timeout - (os.clock() - startTime))
            if remaining <= 0 then
                break
            end
        end

        child = parent:WaitForChild(name, remaining)
        if not child then
            break
        end

        if child:IsA(className) then
            return child
        end

        -- Wrong class; avoid tight loops by breaking out.
        break
    end

    return nil
end

function SidebarController:AttachInterface(screen: ScreenGui)
    if not isSidebar(screen) then
        return
    end

    if self.Screen == screen then
        return
    end

    self.Screen = screen
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true

    local container = waitForChildOfClass(screen, "Container", "Frame")
    if not container then
        return
    end
    if container and container:IsA("Frame") and container.AutomaticSize == Enum.AutomaticSize.None then
        container.AutomaticSize = Enum.AutomaticSize.Y
    end
    local bossRow = waitForChildOfClass(container, "BossRow", "Frame")
    local downRow = waitForChildOfClass(container, "DownRow", "Frame")
    local rushRow = waitForChildOfClass(container, "RushRow", "Frame")
    local statsRow = waitForChildOfClass(container, "StatsRow", "Frame")
    if container and not statsRow then
        statsRow = createStatsRow(container)
    end

    local function applyStatsLabelSettings(label: TextLabel)
        if not label or not label:IsA("TextLabel") then
            return
        end

        if label.AutomaticSize == Enum.AutomaticSize.None then
            label.AutomaticSize = Enum.AutomaticSize.Y
        end

        label.TextWrapped = true
        label.Size = UDim2.new(1, -30, 0, 0)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
    end

    local function capture(rowKey, rowInstance)
        if not rowInstance or not rowInstance:IsA("Frame") then
            return nil
        end

        local label = waitForChildOfClass(rowInstance, "Label", "TextLabel", 2)
        if not label then
            label = rowInstance:FindFirstChildWhichIsA("TextLabel", true)
        end

        if rowInstance.Name == "StatsRow" and rowInstance.AutomaticSize == Enum.AutomaticSize.None then
            rowInstance.AutomaticSize = Enum.AutomaticSize.Y
        end

        local captured = {
            Frame = rowInstance,
            Label = label,
        }

        if rowInstance.Name == "StatsRow" then
            if label and label:IsA("TextLabel") then
                applyStatsLabelSettings(label)
            else
                task.spawn(function()
                    local statsLabel = waitForChildOfClass(rowInstance, "Label", "TextLabel")
                    if not statsLabel then
                        statsLabel = rowInstance:FindFirstChildWhichIsA("TextLabel", true)
                    end
                    if statsLabel and statsLabel:IsA("TextLabel") then
                        captured.Label = statsLabel
                        applyStatsLabelSettings(statsLabel)
                        if self.Rows and self.Rows[rowKey] == captured then
                            self:SetStatsText(self.PendingStatsText or self.LastStatsText or "강화: 없음")
                        end
                    end
                end)
            end
        end

        return captured
    end

    self.Rows = {
        Boss = capture("Boss", bossRow),
        Down = capture("Down", downRow),
        Rush = capture("Rush", rushRow),
        Stats = capture("Stats", statsRow),
    }

    for _, row in pairs(self.Rows) do
        if row and row.Frame and not row.Frame:FindFirstChildOfClass("UIScale") then
            local scale = Instance.new("UIScale")
            scale.Scale = 1
            scale.Parent = row.Frame
        end
    end

    self:ResetState(false)
end

function SidebarController:ResetState(resetStatsText)
    if resetStatsText == nil then
        resetStatsText = true
    end

    self.DownCount = 0
    self.RushResetToken = self.RushResetToken + 1
    self.LastSessionResetClock = os.clock()
    if resetStatsText then
        self.LastStatsText = nil
        self.PendingStatsText = "강화: 없음"
    end

    if self.Rows.Boss and self.Rows.Boss.Label then
        self.Rows.Boss.Label.Text = "보스: 대기중"
    end

    if self.Rows.Down and self.Rows.Down.Label then
        self.Rows.Down.Label.Text = "팀원 사망: 0"
    end

    if self.Rows.Rush and self.Rows.Rush.Label then
        self.Rows.Rush.Label.Text = "러쉬: -"
    end

    local statsText = self.PendingStatsText or "강화: 없음"
    self:SetStatsText(statsText)
end

function SidebarController:PlayPulse(row)
    if not row or not row.Frame then
        return
    end

    local scale = row.Frame:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Scale = 1
        scale.Parent = row.Frame
    end

    local tweens = self.ActiveTweens[row.Frame]
    if tweens then
        for _, tween in ipairs(tweens) do
            tween:Cancel()
        end
    end

    local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local downInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    local upTween = TweenService:Create(scale, tweenInfo, {Scale = 1.05})
    local downTween = TweenService:Create(scale, downInfo, {Scale = 1})
    local tweenPair = {upTween, downTween}
    self.ActiveTweens[row.Frame] = tweenPair

    upTween.Completed:Connect(function()
        if self.ActiveTweens[row.Frame] == tweenPair then
            downTween:Play()
        end
    end)

    downTween.Completed:Connect(function()
        if self.ActiveTweens[row.Frame] == tweenPair then
            self.ActiveTweens[row.Frame] = nil
        end
        scale.Scale = 1
    end)

    upTween:Play()
end

function SidebarController:SetBossState(text)
    if self.Rows.Boss and self.Rows.Boss.Label then
        self.Rows.Boss.Label.Text = text
        self:PlayPulse(self.Rows.Boss)
    end
end

function SidebarController:SetDownCount(count)
    self.DownCount = count
    if self.Rows.Down and self.Rows.Down.Label then
        self.Rows.Down.Label.Text = string.format("팀원 사망: %d", count)
        self:PlayPulse(self.Rows.Down)
    end
end

function SidebarController:SetRushState(text)
    if self.Rows.Rush and self.Rows.Rush.Label then
        self.Rows.Rush.Label.Text = text
        self:PlayPulse(self.Rows.Rush)
    end
end

function SidebarController:SetStatsText(text)
    local value = text or "강화: 없음"
    self.PendingStatsText = value

    local row = self.Rows.Stats
    if not row or not row.Label then
        return
    end

    row.Label.Text = value
    if self.LastStatsText ~= value then
        self.LastStatsText = value
        self:PlayPulse(row)
    end
end

function SidebarController:ScheduleRushReset()
    local token = self.RushResetToken + 1
    self.RushResetToken = token
    task.delay(3, function()
        if self.RushResetToken == token then
            if self.Rows.Rush and self.Rows.Rush.Label then
                self.Rows.Rush.Label.Text = "러쉬: -"
            end
        end
    end)
end

function SidebarController:BindRemotes()
    Net:GetEvent("BossSpawned").OnClientEvent:Connect(function(spawned)
        if spawned then
            self:SetBossState("보스: 등장!")
        end
    end)

    Net:GetEvent("BossEnraged").OnClientEvent:Connect(function()
        self:SetBossState("보스: 분노!")
    end)

    Net:GetEvent("TeammateDown").OnClientEvent:Connect(function(playerName)
        self:SetDownCount(self.DownCount + 1)
    end)

    Net:GetEvent("RushWarning").OnClientEvent:Connect(function(kind)
        if kind == "pulse" then
            self:SetRushState("러쉬: 잠깐")
        elseif kind == "surge" then
            self:SetRushState("러쉬: 대규모")
        else
            self:SetRushState("러쉬: -")
        end
        self:ScheduleRushReset()
    end)

    Net:GetEvent("HUD").OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then
            return
        end

        local state = payload.State
        local elapsed = payload.Elapsed

        if state == "Active" and typeof(elapsed) == "number" and elapsed <= 0.5 then
            local now = os.clock()
            if now - (self.LastSessionResetClock or 0) > 1 then
                self:ResetState(true)
                self.LastSessionResetClock = now
            end
        end
    end)

    Net:GetEvent("LevelStats").OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then
            self:SetStatsText("강화: 없음")
            return
        end

        local stats = payload.Stats
        local lastChoice = payload.LastChoice
        local summaryLines = buildSummaryLines(stats)
        local outputLines = {}

        local formattedChoice = formatLastChoice(stats, lastChoice)
        if formattedChoice then
            table.insert(outputLines, string.format("최근 강화: %s", formattedChoice))
        elseif typeof(lastChoice) == "table" then
            local fallback = lastChoice.name or lastChoice.desc
            if typeof(fallback) == "string" and fallback ~= "" then
                table.insert(outputLines, string.format("최근 강화: %s", fallback))
            end
        end

        if #summaryLines > 0 then
            table.insert(outputLines, "강화 현황")
            for _, line in ipairs(summaryLines) do
                table.insert(outputLines, line)
            end
        end

        if #outputLines == 0 then
            outputLines = {"강화: 없음"}
        end

        self:SetStatsText(table.concat(outputLines, "\n"))
    end)
end

function SidebarController:KnitStart()
    local player = Players.LocalPlayer
    if not player then
        return
    end

    self.PlayerGui = player:WaitForChild("PlayerGui")

    local function tryAttach(screen)
        if isSidebar(screen) then
            self:AttachInterface(screen)
        end
    end

    local existing = self.PlayerGui:FindFirstChild("Sidebar")
    if existing then
        tryAttach(existing)
    end

    self.PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "Sidebar" then
            task.defer(tryAttach, child)
        end
    end)

    self:BindRemotes()
end

return SidebarController
