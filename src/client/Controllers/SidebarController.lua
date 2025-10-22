local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local SidebarController = Knit.CreateController({
    Name = "SidebarController",
})

local SIDEBAR_ROW_COLOR = Color3.fromRGB(18, 24, 32)
local STATS_ICON_COLOR = Color3.fromRGB(155, 91, 217)

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

local function captureRow(rowInstance: Instance)
    if not rowInstance or not rowInstance:IsA("Frame") then
        return nil
    end

    local label = rowInstance:FindFirstChild("Label")
    if not label or not label:IsA("TextLabel") then
        label = rowInstance:FindFirstChildWhichIsA("TextLabel", true)
    end

    if rowInstance.Name == "StatsRow" and rowInstance.AutomaticSize == Enum.AutomaticSize.None then
        rowInstance.AutomaticSize = Enum.AutomaticSize.Y
    end

    if label and label:IsA("TextLabel") then
        if rowInstance.Name == "StatsRow" then
            if label.AutomaticSize == Enum.AutomaticSize.None then
                label.AutomaticSize = Enum.AutomaticSize.Y
            end
            label.TextWrapped = true
            label.Size = UDim2.new(1, -30, 0, 0)
        end
    end

    return {
        Frame = rowInstance,
        Label = label,
    }
end

function SidebarController:KnitInit()
    self.Screen = nil
    self.PlayerGui = nil
    self.Rows = {}
    self.DownCount = 0
    self.RushResetToken = 0
    self.ActiveTweens = {}
    self.LastSessionResetClock = 0
    self.LastStatsText = nil
end

local function isSidebar(screen: Instance): boolean
    return screen and screen:IsA("ScreenGui") and screen.Name == "Sidebar"
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

    local container = screen:FindFirstChild("Container")
    if container and container:IsA("Frame") and container.AutomaticSize == Enum.AutomaticSize.None then
        container.AutomaticSize = Enum.AutomaticSize.Y
    end
    local bossRow = container and container:FindFirstChild("BossRow")
    local downRow = container and container:FindFirstChild("DownRow")
    local rushRow = container and container:FindFirstChild("RushRow")
    local statsRow = container and container:FindFirstChild("StatsRow")
    if container and (not statsRow or not statsRow:IsA("Frame")) then
        statsRow = createStatsRow(container)
    end

    self.Rows = {
        Boss = captureRow(bossRow),
        Down = captureRow(downRow),
        Rush = captureRow(rushRow),
        Stats = captureRow(statsRow),
    }

    for _, row in pairs(self.Rows) do
        if row and row.Frame and not row.Frame:FindFirstChildOfClass("UIScale") then
            local scale = Instance.new("UIScale")
            scale.Scale = 1
            scale.Parent = row.Frame
        end
    end

    self:ResetState()
end

function SidebarController:ResetState()
    self.DownCount = 0
    self.RushResetToken = self.RushResetToken + 1
    self.LastSessionResetClock = os.clock()
    self.LastStatsText = nil

    if self.Rows.Boss and self.Rows.Boss.Label then
        self.Rows.Boss.Label.Text = "보스: 대기중"
    end

    if self.Rows.Down and self.Rows.Down.Label then
        self.Rows.Down.Label.Text = "팀원 사망: 0"
    end

    if self.Rows.Rush and self.Rows.Rush.Label then
        self.Rows.Rush.Label.Text = "러쉬: -"
    end

    self:SetStatsText("강화: 없음")
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
    local row = self.Rows.Stats
    if not row or not row.Label then
        return
    end

    row.Label.Text = text
    if self.LastStatsText ~= text then
        self.LastStatsText = text
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
                self:ResetState()
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
        local lines = {}

        if typeof(stats) == "table" then
            local function hasValue(value)
                return typeof(value) == "number" and math.abs(value) > 1e-4
            end

            if hasValue(stats.AttackPowerBonus) then
                table.insert(lines, string.format("공격력 +%.0f%%", stats.AttackPowerBonus * 100))
            end

            if hasValue(stats.CritChance) then
                table.insert(lines, string.format("치명타 확률 +%.1f%%", stats.CritChance * 100))
            end

            if hasValue(stats.CritDamageMultiplier and (stats.CritDamageMultiplier - 1)) then
                table.insert(lines, string.format("치명타 피해 +%.1f%%", (stats.CritDamageMultiplier - 1) * 100))
            end

            if hasValue(stats.Lifesteal) then
                table.insert(lines, string.format("흡혈 +%.1f%%", stats.Lifesteal * 100))
            end

            if hasValue(stats.AttackRangeBonus) then
                table.insert(lines, string.format("사거리 +%.1f", stats.AttackRangeBonus))
            end

            if hasValue(stats.MaxHealthBonus) then
                table.insert(lines, string.format("체력 +%.0f%%", stats.MaxHealthBonus * 100))
            end

            if typeof(stats.SkillCooldownMultiplier) == "number" and stats.SkillCooldownMultiplier < 0.999 then
                local reduction = (1 - stats.SkillCooldownMultiplier) * 100
                if reduction > 0 then
                    table.insert(lines, string.format("Q 쿨타임 -%.1f%%", reduction))
                end
            end

            if hasValue(stats.MoveSpeedBonus) then
                table.insert(lines, string.format("이동 속도 +%.1f%%", stats.MoveSpeedBonus * 100))
            end
        end

        local text
        if #lines == 0 then
            if typeof(lastChoice) == "table" and lastChoice.name then
                text = string.format("최근 강화: %s", tostring(lastChoice.name))
            else
                text = "강화: 없음"
            end
        else
            if typeof(lastChoice) == "table" and lastChoice.name then
                table.insert(lines, 1, string.format("최근 강화: %s", tostring(lastChoice.name)))
            else
                table.insert(lines, 1, "강화 현황")
            end
            text = table.concat(lines, "\n")
        end

        self:SetStatsText(text)
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
