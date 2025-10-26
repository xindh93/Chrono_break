local Config = {}

Config.LOBBY_PLACE_ID = 0

Config.Session = {
    TimeLimit = 600,
    Infinite = false,
    BossTime = 480,
    EnrageTime = 600,
    PulseInterval = 30,
    SurgeTimes = {120, 240, 360},
    SurgeDuration = 10,
    ResultDuration = 12,
    PrepareDuration = 5,
}

Config.Enemy = {
    BaseHealth = 70,
    HealthGrowthRate = 0.25,
    BaseSpeed = 12,
    SpeedGrowthRate = 0.45,
    MaxSpeedDelta = 8,
    BaseDamage = 10,
    DamageGrowth = 1.5,
    SpawnInterval = 5,
    PulseBonus = 3,
    SurgeIntervalMult = 0.8,
    EliteChanceStart = 0.15,
    EliteChanceAfter6m = 0.30,
    MaxActive = 80,
    BossPhaseMaxActive = 60,
    PathRefresh = 0.25,
    Spawn = {
        PlayerRadiusMin = 10,
        PlayerRadiusMax = 15,
        SpawnHeight = 6,
        MaxSpawnAttempts = 8,
    },
}

Config.Combat = {
    BasicAttackRange = 10,
    BasicAttackAngle = 120,
    BasicAttackDamage = 28,
    BasicAttackCooldown = 0.75,
    SkillAOEClampRadius = 35,
}

Config.Rewards = {
    KillGold = 6,
    KillXP = 8,
    MilestoneGold = {
        [120] = 10,
        [240] = 15,
        [360] = 20,
    },
    ResultXPBonus = 100,
}

Config.Leveling = Config.Leveling or {}

local leveling = Config.Leveling
leveling.BaseXP = leveling.BaseXP or 60
leveling.Growth = leveling.Growth or 1.2
leveling.MaxLevel = leveling.MaxLevel or 50
leveling.XP = leveling.XP or {
    Kill = 12,
    Assist = 6,
    BossKill = 250,
    Minute = 0,
}

leveling.UI = leveling.UI or {}
local levelingUI = leveling.UI
levelingUI.LerpSpeed = levelingUI.LerpSpeed or 6
levelingUI.ToastDuration = levelingUI.ToastDuration or 2.0
levelingUI.FreezeFade = levelingUI.FreezeFade or 0.25
levelingUI.SelectionTimeout = levelingUI.SelectionTimeout or 30

function leveling.XPToNext(level: number): number
    level = math.max(1, math.floor(level))
    local base = leveling.BaseXP or 0
    local growth = leveling.Growth or 1
    local value = base * (growth ^ (level - 1))
    return math.floor(value)
end

Config.Map = {
    FloorSize = Vector3.new(220, 2, 220),
    FloorMaterial = Enum.Material.Slate,
    LightingColor = Color3.fromRGB(70, 70, 70),
    FloorTransparency = 1,
}

Config.Skill = Config.Skill or {}

Config.Skill.Dash = Config.Skill.Dash or {
    Cooldown = 6.0,
    Distance = 12.0,
    Duration = 0.18,
    IFrame = 0.2,
}

-- =========================
-- Stage / Boss / Enrage
-- =========================
Config.UI = Config.UI or {}

local ui = Config.UI
ui.SafeMargin = ui.SafeMargin or 24
ui.Font = ui.Font or Enum.Font.Gotham
ui.BoldFont = ui.BoldFont or Enum.Font.GothamBold
ui.TopBarHeight = ui.TopBarHeight or 52
ui.TopBarBackgroundColor = ui.TopBarBackgroundColor or Color3.fromRGB(18, 24, 32)
ui.TopBarTransparency = ui.TopBarTransparency or 0.32
ui.TopLabelTextSize = ui.TopLabelTextSize or 20
ui.InfoTextSize = ui.InfoTextSize or 18
ui.SmallTextSize = ui.SmallTextSize or 16
ui.TopInfoWidth = ui.TopInfoWidth or 240
ui.ResourceHeight = ui.ResourceHeight or 60
ui.ResourcePadding = ui.ResourcePadding or 6
ui.SectionSpacing = ui.SectionSpacing or 14
ui.AlertAreaOffset = ui.AlertAreaOffset or 14
ui.AlertAreaWidth = ui.AlertAreaWidth or 440
ui.AlertAreaHeight = ui.AlertAreaHeight or 140
ui.AlertPadding = ui.AlertPadding or 8
ui.AlertTextSize = ui.AlertTextSize or 20
ui.ReservedAlertHeight = ui.ReservedAlertHeight or 56
ui.ReservedAlertCornerRadius = ui.ReservedAlertCornerRadius or 10
ui.AlertBackgroundColor = ui.AlertBackgroundColor or Color3.fromRGB(18, 24, 32)
ui.AlertBackgroundTransparency = ui.AlertBackgroundTransparency or 0.35
ui.MessageHeight = ui.MessageHeight or 40
ui.WaveAnnouncementHeight = ui.WaveAnnouncementHeight or 48
ui.MessageDuration = ui.MessageDuration or 3
ui.DisplayOrder = ui.DisplayOrder or { HUD = 0 }

ui.XP = ui.XP or {}
local xp = ui.XP
xp.BarWidth = xp.BarWidth or 380
xp.BarHeight = xp.BarHeight or 18
xp.LevelWidth = xp.LevelWidth or 60
xp.LevelSpacing = xp.LevelSpacing or 12
xp.LabelHeight = xp.LabelHeight or 20
xp.LabelTextSize = xp.LabelTextSize or 18
xp.LevelTextSize = xp.LevelTextSize or 24
xp.BackgroundColor = xp.BackgroundColor or Color3.fromRGB(18, 24, 32)
xp.BackgroundTransparency = xp.BackgroundTransparency or 0.45
xp.FillColor = xp.FillColor or Color3.fromRGB(88, 182, 255)
xp.FillTransparency = xp.FillTransparency or 0.05
xp.CornerRadius = xp.CornerRadius or 10
xp.BottomOffset = xp.BottomOffset or 0
xp.LabelPrefix = xp.LabelPrefix or "XP"

ui.Dash = ui.Dash or {}
local dash = ui.Dash
dash.Size = dash.Size or 72
dash.BackgroundColor = dash.BackgroundColor or Color3.fromRGB(18, 24, 32)
dash.BackgroundTransparency = dash.BackgroundTransparency or 0.25
dash.FillColor = dash.FillColor or Color3.fromRGB(120, 200, 255)
dash.FillTransparency = dash.FillTransparency or 0.15
dash.StrokeColor = dash.StrokeColor or Color3.fromRGB(120, 200, 255)
dash.StrokeThickness = dash.StrokeThickness or 2
dash.StrokeTransparency = dash.StrokeTransparency or 0.2
dash.ReadyColor = dash.ReadyColor or Color3.fromRGB(180, 255, 205)
dash.KeyText = dash.KeyText or "E"
dash.ReadyText = dash.ReadyText or "Ready"

ui.Party = ui.Party or {}
local party = ui.Party
party.Width = party.Width or 240
party.Padding = party.Padding or 8
party.EntryHeight = party.EntryHeight or 42
party.BackgroundColor = party.BackgroundColor or Color3.fromRGB(18, 24, 32)
party.BackgroundTransparency = party.BackgroundTransparency or 0.25
party.LocalPlayerTransparency = party.LocalPlayerTransparency or 0.18
party.CornerRadius = party.CornerRadius or 10
party.StrokeColor = party.StrokeColor or Color3.fromRGB(80, 120, 160)
party.StrokeThickness = party.StrokeThickness or 1.5
party.StrokeTransparency = party.StrokeTransparency or 0.35
party.HealthFillColor = party.HealthFillColor or Color3.fromRGB(88, 255, 120)
party.HealthFillTransparency = party.HealthFillTransparency or 0.25
party.NameTextSize = party.NameTextSize or 16
party.HealthTextSize = party.HealthTextSize or 15
party.EmptyText = party.EmptyText or "No party members"

ui.Abilities = ui.Abilities or {}
local abilities = ui.Abilities
abilities.Width = abilities.Width or 260
abilities.Height = abilities.Height or 90
abilities.SkillWidth = abilities.SkillWidth or 150
abilities.SkillHeight = abilities.SkillHeight or 36
abilities.Spacing = abilities.Spacing or 12
abilities.BottomOffset = abilities.BottomOffset or 0
abilities.SkillKey = abilities.SkillKey or "Q"
abilities.PrimarySkillId = abilities.PrimarySkillId or "AOE_Blast"
abilities.SkillTextSize = abilities.SkillTextSize or 18

Config.UI = {
    SafeMargin = 24,
    Font = Enum.Font.Gotham,
    BoldFont = Enum.Font.GothamBold,
    TopBarHeight = 52,
    TopBarBackgroundColor = Color3.fromRGB(18, 24, 32),
    TopBarTransparency = 0.32,
    TopLabelTextSize = 20,
    InfoTextSize = 18,
    SmallTextSize = 16,
    SectionSpacing = 14,
    AlertAreaOffset = 14,
    AlertAreaWidth = 440,
    AlertAreaHeight = 140,
    AlertTextSize = 20,
    ReservedAlertHeight = 56,
    AlertBackgroundColor = Color3.fromRGB(18, 24, 32),
    AlertBackgroundTransparency = 0.35,
    MessageDuration = 3,
    BottomReservedHeight = 96,
    XP = {
        BarWidth = 380,
        BarHeight = 18,
        LevelWidth = 60,
        LevelSpacing = 12,
        LabelHeight = 20,
        LabelTextSize = 18,
        LevelTextSize = 24,
        BackgroundColor = Color3.fromRGB(18, 24, 32),
        BackgroundTransparency = 0.45,
        FillColor = Color3.fromRGB(88, 182, 255),
        FillTransparency = 0.05,
        CornerRadius = 10,
    },
    Dash = {
        Size = 72,
        BackgroundColor = Color3.fromRGB(18, 24, 32),
        BackgroundTransparency = 0.25,
        FillColor = Color3.fromRGB(120, 200, 255),
        FillTransparency = 0.15,
        StrokeColor = Color3.fromRGB(120, 200, 255),
        StrokeThickness = 2,
        StrokeTransparency = 0.2,
    },
    Party = {
        Width = 240,
        Padding = 8,
        EntryHeight = 42,
        BackgroundColor = Color3.fromRGB(18, 24, 32),
        BackgroundTransparency = 0.25,
        CornerRadius = 10,
        StrokeColor = Color3.fromRGB(80, 120, 160),
        StrokeThickness = 1.5,
        StrokeTransparency = 0.35,
        HealthFillColor = Color3.fromRGB(88, 255, 120),
        HealthFillTransparency = 0.25,
        NameTextSize = 16,
        HealthTextSize = 15,
        EmptyText = "No party members",
    },
}

return Config
