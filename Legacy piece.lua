local Fluent           = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager      = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Vesper Hub", SubTitle = "Legacy Piece",
    TabWidth = 160, Size = UDim2.fromOffset(580, 460),
    Acrylic = false, Theme = "Dark", MinimizeKey = Enum.KeyCode.LeftControl,
})
local Tabs = {
    Farm     = Window:AddTab({ Title = "Auto Farm", Icon = "sword" }),
    Stats    = Window:AddTab({ Title = "Stats",     Icon = "trending-up" }),
    Island   = Window:AddTab({ Title = "Island", Icon = "tree-pine" }),
    Settings = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
}
local Options = Fluent.Options

local RS          = game:GetService("ReplicatedStorage")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local InputRemote = RS:WaitForChild("Remotes"):WaitForChild("Input")
local TpRemote    = RS:WaitForChild("Remotes"):WaitForChild("TeleportToPortal")
local QuestRemote = RS:WaitForChild("Remotes"):WaitForChild("Functions"):WaitForChild("Input")

local FarmTable = {
    { min=1,    max=199,  island="Starter",        quest="Quest Bandits",              mobs={"Bandit"} },
    { min=200,  max=249,  island="Starter",        quest="Quest Bandit Leader",        mobs={"Bandit Leader"} },
    { min=250,  max=499,  island="JungleIsland",   quest="Quest Namekians",            mobs={"Namekian"} },
    { min=500,  max=749,  island="JungleIsland",   quest="Quest Piccolo",              mobs={"Piccolo"} },
    { min=750,  max=999,  island="JungleIsland",   quest="Quest Serpoians",            mobs={"Serpoian"} },
    { min=1000, max=1349, island="JungleIsland",   quest="Quest Serpoian (True Form)", mobs={"Serpoian (True Form)"} },
    { min=1350, max=1749, island="ACity",          quest="Quest Beggars",              mobs={"Beggar"} },
    { min=1750, max=2249, island="ACity",          quest="Quest Aristocrat",           mobs={"Aristocrat"} },
    { min=2250, max=2749, island="JujutsuAcademy", quest="Quest Cursed Students",      mobs={"Cursed Student"} },
    { min=2750, max=3249, island="JujutsuAcademy", quest="Quest Cursed Teacher",       mobs={"Cursed Teacher"} },
    { min=3250, max=3849, island="HollowLand",     quest="Quest Hollows",              mobs={"Hollow"} },
    { min=3850, max=4499, island="HollowLand",     quest="Quest Shinigami",            mobs={"Shinigami"} },
    { min=4500, max=5249, island="SlayerMansion",  quest="Quest Demon Slayers",        mobs={"Demon Slayer"} },
    { min=5250, max=5999, island="SlayerMansion",  quest="Quest Nameless Pillar",      mobs={"Nameless Pillar"} },
    { min=6000, max=6749, island="TokyoGhoul",     quest="Quest Ghoul Investigators",  mobs={"Ghoul Investigator"} },
    { min=6750, max=7499, island="TokyoGhoul",     quest="Quest Ghouls",               mobs={"Ghoul"} },
    { min=7500, max=8249, island="RuinCity",       quest="Quest Distortion Monsters",  mobs={"Distortion Monster"} },
    { min=8250, max=9999, island="RuinCity",       quest="Quest Hishaku Members",      mobs={"Hishaku Member"} },
}

-- State
local AutoFarmEnabled  = false
local AutoEquipEnabled = false
local AutoSkillEnabled = false
local CurrentTarget    = nil
local SelectedToolName = nil
local lastIsland       = ""
local QuestBusy        = false

local SkillSlots   = { "Z", "X", "C", "V", "F" }
local SkillEnabled = { Z=false, X=false, C=false, V=false, F=false }

-- Helpers
local function GetLevel()
    local ok, v = pcall(function() return LocalPlayer.Data.Level.Value end)
    return ok and v or 0
end
local function GetFarmData()
    local lvl = GetLevel()
    for _, d in ipairs(FarmTable) do
        if lvl >= d.min and lvl <= d.max then return d end
    end
    return FarmTable[#FarmTable]
end
local function GetHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function IsAlive()
    local c = LocalPlayer.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end
local function WaitForAlive()
    while not IsAlive() do task.wait(0.5) end
    task.wait(1.5)
end
local function IsQuestActive(questName)
    local ok, result = pcall(function()
        return LocalPlayer.Data.Quests.Main:FindFirstChild(questName) ~= nil
    end)
    return ok and result == true
end
local function CancelQuest()
    pcall(function() QuestRemote:InvokeServer("Quest", "Cancel") end)
    pcall(function() QuestRemote:InvokeServer("Quest", "Abandon") end)
end
local function FindNearestMob(mobs)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return nil end
    local hrp = GetHRP()
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, v in ipairs(folder:GetChildren()) do
        local eHrp = v:FindFirstChild("HumanoidRootPart")
        local hum  = v:FindFirstChildOfClass("Humanoid")
        if eHrp and hum and hum.Health > 0 then
            for _, name in ipairs(mobs) do
                if v.Name == name then
                    local d = (eHrp.Position - hrp.Position).Magnitude
                    if d < bestDist then best = v; bestDist = d end
                end
            end
        end
    end
    return best
end
local function IsTargetAlive(target)
    if not target then return false end
    local ok, result = pcall(function()
        if target.Parent == nil then return false end
        local h = target:FindFirstChildOfClass("Humanoid")
        return h ~= nil and h.Health > 0
    end)
    return ok and result == true
end
local function TeleportToMob(mob)
    local hrp  = GetHRP()
    local eHrp = mob and mob:FindFirstChild("HumanoidRootPart")
    if not (hrp and eHrp) then return end
    hrp.CFrame = CFrame.new(eHrp.Position + Vector3.new(0, 3.5, 0), eHrp.Position)
    hrp.AssemblyLinearVelocity  = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end
local function FindToolInstance(name)
    if not name or name == "None" then return nil end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild(name) then return char[name] end
    return LocalPlayer.Backpack:FindFirstChild(name)
end
local function Attack()
    local toolObj = FindToolInstance(SelectedToolName)
    if toolObj then
        pcall(function() InputRemote:FireServer("Tool", toolObj, "M1") end)
    else
        pcall(function() InputRemote:FireServer("Tool", "Combat", "M1") end)
    end
end
local function DisableAllSkills()
    pcall(function()
        local s = LocalPlayer.Data.Settings
        for _, slot in ipairs(SkillSlots) do
            local bv = s:FindFirstChild("AutoSkill_" .. slot)
            if bv then bv.Value = false end
        end
    end)
end
local function GetToolList()
    local names, seen = {}, {}
    local function scan(c)
        if not c then return end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and not seen[t.Name] then
                seen[t.Name] = true; table.insert(names, t.Name)
            end
        end
    end
    scan(LocalPlayer.Backpack); scan(LocalPlayer.Character)
    table.sort(names)
    return #names > 0 and names or {"None"}
end

-- map ชื่อ island key → ชื่อใน Data.Spawn
local SpawnNames = {
    ["Starter"]        = "Starter Island",
    ["JungleIsland"]   = "Jungle Island",
    ["ACity"]          = "A-City",
    ["JujutsuAcademy"] = "Jujutsu Academy",
    ["HollowLand"]     = "Hueco Mundo",
    ["SlayerMansion"]  = "Ubuyashiki Mansion",
    ["TokyoGhoul"]     = "Tokyo Ghoul",
    ["RuinCity"]       = "Ruin City",
}

local function GetCurrentSpawn()
    local ok, v = pcall(function() return LocalPlayer.Data.Spawn.Value end)
    return ok and v or ""
end

local function SetSpawn(islandKey)
    local spawnName = SpawnNames[islandKey]
    if not spawnName then return end
    if GetCurrentSpawn() == spawnName then return end -- set แล้วไม่ทำซ้ำ

    local npcs = workspace:FindFirstChild("NPCs")
    if not npcs then return end
    local hrp = GetHRP()
    if not hrp then return end

    local closest, closestDist = nil, math.huge
    for _, v in pairs(npcs:GetChildren()) do
        if v.Name == "Spawner" then
            local sHrp = v:FindFirstChild("HumanoidRootPart")
            if sHrp then
                local dist = (sHrp.Position - hrp.Position).Magnitude
                if dist < closestDist then
                    closest = v
                    closestDist = dist
                end
            end
        end
    end

    if closest then
        local sHrp = closest:FindFirstChild("HumanoidRootPart")
        if sHrp then
            hrp.CFrame = sHrp.CFrame * CFrame.new(0, 0, 3)
            task.wait(0.3)
        end
        pcall(function() QuestRemote:InvokeServer("Spawn", "Spawner") end)
        print("✅ Set spawn: " .. spawnName)
    end
end

-- ============================================
--  LOOP 1: Quest Manager
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.3)
        if not AutoFarmEnabled then lastIsland = ""; continue end
        if not IsAlive() then continue end
        if QuestBusy then continue end

        local data = GetFarmData()

        if data.island ~= lastIsland then
            CancelQuest()
            pcall(function() TpRemote:FireServer(data.island) end)
            lastIsland    = data.island
            CurrentTarget = nil
            task.wait(4)
            SetSpawn(data.island)
            continue
        end

        if not IsQuestActive(data.quest) then
            QuestBusy = true
            local npcFolder = workspace:FindFirstChild("NPCs")
            local npc = npcFolder and npcFolder:FindFirstChild(data.quest)
            if npc then
                local hrp  = GetHRP()
                local nHrp = npc:FindFirstChild("HumanoidRootPart")
                if hrp and nHrp then
                    hrp.CFrame = nHrp.CFrame * CFrame.new(0, 0, 3)
                    task.wait(0.3)
                end
            end
            pcall(function() QuestRemote:InvokeServer("Quest", "Accept", data.quest) end)
            task.wait(0.5)
            QuestBusy = false
        end
    end
end)

-- ============================================
--  LOOP 2: Farm (target tracking + teleport)
-- ============================================
task.spawn(function()
    local lastKillPos = nil
    while true do
        task.wait(0.05)
        if not AutoFarmEnabled then
            CurrentTarget = nil; lastKillPos = nil; continue
        end
        if not IsAlive() then
            CurrentTarget = nil; WaitForAlive(); continue
        end
        if QuestBusy then
            CurrentTarget = nil; continue
        end

        local data = GetFarmData()
        if not IsQuestActive(data.quest) then
            CurrentTarget = nil; continue
        end

        if not IsTargetAlive(CurrentTarget) then
            CurrentTarget = FindNearestMob(data.mobs)
        end

        if not CurrentTarget then
            if lastKillPos then
                local hrp = GetHRP()
                if hrp then
                    hrp.CFrame = CFrame.new(lastKillPos + Vector3.new(0, 8, 0))
                    hrp.AssemblyLinearVelocity  = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end
            end
            continue
        end

        local ok, ePos = pcall(function()
            return CurrentTarget:FindFirstChild("HumanoidRootPart").Position
        end)
        if ok and ePos then lastKillPos = ePos end
        pcall(function() TeleportToMob(CurrentTarget) end)
    end
end)

-- ============================================
--  LOOP 3: Attack
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.05)
        if not AutoFarmEnabled then continue end
        if not IsAlive() then continue end
        if QuestBusy then continue end

        local data = GetFarmData()
        if not IsQuestActive(data.quest) then continue end
        if not IsTargetAlive(CurrentTarget) then continue end
        Attack()
    end
end)

-- ============================================
--  LOOP 4: Auto Skill
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(function()
            local s = LocalPlayer.Data.Settings
            for _, slot in ipairs(SkillSlots) do
                local bv = s:FindFirstChild("AutoSkill_" .. slot)
                if bv then
                    bv.Value = AutoSkillEnabled and AutoFarmEnabled and (SkillEnabled[slot] == true)
                end
            end
        end)
    end
end)

-- ============================================
--  LOOP 5: Auto Equip
-- ============================================
task.spawn(function()
    while true do
        task.wait(1)
        if not AutoEquipEnabled or not SelectedToolName then continue end
        local char = LocalPlayer.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or char:FindFirstChild(SelectedToolName) then continue end
        local tool = LocalPlayer.Backpack:FindFirstChild(SelectedToolName)
        if tool then pcall(function() hum:EquipTool(tool) end) end
    end
end)

-- ============================================
--  UI: Teleport Tab
-- ============================================
Tabs.Teleport:AddSection("Island Teleport")

local IslandList = {
    "Starter", "Legacy", "JungleIsland", "IceIsland",
    "ACity", "JujutsuAcademy", "HollowLand", "SlayerMansion",
    "TokyoGhoul", "RuinCity"
}

local SelectedIsland = IslandList[1]

Tabs.Teleport:AddDropdown("IslandDropdown", {
    Title = "Select Island",
    Values = IslandList,
    Default = 1,
    Callback = function(v) SelectedIsland = v end,
})

Tabs.Teleport:AddButton({
    Title = "Teleport",
    Callback = function()
        pcall(function() TpRemote:FireServer(SelectedIsland) end)
        Fluent:Notify({ Title="Teleport", Content="Teleporting to " .. SelectedIsland, Duration=2 })
    end,
})

-- ============================================
--  Auto Stats
-- ============================================
local AutoStatsEnabled = false
local AddAmount        = 1
local StatPointer      = 1
local StatNames = { "Strength", "Defense", "Weapon", "Ability" }
local StatKeys  = { "StrengthToggle", "DefenseToggle", "WeaponToggle", "AbilityToggle" }

task.spawn(function()
    while true do
        task.wait(0.1)
        if not AutoStatsEnabled then continue end
        local enabled = {}
        for i, key in ipairs(StatKeys) do
            if Options[key] and Options[key].Value then
                table.insert(enabled, StatNames[i])
            end
        end
        if #enabled == 0 then continue end
        if StatPointer > #enabled then StatPointer = 1 end
        pcall(function()
            QuestRemote:InvokeServer("AddPoint", enabled[StatPointer], AddAmount)
        end)
        StatPointer = (StatPointer % #enabled) + 1
    end
end)

-- ============================================
--  UI: Farm Tab
-- ============================================
Tabs.Farm:AddSection("Auto Farm + Auto Quest")
Tabs.Farm:AddToggle("FarmToggle", {
    Title = "Enable Auto Farm + Quest",
    Description = "Farm mobs and accept quests automatically",
    Default = false,
}):OnChanged(function()
    AutoFarmEnabled = Options.FarmToggle.Value
    if AutoFarmEnabled then
        task.spawn(function()
            task.wait(0.3)
            if not IsAlive() then return end
            local data = GetFarmData()
            CancelQuest()
            lastIsland = ""; CurrentTarget = nil
            pcall(function() TpRemote:FireServer(data.island) end)
            lastIsland = data.island
        end)
    else
        CurrentTarget = nil; lastIsland = ""
        DisableAllSkills()
    end
end)

Tabs.Farm:AddSection("Weapon Management")
local toolDropdown = Tabs.Farm:AddDropdown("ToolSelect", {
    Title = "Select Farming Weapon", Values = GetToolList(), Multi = false, Default = 1,
    Callback = function(v) SelectedToolName = (v ~= "None") and v or nil end,
})
Tabs.Farm:AddButton({
    Title = "Refresh Weapon List",
    Callback = function()
        local list = GetToolList()
        toolDropdown:SetValues(list)
        Fluent:Notify({ Title="Refreshed", Content=#list.." weapons", Duration=2 })
    end,
})
Tabs.Farm:AddToggle("EquipToggle", {
    Title = "Auto Equip Selected Weapon", Default = false,
}):OnChanged(function() AutoEquipEnabled = Options.EquipToggle.Value end)

Tabs.Farm:AddSection("Auto Skill (Built-in)")
Tabs.Farm:AddParagraph({
    Title   = "Info",
    Content = "Uses the game's built-in AutoSkill system (Data.Settings.AutoSkill_*).\nThe game handles cooldowns automatically.",
})
Tabs.Farm:AddToggle("AutoSkillToggle", {
    Title = "Enable Auto Skill", Default = false,
}):OnChanged(function()
    AutoSkillEnabled = Options.AutoSkillToggle.Value
    if not AutoSkillEnabled then DisableAllSkills() end
end)
for _, slot in ipairs(SkillSlots) do
    local s = slot
    Tabs.Farm:AddToggle(s.."Toggle", {
        Title = "Auto Skill [" .. s .. "]", Default = false,
    }):OnChanged(function() SkillEnabled[s] = Options[s.."Toggle"].Value end)
end

-- ============================================
--  UI: Stats Tab
-- ============================================
Tabs.Stats:AddSection("Stat Allocation System")
Tabs.Stats:AddToggle("AutoStatsToggle", { Title="Enable Auto Stats", Default=false })
    :OnChanged(function() AutoStatsEnabled = Options.AutoStatsToggle.Value; StatPointer=1 end)
Tabs.Stats:AddSlider("AddAmountSlider", {
    Title="Points Per Iteration", Default=1, Min=1, Max=100, Rounding=0,
    Callback=function(v) AddAmount=v end,
})
Tabs.Stats:AddSection("Target Stat Filter")
Tabs.Stats:AddToggle("StrengthToggle", { Title="Strength", Default=false })
Tabs.Stats:AddToggle("DefenseToggle",  { Title="Defense",  Default=false })
Tabs.Stats:AddToggle("WeaponToggle",   { Title="Weapon",   Default=false })
Tabs.Stats:AddToggle("AbilityToggle",  { Title="Ability",  Default=false })

-- ============================================
--  Settings
-- ============================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("VesperHub")
SaveManager:SetFolder("VesperHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
pcall(function() SaveManager:LoadAutoloadConfig() end)
Window:SelectTab(1)
Fluent:Notify({ Title="Vesper Hub", Content="Loaded.", Duration=3 })