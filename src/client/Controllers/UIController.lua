local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)

local UIController = Knit.CreateController({
    Name = "UIController",
})

function UIController:KnitInit()
    self.State = {
        State = "Idle",
        RemainingEnemies = 0,
        TimeRemaining = -1,
        Countdown = 0,
        Gold = 0,
        XP = 0,
        Elapsed = 0,
        Wave = 1,
        Kills = 0,
        DamageDealt = 0,
        Assists = 0,
        MilestonesReached = 0,
        Level = 1,
        XPProgress = nil,
        SkillCooldowns = {},
        DashCooldown = {
            Remaining = 0,
            Cooldown = (Config.Skill and Config.Skill.Dash and Config.Skill.Dash.Cooldown) or 6,
            ReadyTime = 0,
        },
        Party = {},
    }
    self.Options = {ShowNameplates = false}
    self.MatchEndTime = nil
    self.CountdownEndTime = nil
    self.EstimatedEnemyCount = 0
end

function UIController:GetHUD()
    local hud = self.HUD
    if hud then
        return hud
    end

    hud = Knit.GetController("HUDController")
    if hud then
        self.HUD = hud
    end

    return hud
end

function UIController:RefreshHUD()
    local hud = self:GetHUD()
    if hud and typeof(hud.Update) == "function" then
        hud:Update(self.State)
        return hud
    end

    return nil
end

function UIController:WithHUD(methodName, ...)
    local hud = self:GetHUD()
    if not hud then
        return nil
    end

    local method = hud[methodName]
    if typeof(method) == "function" then
        return method(hud, ...)
    end

    return nil
end

function UIController:KnitStart()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    self.HUD = Knit.GetController("HUDController")

    local function refreshHUD()
        self:RefreshHUD()
    end

    if self.HUD then
        if typeof(self.HUD.EnsureInterface) == "function" then
            self.HUD:EnsureInterface(playerGui)
        end

        local onInterfaceReady = self.HUD.OnInterfaceReady
        if typeof(onInterfaceReady) == "function" then
            onInterfaceReady(self.HUD, refreshHUD)
        elseif self.HUD.InterfaceSignal and self.HUD.InterfaceSignal.Event then
            self.HUD.InterfaceSignal.Event:Connect(refreshHUD)
        end

        if self.HUD.Screen then
            task.defer(refreshHUD)
        end
    end
    Net:GetEvent("HUD").OnClientEvent:Connect(function(payload)
        self:ApplyHUDUpdate(payload)
    end)

    Net:GetEvent("GameState").OnClientEvent:Connect(function(data)
        if data.Type == "TeleportFailed" then
            self:WithHUD("ShowMessage", "Teleport failed: " .. tostring(data.Message))
        end
    end)

    Net:GetEvent("Result").OnClientEvent:Connect(function(summary)
        self:WithHUD("ShowMessage", "Session ended: " .. tostring(summary.Reason))
    end)

    Net:GetEvent("DashCooldown").OnClientEvent:Connect(function(data)
        self:OnDashCooldown(data)
    end)

    Net:GetEvent("EnemySpawned").OnClientEvent:Connect(function()
        self:OnEnemyCountDelta(1)
    end)

    Net:GetEvent("EnemyRemoved").OnClientEvent:Connect(function()
        self:OnEnemyCountDelta(-1)
    end)

    RunService.RenderStepped:Connect(function()
        local hud = self:GetHUD()
        if not hud then
            return
        end

        self.HUD = hud

        local now = Workspace:GetServerTimeNow()
        local needsUpdate = false
        local hasActiveSkill = false
        local toClear = nil

        local dash = self.State.DashCooldown
        if dash and dash.ReadyTime and dash.ReadyTime > 0 then
            local newRemaining = math.max(0, dash.ReadyTime - now)
            if dash.Remaining == nil or math.abs(newRemaining - dash.Remaining) > 0.01 or newRemaining <= 0.05 then
                dash.Remaining = newRemaining
                needsUpdate = true
            else
                dash.Remaining = newRemaining
            end
        end

        for skillId, info in pairs(self.State.SkillCooldowns) do
            local cooldown = info and info.Cooldown or 0
            if cooldown <= 0 then
                toClear = toClear or {}
                table.insert(toClear, skillId)
            else
                local readyTime = info and info.ReadyTime
                if typeof(readyTime) ~= "number" then
                    local endTime = info and info.EndTime
                    if typeof(endTime) == "number" then
                        readyTime = endTime
                    end
                end
                if typeof(readyTime) ~= "number" then
                    local timestamp = info and info.Timestamp
                    if typeof(timestamp) == "number" then
                        readyTime = timestamp + cooldown
                    end
                end
                if typeof(readyTime) ~= "number" then
                    local remainingValue = info and info.Remaining
                    if typeof(remainingValue) == "number" then
                        readyTime = now + remainingValue
                    end
                end

                if typeof(readyTime) ~= "number" then
                    toClear = toClear or {}
                    table.insert(toClear, skillId)
                else
                    info.EndTime = readyTime
                    info.ReadyTime = readyTime
                    if typeof(info.Timestamp) ~= "number" then
                        info.Timestamp = readyTime - cooldown
                    end

                    local remaining = readyTime - now
                    if remaining <= 0 then
                        toClear = toClear or {}
                        table.insert(toClear, skillId)
                        needsUpdate = true
                    else
                        hasActiveSkill = true
                        if info.Remaining == nil or math.abs(remaining - info.Remaining) > 0.05 then
                            info.Remaining = remaining
                            needsUpdate = true
                        else
                            info.Remaining = remaining
                        end
                    end
                end
            end
        end

        if self.CountdownEndTime and self.State.State == "Prepare" then
            local newCountdown = math.max(0, self.CountdownEndTime - now)
            if math.abs(newCountdown - (self.State.Countdown or 0)) > 0.05 then
                self.State.Countdown = newCountdown
                needsUpdate = true
            else
                self.State.Countdown = newCountdown
            end
            if newCountdown <= 0 then
                self.CountdownEndTime = nil
            end
        end

        if self.MatchEndTime and (self.State.TimeRemaining == nil or self.State.TimeRemaining >= 0) then
            local newRemaining = math.max(0, self.MatchEndTime - now)
            if math.abs(newRemaining - (self.State.TimeRemaining or 0)) > 0.05 then
                self.State.TimeRemaining = newRemaining
                needsUpdate = true
            else
                self.State.TimeRemaining = newRemaining
            end
            if newRemaining <= 0 then
                self.MatchEndTime = nil
            end
        end

        if toClear then
            for _, skillId in ipairs(toClear) do
                self.State.SkillCooldowns[skillId] = nil
            end
            needsUpdate = true
        end

        if needsUpdate or hasActiveSkill then
            self:RefreshHUD()
        end
    end)

    self:RefreshHUD()
end

function UIController:ApplyHUDUpdate(payload)
    local now = Workspace:GetServerTimeNow()
    local newState

    for key, value in pairs(payload) do
        if key == "SkillCooldowns" then
            for skillId, info in pairs(value) do
                if typeof(info) == "table" then
                    local entry = self.State.SkillCooldowns[skillId]
                    if typeof(entry) ~= "table" then
                        entry = {}
                        self.State.SkillCooldowns[skillId] = entry
                    end

                    local cooldown = entry.Cooldown or 0
                    if typeof(info.Cooldown) == "number" then
                        cooldown = math.max(0, info.Cooldown)
                        entry.Cooldown = cooldown
                    elseif entry.Cooldown == nil then
                        entry.Cooldown = cooldown
                    end

                    if typeof(info.Timestamp) == "number" then
                        entry.Timestamp = info.Timestamp
                    end

                    local readyTime = info.ReadyTime
                    if typeof(readyTime) ~= "number" then
                        if typeof(info.EndTime) == "number" then
                            readyTime = info.EndTime
                        elseif typeof(entry.Timestamp) == "number" and cooldown > 0 then
                            readyTime = entry.Timestamp + cooldown
                        elseif typeof(info.Remaining) == "number" then
                            readyTime = now + math.max(0, info.Remaining)
                        end
                    end

                    entry.ReadyTime = readyTime
                    if typeof(readyTime) == "number" then
                        entry.EndTime = readyTime
                        if (typeof(entry.Timestamp) ~= "number" or entry.Timestamp <= 0) and cooldown > 0 then
                            entry.Timestamp = readyTime - cooldown
                        end
                        entry.Remaining = math.max(0, readyTime - now)
                    elseif typeof(info.Remaining) == "number" then
                        local normalized = math.max(0, info.Remaining)
                        entry.Remaining = normalized
                        entry.EndTime = now + normalized
                        entry.ReadyTime = entry.EndTime
                    else
                        entry.Remaining = nil
                        entry.EndTime = nil
                    end

                    for keyName, value in pairs(info) do
                        if entry[keyName] == nil then
                            entry[keyName] = value
                        end
                    end
                else
                    self.State.SkillCooldowns[skillId] = nil
                end
            end
        elseif key == "DashCooldown" then
            self:OnDashCooldown(value)
        elseif key == "Party" then
            self.State.Party = value
        elseif key == "XPProgress" then
            self.State.XPProgress = value
        elseif key == "Level" then
            self.State.Level = value
        elseif key == "Elapsed" then
            if typeof(value) == "number" then
                self.State.Elapsed = math.max(0, value)
            end
        elseif key == "Wave" then
            self.State.Wave = value
        elseif key == "TimeRemaining" then
            if typeof(value) == "number" then
                if value >= 0 then
                    local remainingValue = math.max(0, value)
                    self.State.TimeRemaining = remainingValue
                    self.MatchEndTime = now + remainingValue
                else
                    self.State.TimeRemaining = value
                    self.MatchEndTime = nil
                end
            else
                self.State.TimeRemaining = -1
                self.MatchEndTime = nil
            end
        elseif key == "Countdown" then
            if typeof(value) == "number" then
                local countdownValue = math.max(0, value)
                self.State.Countdown = countdownValue
                if countdownValue > 0 then
                    self.CountdownEndTime = now + countdownValue
                else
                    self.CountdownEndTime = nil
                end
            else
                self.State.Countdown = 0
                self.CountdownEndTime = nil
            end
        elseif key == "RemainingEnemies" then
            self.State.RemainingEnemies = value
            if typeof(value) == "number" then
                self.EstimatedEnemyCount = math.max(0, value)
            else
                self.EstimatedEnemyCount = 0
            end
        elseif key == "State" then
            newState = value
        else
            self.State[key] = value
        end
    end

    if newState ~= nil then
        self.State.State = newState
        if newState == "Prepare" then
            self.EstimatedEnemyCount = self.State.RemainingEnemies or 0
        elseif newState == "Active" then
            if typeof(self.State.RemainingEnemies) == "number" then
                self.EstimatedEnemyCount = math.max(0, self.State.RemainingEnemies)
            end
        elseif newState == "Results" or newState == "Ended" or newState == "Idle" then
            self.EstimatedEnemyCount = 0
            self.MatchEndTime = nil
        end

        if newState ~= "Prepare" then
            self.CountdownEndTime = nil
            self.State.Countdown = 0
        end
    end

    self:RefreshHUD()
end

function UIController:OnDashCooldown(data)
    local dashState = self.State.DashCooldown
    if not dashState then
        dashState = {}
        self.State.DashCooldown = dashState
    end

    local now = Workspace:GetServerTimeNow()
    local cooldown = dashState.Cooldown or 0
    local remaining = dashState.Remaining or 0
    local readyTime = dashState.ReadyTime or (now + remaining)

    if typeof(data) == "table" then
        if typeof(data.Cooldown) == "number" then
            cooldown = math.max(0, data.Cooldown)
        end
        if typeof(data.ReadyTime) == "number" then
            readyTime = data.ReadyTime
            remaining = math.max(0, readyTime - now)
        elseif typeof(data.Remaining) == "number" then
            remaining = math.max(0, data.Remaining)
            readyTime = now + remaining
        end
    end

    dashState.Cooldown = cooldown
    dashState.Remaining = remaining
    dashState.ReadyTime = readyTime
    dashState.LastUpdate = now

    self:RefreshHUD()
end

function UIController:OnEnemyCountDelta(delta)
    if typeof(delta) ~= "number" or delta == 0 then
        return
    end

    if self.State.State == "Results" or self.State.State == "Idle" then
        self.EstimatedEnemyCount = 0
        self.State.RemainingEnemies = 0
        self:RefreshHUD()
        return
    end

    local count = self.EstimatedEnemyCount
    if typeof(count) ~= "number" then
        count = self.State.RemainingEnemies or 0
    end

    count = count + delta
    if count < 0 then
        count = 0
    end

    self.EstimatedEnemyCount = count
    self.State.RemainingEnemies = count

    self:RefreshHUD()
end

function UIController:ApplyOptions(options)
    if typeof(options) ~= "table" then
        return
    end

    if options.ShowNameplates ~= nil then
        self:SetNameplatesEnabled(not not options.ShowNameplates)
    end
end

function UIController:SetNameplatesEnabled(enabled, force)
    enabled = not not enabled

    if not force and self.Options.ShowNameplates == enabled then
        return
    end

    self.Options.ShowNameplates = enabled

    if enabled then
        self:DisconnectNameplateTracking()
        self:ApplyNameplateMode(Enum.HumanoidDisplayDistanceType.Viewer)
    else
        self:ConnectNameplateTracking()
        self:ApplyNameplateMode(Enum.HumanoidDisplayDistanceType.None)
    end
end

function UIController:ApplyNameplateMode(displayType)
    for _, player in ipairs(Players:GetPlayers()) do
        self:ApplyNameplateToPlayer(player, displayType)
    end
end

function UIController:ApplyNameplateToPlayer(player, displayType)
    local character = player.Character
    if character then
        self:ApplyNameplateToCharacter(character, displayType)
    end
end

function UIController:ApplyNameplateToCharacter(character, displayType)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.DisplayDistanceType = displayType
    end
end

function UIController:ConnectNameplateTracking()
    self:DisconnectNameplateTracking()

    self.NameplateTrackedPlayers = {}

    local function track(player)
        self:TrackPlayerNameplate(player)
    end

    self.NameplatePlayerAddedConn = Players.PlayerAdded:Connect(track)
    self.NameplatePlayerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        self:UntrackPlayerNameplate(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        track(player)
    end
end

function UIController:DisconnectNameplateTracking()
    if self.NameplatePlayerAddedConn then
        self.NameplatePlayerAddedConn:Disconnect()
        self.NameplatePlayerAddedConn = nil
    end
    if self.NameplatePlayerRemovingConn then
        self.NameplatePlayerRemovingConn:Disconnect()
        self.NameplatePlayerRemovingConn = nil
    end

    for player, connections in pairs(self.NameplateTrackedPlayers) do
        if connections.CharacterAdded then
            connections.CharacterAdded:Disconnect()
        end
        if connections.CharacterRemoving then
            connections.CharacterRemoving:Disconnect()
        end
        if connections.ChildAdded then
            connections.ChildAdded:Disconnect()
        end
        self.NameplateTrackedPlayers[player] = nil
    end
end

function UIController:TrackPlayerNameplate(player)
    self:UntrackPlayerNameplate(player)

    local connections = {}
    self.NameplateTrackedPlayers[player] = connections

    local function apply(character)
        self:ApplyNameplateToCharacter(character, Enum.HumanoidDisplayDistanceType.None)
        if connections.ChildAdded then
            connections.ChildAdded:Disconnect()
        end
        connections.ChildAdded = character.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then
                self:ApplyNameplateToCharacter(character, Enum.HumanoidDisplayDistanceType.None)
            end
        end)
    end

    if player.Character then
        apply(player.Character)
    end

    connections.CharacterAdded = player.CharacterAdded:Connect(function(character)
        apply(character)
    end)

    connections.CharacterRemoving = player.CharacterRemoving:Connect(function(character)
        if connections.ChildAdded then
            connections.ChildAdded:Disconnect()
            connections.ChildAdded = nil
        end
        self:ApplyNameplateToCharacter(character, Enum.HumanoidDisplayDistanceType.Viewer)
    end)
end

function UIController:UntrackPlayerNameplate(player)
    local connections = self.NameplateTrackedPlayers[player]
    if not connections then
        return
    end

    if connections.CharacterAdded then
        connections.CharacterAdded:Disconnect()
    end
    if connections.CharacterRemoving then
        connections.CharacterRemoving:Disconnect()
    end
    if connections.ChildAdded then
        connections.ChildAdded:Disconnect()
    end

    self.NameplateTrackedPlayers[player] = nil
end

return UIController
