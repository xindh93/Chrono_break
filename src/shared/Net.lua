local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local isServer = RunService:IsServer()

local REMOTE_FOLDER_NAME = "Remotes"
local remoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)

if not remoteFolder then
    if isServer then
        remoteFolder = Instance.new("Folder")
        remoteFolder.Name = REMOTE_FOLDER_NAME
        remoteFolder.Parent = ReplicatedStorage
    else
        remoteFolder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
    end
end

local Net = {}

Net.Definitions = {
    Events = {
        Attack = "AttackRequest",
        Skill = "SkillRequest",
        HUD = "HUDUpdate",
        GameState = "GameState",
        Result = "Result",
        Combat = "CombatEvent",
        EnemySpawned = "EnemySpawned",
        EnemyRemoved = "EnemyRemoved",
        LobbyTeleport = "LobbyTeleport",
        DashRequest = "DashRequest",
        DashReplicate = "DashReplicate",
        DashCooldown = "DashCooldown",
        BossSpawned = "BossSpawned",
        BossEnraged = "BossEnraged",
        RushWarning = "RushWarning",
        TeammateDown = "TeammateDown",
        XPChanged = "XPChanged",
        LevelUp = "LevelUp",
        CommitLevelUpChoice = "CommitLevelUpChoice",
        SetWorldFreeze = "SetWorldFreeze",
        LevelUpStatus = "LevelUpStatus",
        LevelStats = "LevelStats",
    },
    Functions = {
        RequestSummary = "RequestSummary",
        RestartMatch = "RestartMatch",
        GetProgress = "GetProgress",
        GetLevelUpChoices = "GetLevelUpChoices",
    },
}

local function ensureRemoteEvent(name: string): RemoteEvent
    local remote = remoteFolder:FindFirstChild(name)
    if not remote and isServer then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remoteFolder
    end
    if not remote then
        remote = remoteFolder:WaitForChild(name)
    end
    return remote :: RemoteEvent
end

local function ensureRemoteFunction(name: string): RemoteFunction
    local remote = remoteFolder:FindFirstChild(name)
    if not remote and isServer then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = remoteFolder
    end
    if not remote then
        remote = remoteFolder:WaitForChild(name)
    end
    return remote :: RemoteFunction
end

function Net:GetEvent(key: string): RemoteEvent
    local name = Net.Definitions.Events[key] or key
    return ensureRemoteEvent(name)
end

function Net:GetFunction(key: string): RemoteFunction
    local name = Net.Definitions.Functions[key] or key
    return ensureRemoteFunction(name)
end

local rateLimits: {[Player]: {[string]: {count: number, windowStart: number}}} = {}
local RATE_WINDOW = 1

local function getEntry(player: Player, key: string)
    local playerEntry = rateLimits[player]
    if not playerEntry then
        playerEntry = {}
        rateLimits[player] = playerEntry
    end

    local entry = playerEntry[key]
    if not entry then
        entry = {count = 0, windowStart = os.clock()}
        playerEntry[key] = entry
    end

    return entry
end

function Net:CheckRate(player: Player, key: string, limitPerSecond: number): boolean
    local entry = getEntry(player, key)
    local now = os.clock()
    if now - entry.windowStart > RATE_WINDOW then
        entry.count = 0
        entry.windowStart = now
    end

    if entry.count >= limitPerSecond then
        return false
    end

    entry.count = entry.count + 1
    return true
end

if isServer then
    Players.PlayerRemoving:Connect(function(player)
        rateLimits[player] = nil
    end)
end

function Net:FireAll(eventKey: string, ...)
    if not isServer then
        error("Net:FireAll can only be called from the server")
    end

    local event = self:GetEvent(eventKey)
    event:FireAllClients(...)
end

function Net:FireClient(player: Player, eventKey: string, ...)
    if not isServer then
        error("Net:FireClient can only be called from the server")
    end

    local event = self:GetEvent(eventKey)
    event:FireClient(player, ...)
end

return Net
