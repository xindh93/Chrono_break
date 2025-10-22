local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Shared.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local SkillDefs = require(ReplicatedStorage.Shared.SkillDefs)

local CombatService = Knit.CreateService({
    Name = "CombatService",
    Client = {},
})

function CombatService:KnitInit()
    self.LastBasicAttack = {} :: {[Player]: number}
    self.SkillCooldowns = {} :: {[Player]: {[string]: number}}
    self.Random = Random.new()
end

function CombatService:KnitStart()
    self.EnemyService = Knit.GetService("EnemyService")
    self.RewardService = Knit.GetService("RewardService")
    self.PlayerProgressService = Knit.GetService("PlayerProgressService")

    local attackEvent = Net:GetEvent("Attack")
    attackEvent.OnServerEvent:Connect(function(player)
        self:HandleBasicAttack(player)
    end)

    local skillEvent = Net:GetEvent("Skill")
    skillEvent.OnServerEvent:Connect(function(player, skillId, payload)
        self:HandleSkill(player, tostring(skillId), payload)
    end)
end

function CombatService:GetSkillLevel(player: Player, skillId: string): number
    local attributeName = "SkillLevel_" .. skillId
    local level = player:GetAttribute(attributeName)
    if typeof(level) == "number" then
        return math.clamp(math.floor(level), 1, 20)
    end
    return 1
end

function CombatService:GetCooldownData(player: Player)
    local cooldowns = self.SkillCooldowns[player]
    if not cooldowns then
        cooldowns = {}
        self.SkillCooldowns[player] = cooldowns
    end
    return cooldowns
end

function CombatService:IsSkillReady(player: Player, skillId: string, cooldown: number): boolean
    local cooldowns = self:GetCooldownData(player)
    local lastUse = cooldowns[skillId]
    if not lastUse then
        return true
    end
    return os.clock() - lastUse >= cooldown
end

function CombatService:SetSkillUsed(player: Player, skillId: string)
    local cooldowns = self:GetCooldownData(player)
    cooldowns[skillId] = os.clock()
end

function CombatService:HandleBasicAttack(player: Player)
    if not Net:CheckRate(player, "BasicAttack", 5) then
        return
    end

    local now = os.clock()
    local last = self.LastBasicAttack[player]
    if last and now - last < Config.Combat.BasicAttackCooldown then
        return
    end
    self.LastBasicAttack[player] = now

    local character = player.Character
    if not character then
        return
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return
    end

    local lookVector = root.CFrame.LookVector
    local attackRange = Config.Combat.BasicAttackRange
    local attackAngle = Config.Combat.BasicAttackAngle
    local dealtDamage = 0

    local statSnapshot = self.PlayerProgressService and self.PlayerProgressService:GetStatSnapshot(player) or nil
    local damageMultiplier = 1
    local critChance = 0
    local critDamageMultiplier = 1
    local lifesteal = 0
    if statSnapshot then
        attackRange += statSnapshot.AttackRangeBonus or 0
        damageMultiplier += statSnapshot.AttackPowerBonus or 0
        critChance = math.clamp(statSnapshot.CritChance or 0, 0, 1)
        critDamageMultiplier = statSnapshot.CritDamageMultiplier or 1
        lifesteal = math.clamp(statSnapshot.Lifesteal or 0, 0, 1)
    end

    for enemyModel, enemyData in pairs(self.EnemyService:GetActiveEnemies()) do
        local enemyRoot = enemyModel.PrimaryPart
        if enemyRoot then
            local offset = enemyRoot.Position - root.Position
            local distance = offset.Magnitude
            if distance <= attackRange and distance > 0 then
                local direction = offset.Unit
                local angle = math.deg(math.acos(math.clamp(direction:Dot(lookVector), -1, 1)))
                if angle <= attackAngle / 2 then
                    local damage = Config.Combat.BasicAttackDamage * damageMultiplier
                    if critChance > 0 and (self.Random and self.Random:NextNumber() or math.random()) < critChance then
                        damage *= critDamageMultiplier
                    end
                    self.EnemyService:ApplyDamage(enemyModel, damage, player)
                    dealtDamage = dealtDamage + damage
                end
            end
        end
    end

    if dealtDamage > 0 then
        self.RewardService:RecordDamage(player, dealtDamage)
        if lifesteal > 0 and humanoid then
            local healAmount = dealtDamage * lifesteal
            humanoid.Health = math.clamp(humanoid.Health + healAmount, 0, humanoid.MaxHealth)
        end
    end
end

function CombatService:HandleSkill(player: Player, skillId: string, payload)
    local definition = SkillDefs[skillId]
    if not definition then
        return
    end

    if not Net:CheckRate(player, "Skill_" .. skillId, 3) then
        return
    end

    local statSnapshot = self.PlayerProgressService and self.PlayerProgressService:GetStatSnapshot(player) or nil
    local cooldown = definition.Cooldown
    if statSnapshot and statSnapshot.SkillCooldownMultiplier then
        cooldown = cooldown * math.clamp(statSnapshot.SkillCooldownMultiplier, 0.1, 1)
    end

    if not self:IsSkillReady(player, skillId, cooldown) then
        return
    end

    local character = player.Character
    if not character then
        return
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return
    end

    local level = self:GetSkillLevel(player, skillId)
    local levelInfo = definition.LevelCurve(level)

    if skillId == "AOE_Blast" then
        self:ExecuteAOEBlast(player, root, humanoid, levelInfo, payload, statSnapshot)
    end

    self:SetSkillUsed(player, skillId)
    local serverNow = Workspace:GetServerTimeNow()
    Net:FireClient(player, "HUD", {
        SkillCooldowns = {
            [skillId] = {
                Cooldown = cooldown,
                Timestamp = serverNow,
                ReadyTime = serverNow + cooldown,
                Remaining = cooldown,
            },
        },
    })

    Net:FireClient(player, "Combat", {
        Type = "SkillUsed",
        SkillId = skillId,
        Cooldown = cooldown,
    })
end

function CombatService:ExecuteAOEBlast(player: Player, root: BasePart, humanoid: Humanoid?, levelInfo, payload, statSnapshot)
    local baseRadius = levelInfo.Radius or 10
    local radiusScale = 1.3
    -- Match the fully expanded VFX ring which scales up to ~130% of the base radius.
    local radius = baseRadius * radiusScale
    local baseDamage = levelInfo.Damage or 40
    local origin = root.Position

    if typeof(payload) == "table" and payload.TargetPosition then
        local target = payload.TargetPosition :: Vector3
        if typeof(target) == "Vector3" then
            local delta = target - origin
            local maxDistance = Config.Combat.SkillAOEClampRadius
            if delta.Magnitude > maxDistance then
                delta = delta.Unit * maxDistance
            end
            origin = origin + delta
        end
    end

    local damageMultiplier = 1
    local critChance = 0
    local critDamageMultiplier = 1
    local lifesteal = 0
    if statSnapshot then
        damageMultiplier += statSnapshot.AttackPowerBonus or 0
        critChance = math.clamp(statSnapshot.CritChance or 0, 0, 1)
        critDamageMultiplier = statSnapshot.CritDamageMultiplier or 1
        lifesteal = math.clamp(statSnapshot.Lifesteal or 0, 0, 1)
    end

    local affected = 0
    local dealtDamage = 0

    for enemyModel in pairs(self.EnemyService:GetActiveEnemies()) do
        local enemyRoot = enemyModel.PrimaryPart
        if enemyRoot and (enemyRoot.Position - origin).Magnitude <= radius then
            local damage = baseDamage * damageMultiplier
            if critChance > 0 and (self.Random and self.Random:NextNumber() or math.random()) < critChance then
                damage *= critDamageMultiplier
            end
            self.EnemyService:ApplyDamage(enemyModel, damage, player)
            affected += 1
            dealtDamage += damage
        end
    end

    if affected > 0 then
        self.RewardService:RecordDamage(player, dealtDamage)
        if lifesteal > 0 and humanoid then
            local healAmount = dealtDamage * lifesteal
            humanoid.Health = math.clamp(humanoid.Health + healAmount, 0, humanoid.MaxHealth)
        end
    end

    Net:FireAll("Combat", {
        Type = "AOE",
        Position = origin,
        Radius = radius,
    })
end

function CombatService:ApplyDamageToPlayer(player: Player, amount: number, _source)
    if amount <= 0 then
        return false
    end

    local character = player.Character
    if not character or character:GetAttribute("IFrame") then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    humanoid:TakeDamage(amount)
    return true
end

return CombatService
