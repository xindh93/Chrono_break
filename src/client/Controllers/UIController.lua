local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)

local ResultScreen = require(script.Parent.Parent.UI.ResultScreen)

local UIController = Knit.CreateController({
    Name = "UIController",
})

function UIController:KnitInit()
    self.State = {
        State = "Prepare",
        Wave = 0,
        RemainingEnemies = 0,
        TimeRemaining = -1,
        Gold = 0,
        XP = 0,
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
end

function UIController:KnitStart()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    self.HUD = Knit.GetController("HUDController")
    if self.HUD and self.HUD.CreateInterface and not self.HUD.Screen then
        self.HUD:CreateInterface(playerGui)
    end
    self.ResultScreen = ResultScreen.new(playerGui)

    Net:GetEvent("HUD").OnClientEvent:Connect(function(payload)
        self:ApplyHUDUpdate(payload)
    end)

    Net:GetEvent("GameState").OnClientEvent:Connect(function(data)
        if data.Type == "WaveStart" then
            self.HUD:PlayWaveAnnouncement(data.Wave)
        elseif data.Type == "TeleportFailed" then
            self.HUD:ShowMessage("Teleport failed: " .. tostring(data.Message))
        end
    end)

    Net:GetEvent("Result").OnClientEvent:Connect(function(summary)
        self.HUD:ShowMessage("Session ended: " .. tostring(summary.Reason))
        self.ResultScreen:Show(summary)
    end)

    Net:GetEvent("Combat").OnClientEvent:Connect(function(event)
        if event.Type == "AOE" then
            self.HUD:ShowAOE(event.Position, event.Radius)
        end
    end)

    Net:GetEvent("DashCooldown").OnClientEvent:Connect(function(data)
        self:OnDashCooldown(data)
    end)

    Net:GetEvent("PartyUpdate").OnClientEvent:Connect(function(partyData)
        self:OnPartyUpdate(partyData)
    end)

    RunService.RenderStepped:Connect(function()
        if not self.HUD then
            return
        end

        local now = Workspace:GetServerTimeNow()
        local hasActive = false
        local toClear = nil
        local needsUpdate = false

        local dash = self.State.DashCooldown
        if dash then
            if dash.ReadyTime and dash.ReadyTime > 0 then
                local newRemaining = math.max(0, dash.ReadyTime - now)
                if dash.Remaining == nil or math.abs(newRemaining - dash.Remaining) > 0.01 then
                    dash.Remaining = newRemaining
                    needsUpdate = true
                else
                    dash.Remaining = newRemaining
                end
            end
        end

        for skillId, info in pairs(self.State.SkillCooldowns) do
            local cooldown = info.Cooldown or 0
            local timestamp = info.Timestamp

            if not timestamp or cooldown <= 0 then
                toClear = toClear or {}
                table.insert(toClear, skillId)
            else
                local elapsed = now - timestamp
                if elapsed >= cooldown then
                    toClear = toClear or {}
                    table.insert(toClear, skillId)
                else
                    hasActive = true
                end
            end
        end

        if toClear then
            for _, skillId in ipairs(toClear) do
                self.State.SkillCooldowns[skillId] = nil
            end
        end

        if needsUpdate or hasActive or toClear then
            self.HUD:Update(self.State)
        end
    end)

    self.HUD:Update(self.State)
end

function UIController:ApplyHUDUpdate(payload)
    for key, value in pairs(payload) do
        if key == "SkillCooldowns" then
            for skillId, info in pairs(value) do
                self.State.SkillCooldowns[skillId] = info
            end
        elseif key == "DashCooldown" then
            self:OnDashCooldown(value)
        elseif key == "Party" then
            self.State.Party = value
        elseif key == "XPProgress" then
            self.State.XPProgress = value
        elseif key == "Level" then
            self.State.Level = value
        else
            self.State[key] = value
        end
    end

    self.HUD:Update(self.State)
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

    if typeof(data) == "table" then
        if typeof(data.Cooldown) == "number" then
            cooldown = math.max(0, data.Cooldown)
        end
        if typeof(data.Remaining) == "number" then
            remaining = math.max(0, data.Remaining)
        end
    end

    dashState.Cooldown = cooldown
    dashState.Remaining = remaining
    dashState.ReadyTime = now + remaining
    dashState.LastUpdate = now

    if self.HUD then
        self.HUD:Update(self.State)
    end
end

function UIController:OnPartyUpdate(partyData)
    if typeof(partyData) ~= "table" then
        self.State.Party = {}
    else
        self.State.Party = partyData
    end

    if self.HUD then
        self.HUD:Update(self.State)
    end
end

function UIController:OnPartyUpdate(partyData)
    if typeof(partyData) ~= "table" then
        self.State.Party = {}
    else
        self.State.Party = partyData
    end

    if self.HUD then
        self.HUD:Update(self.State)
    end
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
