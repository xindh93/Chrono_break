local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local PLAYER_COLLISION_GROUP = "SkillSurvivalPlayers"
local ENEMY_COLLISION_GROUP = "SkillSurvivalEnemies"

local GameStateService = Knit.CreateService({
    Name = "GameStateService",
    Client = {},
})

function GameStateService:KnitInit()
    self.State = "Idle"
    self.CurrentWave = 0
    self.MatchStartTime = 0
    self.RestartSignal = Knit.Util.Signal.new()
    self.ResultReason = "Unknown"
end

function GameStateService:KnitStart()
    self.EnemyService = Knit.GetService("EnemyService")
    self.RewardService = Knit.GetService("RewardService")
    self.MapService = Knit.GetService("MapService")

    if self.EnemyService then
        self.PlayerCollisionGroup = self.EnemyService:GetPlayerCollisionGroup()
        self.EnemyCollisionGroup = self.EnemyService:GetEnemyCollisionGroup()
        if self.EnemyService.EnsureCollisionGroups then
            self.EnemyService:EnsureCollisionGroups()
        end
    end

    self.PlayerCollisionGroup = self.PlayerCollisionGroup or PLAYER_COLLISION_GROUP
    self.EnemyCollisionGroup = self.EnemyCollisionGroup or ENEMY_COLLISION_GROUP
    self:EnsureCollisionGroups()

    if self.EnemyService.EnemyCountChanged then
        self.EnemyService.EnemyCountChanged:Connect(function()
            if self.State == "Prepare" or self.State == "Active" then
                Net:FireAll("HUD", self:GetHUDPayload())
            end
        end)
    end

    Net:GetFunction("RestartMatch").OnServerInvoke = function(player)
        return self:RestartMatch(player)
    end

    Net:GetFunction("RequestSummary").OnServerInvoke = function(player)
        return self.RewardService:GetSummary(player)
    end

    Net:GetEvent("LobbyTeleport").OnServerEvent:Connect(function(player)
        self:TeleportToLobby(player)
    end)

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            self:OnCharacterAdded(player, character)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            self:OnCharacterAdded(player, player.Character)
        end
    end
end

function GameStateService:EnsureCollisionGroups()
    local function ensure(name: string)
        if typeof(name) ~= "string" or name == "" then
            return
        end

        local success, exists = pcall(function()
            if PhysicsService.CollisionGroupExists then
                return PhysicsService:CollisionGroupExists(name)
            end

            PhysicsService:GetCollisionGroupId(name)
            return true
        end)

        if not success or not exists then
            if PhysicsService.RegisterCollisionGroup then
                PhysicsService:RegisterCollisionGroup(name)
            else
                PhysicsService:CreateCollisionGroup(name)
            end
        end
    end

    local playerGroup = self.PlayerCollisionGroup or PLAYER_COLLISION_GROUP
    local enemyGroup = self.EnemyCollisionGroup or ENEMY_COLLISION_GROUP

    ensure(playerGroup)
    ensure(enemyGroup)

    if playerGroup and enemyGroup then
        PhysicsService:CollisionGroupSetCollidable(playerGroup, enemyGroup, false)
    end
end

function GameStateService:ApplyCharacterCollisionGroup(character: Model)
    if not character then
        return
    end

    local groupName = self.PlayerCollisionGroup or PLAYER_COLLISION_GROUP
    if typeof(groupName) ~= "string" or groupName == "" then
        return
    end

    local function setCollisionGroup(part: BasePart)
        if part.CollisionGroup ~= groupName then
            part.CollisionGroup = groupName
        end
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            setCollisionGroup(descendant)
        end
    end

    character.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            setCollisionGroup(descendant)
        end
    end)
end

function GameStateService:OnCharacterAdded(_player: Player, character: Model)
    if not character then
        return
    end

    self:ApplyCharacterCollisionGroup(character)

    task.defer(function()
        self:TeleportCharacterToSpawn(character)
    end)
end

function GameStateService:TeleportCharacterToSpawn(character: Model)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    local spawnCFrame = self.MapService:GetPlayerSpawnCFrame()
    root.CFrame = spawnCFrame
end

function GameStateService:Start()
    if self.MainLoop then
        return
    end

    self.MainLoop = task.spawn(function()
        while true do
            self:RunSession()
            self.State = "Results"

            task.delay(Config.Session.ResultDuration, function()
                if self.State == "Results" then
                    self.RestartSignal:Fire()
                end
            end)

            self.RestartSignal:Wait()
        end
    end)
end

function GameStateService:RestartMatch(player: Player)
    if self.State ~= "Results" then
        return false
    end

    if player and not Players:GetPlayerByUserId(player.UserId) then
        return false
    end

    self.RestartSignal:Fire()
    return true
end

function GameStateService:RunSession()
    self.State = "Prepare"
    self.CurrentWave = 0
    self.MatchStartTime = time()
    self.ResultReason = "Unknown"

    self.RewardService:ResetAll()
    self.EnemyService:StartMatch()

    for countdown = Config.Session.PrepareDuration, 1, -1 do
        Net:FireAll("HUD", {
            State = "Prepare",
            Countdown = countdown,
            Wave = self.CurrentWave,
            RemainingEnemies = self.EnemyService:GetRemainingEnemies(),
            TimeRemaining = self:GetTimeRemaining(),
        })
        task.wait(1)
    end

    self.State = "Active"
    self.MatchStartTime = time()

    task.spawn(function()
        while self.State == "Active" do
            Net:FireAll("HUD", self:GetHUDPayload())
            task.wait(1)
        end
    end)

    while self.State == "Active" do
        self.CurrentWave = self.CurrentWave + 1
        Net:FireAll("GameState", {
            Type = "WaveStart",
            Wave = self.CurrentWave,
        })

        self.EnemyService:BeginWave(self.CurrentWave)

        local waveFinished = false
        local connection
        connection = self.EnemyService.WaveCleared:Connect(function()
            waveFinished = true
        end)

        while not waveFinished do
            if self:CheckForSessionEnd() then
                waveFinished = true
                break
            end

            if not self.EnemyService:IsSpawning() and self.EnemyService:GetRemainingEnemies() <= 0 then
                waveFinished = true
                break
            end

            task.wait(0.5)
        end

        if connection then
            connection:Disconnect()
        end

        if self.State ~= "Active" then
            break
        end

        self.RewardService:AddWaveClearRewards(self.CurrentWave)
        Net:FireAll("HUD", self:GetHUDPayload())

        if self:CheckForSessionEnd() then
            break
        end

        task.wait(Config.Session.WaveInterval)
    end

    self:FinalizeSession(self.ResultReason)
end

function GameStateService:GetHUDPayload()
    return {
        State = self.State,
        Wave = self.CurrentWave,
        RemainingEnemies = self.EnemyService:GetRemainingEnemies(),
        TimeRemaining = self:GetTimeRemaining(),
        Countdown = 0,
    }
end

function GameStateService:GetTimeRemaining()
    if Config.Session.Infinite then
        return -1
    end

    local elapsed = time() - self.MatchStartTime
    return math.max(0, Config.Session.TimeLimit - elapsed)
end

function GameStateService:CheckForSessionEnd()
    local alivePlayers = self:GetAlivePlayerCount()
    if alivePlayers <= 0 then
        self.ResultReason = "All players down"
        self.State = "Ended"
        return true
    end

    if not Config.Session.Infinite then
        local elapsed = time() - self.MatchStartTime
        if elapsed >= Config.Session.TimeLimit then
            self.ResultReason = "Time limit"
            self.State = "Ended"
            return true
        end
    end

    return false
end

function GameStateService:GetAlivePlayerCount()
    local alive = 0
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            alive = alive + 1
        end
    end
    return alive
end

function GameStateService:FinalizeSession(reason: string)
    if reason == "Unknown" then
        reason = "Session Complete"
    end

    self.ResultReason = reason
    self.State = "Results"
    self.EnemyService:StopAll()
    self.RewardService:FinalizeMatch(reason)

    Net:FireAll("HUD", {
        State = self.State,
        Wave = self.CurrentWave,
        RemainingEnemies = 0,
        TimeRemaining = 0,
        Countdown = 0,
    })

    for _, player in ipairs(Players:GetPlayers()) do
        local summary = self.RewardService:GetSummary(player)
        summary.Wave = self.CurrentWave
        summary.TimeSurvived = math.floor(time() - self.MatchStartTime)
        Net:FireClient(player, "Result", summary)
    end
end

function GameStateService:TeleportToLobby(player: Player)
    local placeId = Config.LOBBY_PLACE_ID
    if placeId <= 0 then
        return
    end

    local success, err = pcall(function()
        TeleportService:Teleport(placeId, player)
    end)

    if not success then
        Net:FireClient(player, "GameState", {
            Type = "TeleportFailed",
            Message = err,
        })
    end
end

return GameStateService
