local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local PlayerProgressService = Knit.CreateService({
    Name = "PlayerProgressService",
    Client = {},
})

local DEFAULT_CHOICES = {
    {
        id = "range_add_06",
        name = "사거리 증폭기",
        desc = "기본 공격 사거리 +0.6",
        kind = "stat",
        stat = "AttackRange",
        operation = "add",
        value = 0.6,
    },
    {
        id = "crit_rate_06",
        name = "정밀 회로",
        desc = "치명타 확률 +6%",
        kind = "stat",
        stat = "CritChance",
        operation = "add",
        value = 0.06,
    },
    {
        id = "crit_dmg_15",
        name = "과충전 유닛",
        desc = "치명타 피해 +15%",
        kind = "stat",
        stat = "CritDamage",
        operation = "add",
        value = 0.15,
    },
    {
        id = "lifesteal_025",
        name = "에너지 환류",
        desc = "입힌 피해의 2.5% 흡수",
        kind = "stat",
        stat = "Lifesteal",
        operation = "compound",
        value = 0.025,
    },
    {
        id = "attack_08",
        name = "출력 증폭기",
        desc = "공격력 +8%",
        kind = "stat",
        stat = "AttackPower",
        operation = "add",
        value = 0.08,
    },
    {
        id = "skill_cdr_08",
        name = "재가동 모듈",
        desc = "Q 쿨타임 -8%",
        kind = "stat",
        stat = "SkillCooldown",
        operation = "scale",
        value = 0.08,
    },
    {
        id = "max_hp_10",
        name = "생체 강화 코어",
        desc = "최대 체력 +10%",
        kind = "stat",
        stat = "MaxHealth",
        operation = "add",
        value = 0.10,
    },
    {
        id = "move_speed_04",
        name = "추진 보강재",
        desc = "이동 속도 +4%",
        kind = "stat",
        stat = "MoveSpeed",
        operation = "compound",
        value = 0.04,
    },
}

local function createDefaultStats()
    return {
        AttackRange = 0,
        AttackPower = 0,
        CritChance = 0,
        CritDamage = 0,
        Lifesteal = 0,
        SkillCooldownMultiplier = 1,
        MaxHealth = 0,
        MoveSpeedBonus = 0,
    }
end

local function compoundIncrease(current: number, amount: number): number
    current = math.clamp(current or 0, 0, 0.95)
    amount = math.clamp(amount or 0, -0.95, 0.95)
    return 1 - (1 - current) * (1 - amount)
end

function PlayerProgressService:GetProfileStats(profile)
    if not profile then
        return createDefaultStats()
    end

    if not profile.stats then
        profile.stats = createDefaultStats()
    end

    return profile.stats
end

function PlayerProgressService:CaptureBaseStats(profile, humanoid)
    if not profile or not humanoid then
        return
    end

    if not profile.baseStats then
        profile.baseStats = {}
    end

    profile.baseStats.MaxHealth = humanoid.MaxHealth
    profile.baseStats.WalkSpeed = humanoid.WalkSpeed
end

function PlayerProgressService:ApplyStatsToCharacter(player: Player, profile, character)
    profile = profile or self.Profiles[player]
    if not profile then
        return
    end

    local stats = self:GetProfileStats(profile)
    character = character or player and player.Character
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    if not profile.baseStats then
        self:CaptureBaseStats(profile, humanoid)
    end

    local baseStats = profile.baseStats or {}
    local baseMaxHealth = baseStats.MaxHealth or humanoid.MaxHealth
    local baseWalkSpeed = baseStats.WalkSpeed or humanoid.WalkSpeed

    local currentMax = humanoid.MaxHealth
    local currentHealth = humanoid.Health
    local ratio = currentMax > 0 and math.clamp(currentHealth / currentMax, 0, 1) or 1

    local maxHealthBonus = math.max(-0.9, stats.MaxHealth or 0)
    local newMax = math.max(1, baseMaxHealth * (1 + maxHealthBonus))
    humanoid.MaxHealth = newMax
    humanoid.Health = math.clamp(newMax * ratio, 0, newMax)

    local moveBonus = stats.MoveSpeedBonus or 0
    humanoid.WalkSpeed = math.max(0, baseWalkSpeed * (1 + moveBonus))
end

function PlayerProgressService:InitializeCharacter(player: Player, profile, character)
    profile = profile or self.Profiles[player]
    if not profile or not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        task.spawn(function()
            local found = character:WaitForChild("Humanoid", 5)
            if found then
                self:CaptureBaseStats(profile, found)
                self:ApplyStatsToCharacter(player, profile, character)
            end
        end)
        return
    end

    self:CaptureBaseStats(profile, humanoid)
    self:ApplyStatsToCharacter(player, profile, character)
end

function PlayerProgressService:GetStatSnapshot(player: Player, profile)
    profile = profile or self.Profiles[player]
    local stats = self:GetProfileStats(profile)
    return {
        AttackRangeBonus = stats.AttackRange or 0,
        AttackPowerBonus = stats.AttackPower or 0,
        CritChance = math.clamp(stats.CritChance or 0, 0, 1),
        CritDamageMultiplier = 1 + math.max(0, stats.CritDamage or 0),
        Lifesteal = math.clamp(stats.Lifesteal or 0, 0, 1),
        SkillCooldownMultiplier = math.clamp(stats.SkillCooldownMultiplier or 1, 0.1, 1),
        MaxHealthBonus = stats.MaxHealth or 0,
        MoveSpeedBonus = stats.MoveSpeedBonus or 0,
    }
end

function PlayerProgressService:SendStatUpdate(player: Player, profile)
    profile = profile or self.Profiles[player]
    if not profile then
        return
    end

    local stats = self:GetStatSnapshot(player, profile)
    local lastChoice = profile.lastChoice
    local payload = {
        Stats = stats,
    }
    if lastChoice and typeof(lastChoice) == "table" then
        payload.LastChoice = {
            id = lastChoice.id,
            name = lastChoice.name,
            desc = lastChoice.desc,
        }
    end

    Net:FireClient(player, "LevelStats", payload)
end

function PlayerProgressService:ApplyStatChoice(player: Player, profile, choice)
    profile = profile or self.Profiles[player]
    if not profile then
        return
    end

    local stats = self:GetProfileStats(profile)
    local statKey = choice.stat
    local value = tonumber(choice.value) or 0

    if statKey == "AttackRange" then
        stats.AttackRange = (stats.AttackRange or 0) + value
    elseif statKey == "AttackPower" then
        stats.AttackPower = (stats.AttackPower or 0) + value
    elseif statKey == "CritChance" then
        stats.CritChance = math.clamp((stats.CritChance or 0) + value, 0, 1)
    elseif statKey == "CritDamage" then
        stats.CritDamage = math.max(0, (stats.CritDamage or 0) + value)
    elseif statKey == "Lifesteal" then
        stats.Lifesteal = compoundIncrease(stats.Lifesteal or 0, value)
    elseif statKey == "SkillCooldown" then
        local scale = math.clamp(1 - value, 0.25, 1)
        stats.SkillCooldownMultiplier = math.clamp((stats.SkillCooldownMultiplier or 1) * scale, 0.1, 1)
    elseif statKey == "MaxHealth" then
        stats.MaxHealth = math.max(-0.9, (stats.MaxHealth or 0) + value)
    elseif statKey == "MoveSpeed" then
        stats.MoveSpeedBonus = compoundIncrease(stats.MoveSpeedBonus or 0, value)
    end

    self:ApplyStatsToCharacter(player, profile)
    self:SendStatUpdate(player, profile)
end

function PlayerProgressService:ApplyChoiceEffect(player: Player, profile, choice)
    if not choice or typeof(choice) ~= "table" then
        return
    end

    local triggeredStatUpdate = false
    if choice.kind == "stat" and choice.stat then
        self:ApplyStatChoice(player, profile, choice)
        triggeredStatUpdate = true
    elseif choice.kind == "instant" then
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local amount = math.max(0, tonumber(choice.value) or 0)
                if amount > 0 then
                    local heal = humanoid.MaxHealth * amount
                    humanoid.Health = math.clamp(humanoid.Health + heal, 0, humanoid.MaxHealth)
                end
            end
        end
    end

    if not triggeredStatUpdate then
        self:SendStatUpdate(player, profile)
    end
end

function PlayerProgressService:KnitInit()
    self.Profiles = {} :: {[Player]: {
        level: number,
        xp: number,
        xpToNext: number,
        isFrozen: boolean,
        queue: { {level: number, carriedXP: number, xpToNext: number} },
        activeLevelUp: {
            level: number,
            carriedXP: number,
            xpToNext: number,
            token: string,
            committed: boolean,
            choices: { [number]: { id: string, name: string, desc: string, kind: string, value: any } }?,
            startedAt: number?,
            expireTime: number?,
        }?,
        connections: { [string]: RBXScriptConnection }?,
        lastChoice: any?,
    }}
    self.ActiveFreezes = 0
    self.WorldFrozen = false
    self.WorldFreezeStartedAt = nil
    self.TotalFreezeDuration = 0
    self.WorldFreezeChanged = Knit.Util.Signal.new()
    self.Random = Random.new()
    self.LevelingConfig = Config.Leveling or {}
    local levelingUI = (self.LevelingConfig and self.LevelingConfig.UI) or {}
    self.LevelUpTimeout = math.max(1, levelingUI.SelectionTimeout or 30)
    self.EnemyService = nil
    self.FrozenPlayerHumanoids = {} :: {[Humanoid]: {WalkSpeed: number, AutoRotate: boolean, JumpValue: number, UseJumpPower: boolean}}
    self.FrozenPlayerRoots = {} :: {[BasePart]: {Anchored: boolean}}
end

function PlayerProgressService:KnitStart()
    task.defer(function()
        local success, service = pcall(function()
            return Knit.GetService("EnemyService")
        end)
        if success then
            self.EnemyService = service
        end
    end)

    Players.PlayerAdded:Connect(function(player)
        self:CreateProfile(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:RemoveProfile(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        self:CreateProfile(player)
    end

    Net:GetFunction("GetProgress").OnServerInvoke = function(player)
        local profile = self:CreateProfile(player)
        return {
            Level = profile.level,
            XP = profile.xp,
            XPToNext = profile.xpToNext,
            MaxLevel = self:GetMaxLevel(),
        }
    end

    Net:GetFunction("GetLevelUpChoices").OnServerInvoke = function(player)
        return self:OnGetLevelUpChoices(player)
    end

    Net:GetEvent("CommitLevelUpChoice").OnServerEvent:Connect(function(player, choiceId)
        self:OnCommitLevelUpChoice(player, choiceId)
    end)
end

function PlayerProgressService:GetMaxLevel(): number
    local maxLevel = self.LevelingConfig and self.LevelingConfig.MaxLevel
    if typeof(maxLevel) == "number" and maxLevel > 0 then
        return math.floor(maxLevel)
    end
    return 50
end

function PlayerProgressService:ComputeXPToNext(level: number): number
    local leveling = self.LevelingConfig
    if leveling and typeof(leveling.XPToNext) == "function" then
        local value = leveling.XPToNext(level)
        if typeof(value) == "number" then
            return math.max(0, math.floor(value))
        end
    end
    local baseXP = (leveling and leveling.BaseXP) or 60
    local growth = (leveling and leveling.Growth) or 1.2
    return math.max(0, math.floor(baseXP * (growth ^ (math.max(1, math.floor(level)) - 1))))
end

function PlayerProgressService:CreateProfile(player: Player)
    local existing = self.Profiles[player]
    if existing then
        return existing
    end

    local profile = {
        level = 1,
        xp = 0,
        xpToNext = self:ComputeXPToNext(1),
        isFrozen = false,
        queue = {},
        activeLevelUp = nil,
        connections = {},
        lastChoice = nil,
        stats = createDefaultStats(),
        baseStats = nil,
    }

    self.Profiles[player] = profile

    local connections = profile.connections
    connections.CharacterAdded = player.CharacterAdded:Connect(function(character)
        if character then
            task.defer(function()
                self:InitializeCharacter(player, profile, character)
            end)
        end
        if self.WorldFrozen and character then
            task.defer(function()
                self:_setCharacterFrozen(character, true)
            end)
        end
    end)

    local character = player.Character
    if character then
        task.defer(function()
            self:InitializeCharacter(player, profile, character)
        end)
        if self.WorldFrozen then
            task.defer(function()
                self:_setCharacterFrozen(character, true)
            end)
        end
    end

    task.defer(function()
        self:SendStatUpdate(player, profile)
    end)

    return profile
end

function PlayerProgressService:RemoveProfile(player: Player)
    local profile = self.Profiles[player]
    if not profile then
        return
    end

    if profile.connections then
        for _, connection in pairs(profile.connections) do
            if connection and connection.Disconnect then
                connection:Disconnect()
            end
        end
        profile.connections = nil
    end

    if profile.isFrozen then
        profile.isFrozen = false
        profile.activeLevelUp = nil
        self.ActiveFreezes = math.max(0, self.ActiveFreezes - 1)
        if self.ActiveFreezes == 0 then
            self:SetWorldFreeze(false)
        end
    end

    self.Profiles[player] = nil
    self:BroadcastLevelUpStatus()
end

function PlayerProgressService:IsWorldFrozen(): boolean
    return self.WorldFrozen
end

function PlayerProgressService:SetWorldFreeze(enabled: boolean)
    if enabled then
        if not self.WorldFrozen then
            self.WorldFrozen = true
            self.WorldFreezeStartedAt = time()
            Net:FireAll("SetWorldFreeze", true)
            self:_setAllPlayerCharactersFrozen(true)
            local enemyService = self.EnemyService
            if enemyService and typeof(enemyService.SetWorldFreeze) == "function" then
                enemyService:SetWorldFreeze(true)
            end
            if self.WorldFreezeChanged then
                self.WorldFreezeChanged:Fire(true, 0)
            end
        end
    else
        if self.WorldFrozen then
            local duration = 0
            if self.WorldFreezeStartedAt then
                duration = math.max(0, time() - self.WorldFreezeStartedAt)
                self.TotalFreezeDuration += duration
            end
            self.WorldFrozen = false
            self.WorldFreezeStartedAt = nil
            Net:FireAll("SetWorldFreeze", false)
            self:_setAllPlayerCharactersFrozen(false)
            local enemyService = self.EnemyService
            if enemyService and typeof(enemyService.SetWorldFreeze) == "function" then
                enemyService:SetWorldFreeze(false)
            end
            if self.WorldFreezeChanged then
                self.WorldFreezeChanged:Fire(false, duration)
            end
        end
    end
end

function PlayerProgressService:_setCharacterFrozen(character: Model?, enabled: boolean)
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
        or (character:IsA("Model") and character.PrimaryPart)

    if humanoid then
        local record = self.FrozenPlayerHumanoids[humanoid]
        if enabled then
            if not record then
                record = {
                    WalkSpeed = humanoid.WalkSpeed,
                    AutoRotate = humanoid.AutoRotate,
                    UseJumpPower = humanoid.UseJumpPower,
                    JumpValue = humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight,
                }
                self.FrozenPlayerHumanoids[humanoid] = record
                humanoid.WalkSpeed = 0
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = 0
                else
                    humanoid.JumpHeight = 0
                end
                humanoid.AutoRotate = false
                humanoid:ChangeState(Enum.HumanoidStateType.Physics)
            end
        else
            if record then
                humanoid.WalkSpeed = record.WalkSpeed
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = record.JumpValue
                else
                    humanoid.JumpHeight = record.JumpValue
                end
                humanoid.AutoRotate = record.AutoRotate
                self.FrozenPlayerHumanoids[humanoid] = nil
            end
        end
    end

    if root and root:IsA("BasePart") then
        local rootRecord = self.FrozenPlayerRoots[root]
        if enabled then
            if not rootRecord then
                self.FrozenPlayerRoots[root] = {Anchored = root.Anchored}
                root.Anchored = true
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        else
            if rootRecord then
                root.Anchored = rootRecord.Anchored
                self.FrozenPlayerRoots[root] = nil
            end
        end
    end
end

function PlayerProgressService:_setAllPlayerCharactersFrozen(enabled: boolean)
    for _, player in ipairs(Players:GetPlayers()) do
        self:_setCharacterFrozen(player.Character, enabled)
    end

    if not enabled then
        for humanoid, record in pairs(self.FrozenPlayerHumanoids) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = record.WalkSpeed
                if humanoid.UseJumpPower then
                    humanoid.JumpPower = record.JumpValue
                else
                    humanoid.JumpHeight = record.JumpValue
                end
                humanoid.AutoRotate = record.AutoRotate
            end
            self.FrozenPlayerHumanoids[humanoid] = nil
        end

        for root, record in pairs(self.FrozenPlayerRoots) do
            if root and root.Parent then
                root.Anchored = record.Anchored
            end
            self.FrozenPlayerRoots[root] = nil
        end
    end
end

function PlayerProgressService:GetProfile(player: Player)
    return self.Profiles[player]
end

function PlayerProgressService:GetTotalFrozenTime(): number
    local total = self.TotalFreezeDuration or 0
    if self.WorldFrozen and self.WorldFreezeStartedAt then
        total += math.max(0, time() - self.WorldFreezeStartedAt)
    end
    return total
end

function PlayerProgressService:GetWorldTime(): number
    local total = self:GetTotalFrozenTime()
    return time() - total
end

function PlayerProgressService:OnWorldFreezeChanged(callback)
    if not self.WorldFreezeChanged or typeof(callback) ~= "function" then
        return nil
    end
    return self.WorldFreezeChanged:Connect(callback)
end

function PlayerProgressService:AddXP(player: Player, amount: number, reason: string?)
    local profile = self:GetProfile(player)
    if not profile then
        return
    end

    if typeof(amount) ~= "number" or not amount or amount <= 0 or amount ~= amount then
        return
    end

    local maxLevel = self:GetMaxLevel()
    if profile.level >= maxLevel then
        profile.level = maxLevel
        profile.xp = 0
        profile.xpToNext = 0
        self:FireXPChanged(player, profile)
        return
    end

    profile.xp += amount

    local leveled = false
    while profile.level < maxLevel and profile.xpToNext > 0 and profile.xp >= profile.xpToNext do
        local carried = profile.xp - profile.xpToNext
        profile.level += 1
        profile.xp = math.max(0, carried)
        profile.xpToNext = self:ComputeXPToNext(profile.level)

        profile.queue[#profile.queue + 1] = {
            level = profile.level,
            carriedXP = profile.xp,
            xpToNext = profile.xpToNext,
        }

        leveled = true

        if profile.level >= maxLevel then
            profile.level = maxLevel
            profile.xp = 0
            profile.xpToNext = 0
            profile.queue = {}
            break
        end
    end

    if leveled then
        self:ProcessQueue(player, profile)
    elseif not profile.isFrozen then
        self:FireXPChanged(player, profile)
    end
end

function PlayerProgressService:ProcessQueue(player: Player, profile)
    if profile.isFrozen then
        return
    end

    local nextEntry = profile.queue[1]
    if not nextEntry then
        return
    end

    self:BeginLevelUpFreeze(player, profile, nextEntry)
end

function PlayerProgressService:BeginLevelUpFreeze(player: Player, profile, entry)
    profile.isFrozen = true
    self.ActiveFreezes += 1
    if self.ActiveFreezes == 1 then
        self:SetWorldFreeze(true)
    end

    profile.activeLevelUp = {
        level = entry.level,
        carriedXP = entry.carriedXP,
        xpToNext = entry.xpToNext,
        token = HttpService:GenerateGUID(false),
        committed = false,
        choices = nil,
        startedAt = time(),
    }

    local active = profile.activeLevelUp
    active.choices = self:GenerateChoices(player, profile)
    active.expireTime = (active.startedAt or time()) + self.LevelUpTimeout

    self:BroadcastLevelUpStatus()

    task.spawn(function()
        self:AwaitLevelUpTimeout(player, active.token)
    end)

    Net:FireAll("LevelUp", player, entry.level, entry.carriedXP)
end

function PlayerProgressService:GenerateChoices(player: Player, profile)
    local pool = DEFAULT_CHOICES
    local count = math.min(3, #pool)
    local used = {}
    local results = {}
    for _ = 1, count do
        local index
        repeat
            index = self.Random:NextInteger(1, #pool)
        until not used[index]
        used[index] = true
        local entry = pool[index]
        results[#results + 1] = table.clone(entry)
    end
    return results
end

function PlayerProgressService:BroadcastLevelUpStatus()
    local total = 0
    local committed = 0
    local minRemaining = nil
    local now = time()
    local playerCount = #Players:GetPlayers()

    for _, profile in pairs(self.Profiles) do
        local active = profile and profile.activeLevelUp
        if active then
            total += 1
            if active.committed then
                committed += 1
            elseif typeof(active.expireTime) == "number" then
                local remaining = math.max(0, active.expireTime - now)
                if not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                end
            end
        end
    end

    Net:FireAll("LevelUpStatus", {
        Total = total,
        Committed = committed,
        Remaining = minRemaining,
        PlayerCount = playerCount,
    })
end

function PlayerProgressService:AwaitLevelUpTimeout(player: Player, token: string)
    while true do
        task.wait(0.5)
        local profile = self.Profiles[player]
        if not profile then
            return
        end

        local active = profile.activeLevelUp
        if not active or active.token ~= token then
            return
        end

        if active.committed then
            return
        end

        local expireTime = active.expireTime
        if typeof(expireTime) ~= "number" then
            expireTime = time() + self.LevelUpTimeout
            active.expireTime = expireTime
        end

        if time() >= expireTime then
            self:AutoCommitLevelUp(player, profile)
            return
        end
    end
end

function PlayerProgressService:AutoCommitLevelUp(player: Player, profile)
    profile = profile or self.Profiles[player]
    if not profile then
        return
    end

    local active = profile.activeLevelUp
    if not active or active.committed then
        return
    end

    if not active.choices then
        active.choices = self:GenerateChoices(player, profile)
    end

    local fallback = nil
    if active.choices and #active.choices > 0 then
        fallback = active.choices[1]
    end

    if fallback then
        self:ApplyLevelUpChoice(player, profile, fallback)
    else
        active.committed = true
        self:BroadcastLevelUpStatus()
        self:CompleteLevelUp(player, profile)
    end
end

function PlayerProgressService:ApplyLevelUpChoice(player: Player, profile, chosen)
    if not profile then
        profile = self.Profiles[player]
    end

    if not profile then
        return
    end

    local active = profile.activeLevelUp
    if not active or active.committed then
        return
    end

    active.committed = true
    profile.lastChoice = table.clone(chosen)
    self:ApplyChoiceEffect(player, profile, chosen)
    self:BroadcastLevelUpStatus()
    self:CompleteLevelUp(player, profile)
end

function PlayerProgressService:OnGetLevelUpChoices(player: Player)
    local profile = self:GetProfile(player)
    if not profile or not profile.isFrozen then
        return nil
    end

    local active = profile.activeLevelUp
    if not active or active.committed then
        return nil
    end

    if not active.choices then
        active.choices = self:GenerateChoices(player, profile)
    end

    return {
        Token = active.token,
        Choices = active.choices,
    }
end

function PlayerProgressService:OnCommitLevelUpChoice(player: Player, choiceId: string)
    local profile = self:GetProfile(player)
    if not profile or not profile.isFrozen then
        return
    end

    local active = profile.activeLevelUp
    if not active or active.committed then
        return
    end

    if typeof(choiceId) ~= "string" or choiceId == "" then
        return
    end

    local chosen = nil
    if active.choices then
        for _, option in ipairs(active.choices) do
            if option.id == choiceId then
                chosen = option
                break
            end
        end
    end

    if not chosen then
        return
    end

    -- TODO: integrate stat and perk application once systems are available.

    self:ApplyLevelUpChoice(player, profile, chosen)
end

function PlayerProgressService:CompleteLevelUp(player: Player, profile)
    if profile.queue[1] then
        table.remove(profile.queue, 1)
    end

    profile.activeLevelUp = nil
    profile.isFrozen = false
    self.ActiveFreezes = math.max(0, self.ActiveFreezes - 1)
    if self.ActiveFreezes == 0 then
        self:SetWorldFreeze(false)
    end

    self:FireXPChanged(player, profile)
    self:BroadcastLevelUpStatus()
    self:ProcessQueue(player, profile)
end

function PlayerProgressService:FireXPChanged(player: Player, profile)
    Net:FireAll("XPChanged", player, profile.xp, profile.xpToNext)
end

return PlayerProgressService
