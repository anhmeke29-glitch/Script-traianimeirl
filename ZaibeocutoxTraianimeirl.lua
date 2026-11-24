-- Zaibeocuto x Traianimeirl HUB | Unified Build v5.6 (Fix Auto Skill Z/X/C/V + Fast Attack + Hitbox)
local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.StopNavController) == "function" then
	pcall(env.StopNavController)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local VirtualInputManager = nil
pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

local function cleanupOldGui()
	local containers = { CoreGui }
	if type(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and typeof(h) == "Instance" then
			table.insert(containers, h)
		end
	end
	local lp = Players.LocalPlayer
	if lp and lp:FindFirstChild("PlayerGui") then
		table.insert(containers, lp.PlayerGui)
	end
	for _, parent in ipairs(containers) do
		pcall(function()
			for _, child in ipairs(parent:GetChildren()) do
				if child.Name == "NavControllerGui" then
					child:Destroy()
				end
			end
		end)
	end
end
cleanupOldGui()

-- ============================================================================
-- MODULE 1: RemoteResolver
-- ============================================================================
local RemoteResolver = {
	Cache = {},
}

function RemoteResolver.Get(dotPath)
	local cached = RemoteResolver.Cache[dotPath]
	if cached and cached.Parent then
		return cached
	end
	local current = ReplicatedStorage
	for segment in string.gmatch(dotPath, "[^%.]+") do
		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	RemoteResolver.Cache[dotPath] = current
	return current
end

-- ============================================================================
-- MODULE 2: ActionDispatcher (Fix Skill Z/X/C/V + Fast Attack)
-- ============================================================================
local ActionDispatcher = {
	Config = {
		NormalCooldown = 0.15,
		FastCooldown = 0.07,
		SkillCooldown = 0.65,
		AbilityKeys = { "Z", "X", "C", "V" },
		M1PerSkill = 5,
		SlotMode = 0, -- 0 = Tự do, 1 = Ô 1, 2 = Ô 2, 3 = Ô 3
		SwordTips = { "sword", "weapon", "katana", "blade" },
		FruitTips = { "fruit", "ability", "power", "devil", "blox" },
	},
	State = {
		SkillBusy = false,
		PauseM1Until = 0,
		LastFired = 0,
		LastTap = 0,
		LastSkillFired = 0,
		M1Count = 0,
		AbilityIndex = 1,
		TotalCalls = 0,
		TotalErrors = 0,
		LastAction = "READY",
		Destroyed = false,
	},
}

local function matchesAny(text, patterns)
	for _, pattern in ipairs(patterns) do
		if string.find(text, pattern, 1, true) then
			return true
		end
	end
	return false
end

function ActionDispatcher.ClassifyTool(tool)
	if not tool or not tool:IsA("Tool") then
		return "Melee"
	end
	local tip = string.lower(tool.ToolTip or "")
	local name = string.lower(tool.Name or "")
	if matchesAny(tip, ActionDispatcher.Config.FruitTips) or matchesAny(name, { "fruit", "love", "flame", "ice", "light", "magma", "dough", "dragon", "phoenix", "quake", "dark", "rumble", "buddha", "venom", "shadow", "control", "spirit", "leopard", "kitsune" }) then
		return "Fruit"
	elseif matchesAny(tip, ActionDispatcher.Config.SwordTips) or matchesAny(name, { "sword", "katana", "cutlass", "pipe", "bisento", "trident", "pole", "saber", "yami", "muramasa", "shark" }) then
		return "Sword"
	end
	return "Melee"
end

function ActionDispatcher.GetOrderedTools(player, character)
	local list = {}
	local seen = {}
	local equipped = character and character:FindFirstChildOfClass("Tool")
	local backpack = player and player:FindFirstChild("Backpack")

	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and not seen[item] then
				seen[item] = true
				table.insert(list, item)
			end
		end
	end
	if equipped and not seen[equipped] then
		table.insert(list, 1, equipped)
	end
	return list
end

function ActionDispatcher.EnsureEquipped(player, character)
	local slot = ActionDispatcher.Config.SlotMode
	if not player or not character or slot == 0 then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local tools = ActionDispatcher.GetOrderedTools(player, character)
	local targetTool = tools[slot]
	if targetTool and targetTool.Parent ~= character then
		pcall(humanoid.EquipTool, humanoid, targetTool)
	end
end

function ActionDispatcher.BuildActionString(character, suffix)
	suffix = tostring(suffix)
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return "FS_None_" .. suffix
	end
	local cleanName = string.gsub(tool.Name, "%s+", "")
	local kind = ActionDispatcher.ClassifyTool(tool)
	if kind == "Fruit" then
		return "DF_" .. cleanName .. "_" .. suffix
	elseif kind == "Sword" then
		return "SW_" .. cleanName .. "_" .. suffix
	end
	if string.lower(cleanName) == "combat" or string.lower(cleanName) == "none" then
		return "FS_None_" .. suffix
	end
	return "FS_" .. cleanName .. "_" .. suffix
end

function ActionDispatcher.PerformRealM1Tap()
	if not VirtualInputManager or os.clock() < ActionDispatcher.State.PauseM1Until then
		return
	end
	local now = os.clock()
	if (now - ActionDispatcher.State.LastTap) < 0.09 then
		return
	end
	ActionDispatcher.State.LastTap = now
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(800, 400)
	local tapX = math.floor(vp.X * 0.52)
	local tapY = math.floor(vp.Y * 0.22)
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(tapX, tapY, 0, true, game, 1)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(tapX, tapY, 0, false, game, 1)
	end)
end

function ActionDispatcher.TriggerMobileSkillButton(player, keyName)
	local pGui = player and player:FindFirstChild("PlayerGui")
	if not pGui then
		return false
	end
	local targetKey = string.upper(tostring(keyName))
	local clicked = false

	for _, desc in ipairs(pGui:GetDescendants()) do
		if (desc:IsA("TextButton") or desc:IsA("ImageButton")) and desc.Visible then
			local parentGui = desc:FindFirstAncestorOfClass("ScreenGui")
			if parentGui and parentGui.Name ~= "NavControllerGui" and parentGui.Enabled then
				local btnName = string.upper(desc.Name)
				local matched = (btnName == targetKey or btnName == ("SKILL" .. targetKey) or btnName == ("KEY" .. targetKey))
				if not matched then
					for _, child in ipairs(desc:GetDescendants()) do
						if child:IsA("TextLabel") and string.upper(string.gsub(child.Text, "%s+", "")) == targetKey then
							matched = true
							break
						end
					end
				end

				if matched then
					if type(firesignal) == "function" then
						pcall(firesignal, desc.MouseButton1Down)
						pcall(firesignal, desc.Activated)
						pcall(firesignal, desc.MouseButton1Click)
						task.delay(0.12, function()
							pcall(firesignal, desc.MouseButton1Up)
						end)
						clicked = true
					elseif VirtualInputManager then
						local pos = desc.AbsolutePosition + (desc.AbsoluteSize * 0.5)
						task.spawn(function()
							pcall(function()
								VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
								task.wait(0.12)
								VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
							end)
						end)
						clicked = true
					end
				end
			end
		end
	end

	return clicked
end

function ActionDispatcher.SendKeyPress(keyName)
	if not VirtualInputManager then
		return
	end
	local keyCode = Enum.KeyCode[keyName]
	if not keyCode then
		return
	end
	task.spawn(function()
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
			task.wait(0.12)
			VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
		end)
	end)
end

function ActionDispatcher.FireSkill(player, character, key, targetPosition)
	local state = ActionDispatcher.State
	if state.Destroyed or state.SkillBusy then
		return false
	end
	local remote = RemoteResolver.Get("Chest.Remotes.Functions.SkillAction")
	local actionStr = ActionDispatcher.BuildActionString(character, key)
	local pos = (typeof(targetPosition) == "Vector3") and targetPosition or Vector3.new(0, 0, 0)

	state.SkillBusy = true
	state.PauseM1Until = os.clock() + 0.22
	state.LastSkillFired = os.clock()
	state.LastAction = "[SKILL] " .. actionStr

	ActionDispatcher.TriggerMobileSkillButton(player, key)
	ActionDispatcher.SendKeyPress(key)

	task.spawn(function()
		if remote then
			local ok = pcall(function()
				remote:InvokeServer(actionStr, {
					MouseHit = CFrame.new(pos),
					Hit = CFrame.new(pos),
					Pos = pos,
				})
			end)
			state.TotalCalls = state.TotalCalls + 1
			if not ok then
				state.TotalErrors = state.TotalErrors + 1
			end
		end
		task.wait(0.12)
		state.SkillBusy = false
	end)
	return true
end

function ActionDispatcher.StepAction(player, character, targetPosition, enableM1, cycleAbilities, fastAttack)
	local state = ActionDispatcher.State
	local config = ActionDispatcher.Config
	local now = os.clock()

	ActionDispatcher.EnsureEquipped(player, character)

	local readyForSkill = cycleAbilities
		and (not state.SkillBusy)
		and ((now - state.LastSkillFired) >= config.SkillCooldown)
		and ((not enableM1) or (state.M1Count >= config.M1PerSkill))

	if readyForSkill then
		local key = config.AbilityKeys[state.AbilityIndex]
		state.AbilityIndex = (state.AbilityIndex % #config.AbilityKeys) + 1
		if ActionDispatcher.FireSkill(player, character, key, targetPosition) then
			state.M1Count = 0
			return true
		end
	end

	if now < state.PauseM1Until then
		return false
	end

	local cd = fastAttack and config.FastCooldown or config.NormalCooldown
	if not enableM1 or (now - state.LastFired) < cd then
		return false
	end

	local tool = character and character:FindFirstChildOfClass("Tool")
	local kind = ActionDispatcher.ClassifyTool(tool)
	local m1Str = ActionDispatcher.BuildActionString(character, "M1")

	state.LastFired = now
	state.LastAction = (fastAttack and "[FAST] " or "") .. m1Str
	state.M1Count = state.M1Count + 1

	if tool then
		pcall(tool.Activate, tool)
		if type(firesignal) == "function" then
			pcall(firesignal, tool.Activated)
		end
	end

	if kind == "Sword" or kind == "Fruit" then
		task.spawn(ActionDispatcher.PerformRealM1Tap)
	end

	task.spawn(function()
		local remote = RemoteResolver.Get("Chest.Remotes.Functions.SkillAction")
		if remote then
			local ok = pcall(function()
				remote:InvokeServer(m1Str)
			end)
			state.TotalCalls = state.TotalCalls + 1
			if not ok then
				state.TotalErrors = state.TotalErrors + 1
			end
		end
	end)
	return true
end

-- ============================================================================
-- MODULE 3: HitboxExpander (Mở rộng Hitbox tại chỗ)
-- ============================================================================
local HitboxExpander = {
	OriginalSizes = setmetatable({}, { __mode = "k" }),
	OriginalTransparencies = setmetatable({}, { __mode = "k" }),
}

function HitboxExpander.RestoreAll()
	for rootPart, origSize in pairs(HitboxExpander.OriginalSizes) do
		if rootPart and rootPart.Parent then
			pcall(function()
				rootPart.Size = origSize
				rootPart.Transparency = HitboxExpander.OriginalTransparencies[rootPart] or 1
			end)
		end
		HitboxExpander.OriginalSizes[rootPart] = nil
		HitboxExpander.OriginalTransparencies[rootPart] = nil
	end
end

function HitboxExpander.Apply(mobList, expandHitbox, hitboxSize)
	if not expandHitbox then
		HitboxExpander.RestoreAll()
		return
	end
	if #mobList == 0 then
		return
	end

	local sz = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
	for _, entry in ipairs(mobList) do
		local model = entry.Model
		local mRoot = model and model:FindFirstChild("HumanoidRootPart")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if mRoot and hum and hum.Health > 0 then
			if not HitboxExpander.OriginalSizes[mRoot] then
				HitboxExpander.OriginalSizes[mRoot] = mRoot.Size
				HitboxExpander.OriginalTransparencies[mRoot] = mRoot.Transparency
			end
			if mRoot.Size ~= sz then
				mRoot.Size = sz
				mRoot.CanCollide = false
				mRoot.Transparency = 0.72
			end
		end
	end
end

-- ============================================================================
-- MODULE 4: StatusSync (Buso/Ken Haki + Auto Stats +10)
-- ============================================================================
local StatusSync = {
	Config = {
		AuraInterval = 2.5,
		AllocateInterval = 0.45,
		AmountPerCall = 10,
		PointKeyPatterns = { "availablepoint", "skillpoint", "statpoint", "point" },
	},
	Active = true,
	InvokingStat = false,
	InvokingKen = false,
	LastEventInfo = "Stats ready",
}

function StatusSync.GetAvailablePoints(player)
	for attrName, val in pairs(player:GetAttributes()) do
		if type(val) == "number" and val > 0 and string.find(string.lower(attrName), "point", 1, true) then
			return val, attrName
		end
	end
	for _, desc in ipairs(player:GetDescendants()) do
		if (desc:IsA("IntValue") or desc:IsA("NumberValue")) and desc.Value > 0 then
			local low = string.lower(desc.Name)
			for _, pat in ipairs(StatusSync.Config.PointKeyPatterns) do
				if string.find(low, pat, 1, true) then
					return desc.Value, desc.Name
				end
			end
		end
	end
	return 0, nil
end

function StatusSync.GetStatsRemote(player)
	local pGui = player:FindFirstChild("PlayerGui")
	local mainGui = pGui and pGui:FindFirstChild("MainGui")
	local starterFrame = mainGui and mainGui:FindFirstChild("StarterFrame")
	local statsFrame = starterFrame and starterFrame:FindFirstChild("StatsFrame")
	local remoteEvent = statsFrame and statsFrame:FindFirstChild("RemoteEvent")
	if remoteEvent and remoteEvent:IsA("RemoteEvent") then
		return remoteEvent
	end
	return nil
end

function StatusSync.StartLoops(player, config)
	StatusSync.Active = true

	task.spawn(function()
		while StatusSync.Active do
			task.wait(StatusSync.Config.AuraInterval)
			if not StatusSync.Active then
				break
			end
			local char = player.Character
			if char then
				if config.AutoAuraA then
					local hasBuso = char:GetAttribute("Armament") or char:GetAttribute("Buso") or char:FindFirstChild("Buso")
					if not hasBuso then
						local armEv = RemoteResolver.Get("Chest.Remotes.Events.Armament")
						if armEv and armEv:IsA("RemoteEvent") then
							pcall(armEv.FireServer, armEv, true)
						end
					end
				end

				if config.AutoAuraB and not StatusSync.InvokingKen then
					local hasKen = char:GetAttribute("Ken") or char:GetAttribute("Observation") or char:FindFirstChild("Ken")
					if not hasKen then
						local kenFn = RemoteResolver.Get("Chest.Remotes.Functions.KenEvent")
						if kenFn and kenFn:IsA("RemoteFunction") then
							StatusSync.InvokingKen = true
							task.spawn(function()
								pcall(kenFn.InvokeServer, kenFn, true)
								StatusSync.InvokingKen = false
							end)
						end
					end
				end
			end
		end
	end)

	task.spawn(function()
		while StatusSync.Active do
			task.wait(StatusSync.Config.AllocateInterval)
			if not StatusSync.Active then
				break
			end
			if config.AutoAllocate and config.SelectedStat and not StatusSync.InvokingStat then
				local pts, keyName = StatusSync.GetAvailablePoints(player)
				if pts <= 0 then
					StatusSync.LastEventInfo = "Stats no points"
				else
					local amt = math.min(pts, StatusSync.Config.AmountPerCall)
					local statsEv = StatusSync.GetStatsRemote(player)
					if statsEv then
						pcall(statsEv.FireServer, statsEv, config.SelectedStat, amt)
						StatusSync.LastEventInfo = string.format("+%d %s [%s]", amt, config.SelectedStat, tostring(keyName))
					else
						local upgradeFn = RemoteResolver.Get("Chest.Remotes.Functions.Upgrade")
						if upgradeFn and upgradeFn:IsA("RemoteFunction") then
							StatusSync.InvokingStat = true
							task.spawn(function()
								pcall(upgradeFn.InvokeServer, upgradeFn, config.SelectedStat, amt)
								StatusSync.LastEventInfo = string.format("+%d %s (Fn)", amt, config.SelectedStat)
								StatusSync.InvokingStat = false
							end)
						end
					end
				end
			end
		end
	end)
end

-- ============================================================================
-- MODULE 5: TeleportManager
-- ============================================================================
local TeleportManager = {
	Config = {
		Speed = 340,
		LongRangeSpeed = 600,
		LongRangeThreshold = 80,
		ArrivalThreshold = 6,
	},
	State = {
		Active = false,
		Destination = nil,
		Label = "Idle",
		IsResume = false,
	},
}

function TeleportManager.ToCFrame(cf, label, isResume)
	if TeleportManager.State.Active and TeleportManager.State.Destination == cf then
		return
	end
	local prep = RemoteResolver.Get("Chest.Remotes.TeleportPrepare")
	if prep then
		if prep:IsA("RemoteEvent") then
			pcall(prep.FireServer, prep, cf.Position)
		elseif prep:IsA("RemoteFunction") then
			task.spawn(pcall, prep.InvokeServer, prep, cf.Position)
		end
	end
	TeleportManager.State.Destination = cf
	TeleportManager.State.Active = true
	TeleportManager.State.Label = label or "Target"
	TeleportManager.State.IsResume = isResume == true
end

function TeleportManager.Cancel()
	TeleportManager.State.Active = false
	TeleportManager.State.Destination = nil
	TeleportManager.State.Label = "Idle"
	TeleportManager.State.IsResume = false
end

function TeleportManager.Update(dt, root)
	local state = TeleportManager.State
	if not state.Active or not state.Destination or not root then
		return false
	end

	local targetPos = state.Destination.Position
	local delta = targetPos - root.Position
	local dist = delta.Magnitude

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	if dist <= TeleportManager.Config.ArrivalThreshold then
		root.CFrame = state.Destination
		state.Active = false
		state.Destination = nil
		state.Label = "Arrived"
		state.IsResume = false
		return false
	end

	local activeSpeed = (dist > TeleportManager.Config.LongRangeThreshold)
		and TeleportManager.Config.LongRangeSpeed
		or TeleportManager.Config.Speed
	local step = math.min(dist, activeSpeed * math.min(dt, 0.1))
	local nextPos = root.Position + delta.Unit * step
	root.CFrame = CFrame.new(nextPos) * state.Destination.Rotation
	return true
end

-- ============================================================================
-- MODULE 6: QuestManager
-- ============================================================================
local QuestManager = {
	State = {
		Loaded = false,
		Records = {},
		LastLoad = 0,
		Stage = "Idle",
		CurrentQuest = nil,
		TargetMobName = nil,
		NextTakeAt = 0,
		Taking = false,
		RemoteFails = {},
		Blacklist = {},
		SelectedNpcIndex = 1,
		CachedNpcs = {},
		LastNpcScan = 0,
	},
}

function QuestManager.GetPlayerLevel(player)
	for attr, val in pairs(player:GetAttributes()) do
		local low = string.lower(attr)
		if (low == "level" or low == "lvl") and type(val) == "number" then
			return val
		end
	end
	for _, desc in ipairs(player:GetDescendants()) do
		if desc:IsA("ValueBase") then
			local low = string.lower(desc.Name)
			if low == "level" or low == "lvl" then
				local num = tonumber(desc.Value)
				if num then
					return num
				end
			end
		end
	end
	return 1
end

local function isNonMobQuest(questName, mobName)
	local qLow = string.lower(tostring(questName or ""))
	local mLow = string.lower(tostring(mobName or ""))
	if qLow == "" or mLow == "" then
		return true
	end
	if string.find(qLow, "find ", 1, true)
		or string.find(qLow, "deliver", 1, true)
		or string.find(qLow, "collect", 1, true)
		or string.find(qLow, "daily", 1, true)
	then
		return true
	end
	return false
end

function QuestManager.LoadFromModule()
	local now = os.clock()
	if QuestManager.State.Loaded and (now - QuestManager.State.LastLoad) < 60 then
		return QuestManager.State.Records
	end
	QuestManager.State.LastLoad = now

	local modInst = RemoteResolver.Get("Chest.Modules.QuestManager")
	if not modInst or not modInst:IsA("ModuleScript") then
		return QuestManager.State.Records
	end

	local ok, data = pcall(require, modInst)
	if not ok or type(data) ~= "table" then
		return QuestManager.State.Records
	end

	local parsed = {}
	for key, entry in pairs(data) do
		if type(entry) == "table" then
			local qName = (type(entry.Name) == "string" and entry.Name) or (type(key) == "string" and key) or nil
			local mobName = type(entry.Mob) == "string" and entry.Mob or nil
			local reqLvl = tonumber(entry.Level)
			local isDaily = entry.DailyQuest == true
			local isOneTime = entry.OneTimeQuest == true
			local isSpecial = entry.SpecialQuest == true

			if qName and mobName and reqLvl and not isDaily and not isOneTime and not isSpecial and not isNonMobQuest(qName, mobName) then
				table.insert(parsed, {
					QuestName = qName,
					MobName = mobName,
					Level = reqLvl,
					Amount = tonumber(entry.Ammount) or 1,
				})
			end
		end
	end

	table.sort(parsed, function(a, b)
		if a.Level == b.Level then
			return a.QuestName < b.QuestName
		end
		return a.Level < b.Level
	end)

	QuestManager.State.Records = parsed
	QuestManager.State.Loaded = true
	return parsed
end

function QuestManager.SelectBestQuest(playerLevel)
	local records = QuestManager.LoadFromModule()
	local now = os.clock()
	local best = nil
	for _, rec in ipairs(records) do
		if rec.Level <= playerLevel then
			local blockedUntil = QuestManager.State.Blacklist[rec.QuestName]
			if not blockedUntil or now >= blockedUntil then
				best = rec
			end
		else
			break
		end
	end
	return best
end

function QuestManager.ScanNpcs()
	local now = os.clock()
	if #QuestManager.State.CachedNpcs > 0 and (now - QuestManager.State.LastNpcScan) < 25 then
		return QuestManager.State.CachedNpcs
	end
	QuestManager.State.LastNpcScan = now

	local list = {}
	local allNpc = workspace:FindFirstChild("AllNPC")
	local searchRoot = allNpc or workspace
	for _, obj in ipairs(searchRoot:GetDescendants()) do
		if obj:IsA("Model") then
			local low = string.lower(obj.Name)
			local isIgnored = string.find(low, "daily", 1, true) ~= nil or string.find(low, "find", 1, true) ~= nil
			local isQuest = (not isIgnored) and (string.find(low, "quest", 1, true) ~= nil)
			if isQuest then
				local rootPart = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")
				if rootPart then
					local lvlMin = tonumber(obj:GetAttribute("LevelMin")) or tonumber(obj:GetAttribute("Level")) or tonumber(string.match(obj.Name, "(%d+)")) or 0
					local lvlMax = tonumber(obj:GetAttribute("LevelMax")) or 99999
					table.insert(list, {
						Model = obj,
						Name = obj.Name,
						Root = rootPart,
						Level = lvlMin,
						LevelMax = lvlMax,
					})
				end
			end
		end
	end

	table.sort(list, function(a, b)
		return a.Level < b.Level
	end)
	QuestManager.State.CachedNpcs = list
	return list
end

function QuestManager.DismissNpcDialogue(player)
	local pGui = player:FindFirstChild("PlayerGui")
	if not pGui then
		return
	end
	for _, gui in ipairs(pGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Name ~= "NavControllerGui" then
			local lowName = string.lower(gui.Name)
			if string.find(lowName, "dialogue", 1, true) or string.find(lowName, "npc", 1, true) then
				if gui.Enabled then
					gui.Enabled = false
				end
			end
			for _, desc in ipairs(gui:GetDescendants()) do
				if desc:IsA("GuiObject") and desc.Name ~= "QuestFrame" and desc.Name ~= "QuestBoard" then
					local dLow = string.lower(desc.Name)
					if (string.find(dLow, "dialogue", 1, true) or string.find(dLow, "dialog", 1, true) or string.find(dLow, "questgiver", 1, true)) and desc.Visible then
						desc.Visible = false
					end
				end
			end
		end
	end
end

function QuestManager.HasActiveQuestGui(player)
	local pGui = player:FindFirstChild("PlayerGui")
	local mainGui = pGui and pGui:FindFirstChild("MainGui")
	local questFrame = mainGui and mainGui:FindFirstChild("QuestFrame")
	if not questFrame or not questFrame:IsA("GuiObject") then
		return false, nil
	end

	local board = questFrame:FindFirstChild("QuestBoard", true)
	local textFrame = board and board:FindFirstChild("TextFrame")
	local qNameLbl = textFrame and textFrame:FindFirstChild("QuestName")
	local qCountLbl = textFrame and textFrame:FindFirstChild("QuestCount")

	local visible = questFrame.Visible and (board == nil or board.Visible)
	if not visible then
		return false, nil
	end

	local nameText = (qNameLbl and qNameLbl:IsA("TextLabel") and qNameLbl.Text) or ""
	local countText = (qCountLbl and qCountLbl:IsA("TextLabel") and qCountLbl.Text) or ""

	if nameText == "" or nameText == "????" or string.find(countText, "?", 1, true) then
		return false, nil
	end

	local curNum, maxNum = string.match(countText, "(%d+)%s*/%s*(%d+)")
	if curNum and maxNum and tonumber(curNum) >= tonumber(maxNum) then
		return false, nil
	end

	return true, nameText
end

function QuestManager.MatchQuestFromBoardText(boardText, playerLevel)
	local cleanBoard = string.lower(string.gsub(tostring(boardText or ""), "%s*%[.-%]", ""))
	cleanBoard = string.gsub(cleanBoard, "^%s*(.-)%s*$", "%1")
	if cleanBoard ~= "" then
		for _, rec in ipairs(QuestManager.LoadFromModule()) do
			local cleanMob = string.lower(string.gsub(rec.MobName, "%s*%[.-%]", ""))
			cleanMob = string.gsub(cleanMob, "^%s*(.-)%s*$", "%1")
			if cleanMob == cleanBoard then
				return rec
			end
		end
	end
	return QuestManager.SelectBestQuest(playerLevel)
end

function QuestManager.TriggerTakeAsync(player, candidate)
	if QuestManager.State.Taking then
		return
	end
	local now = os.clock()
	if now < QuestManager.State.NextTakeAt then
		return
	end
	QuestManager.State.NextTakeAt = now + 0.4
	QuestManager.State.Taking = true
	QuestManager.State.Stage = "RemoteTakeQuest"

	task.spawn(function()
		local qRemote = RemoteResolver.Get("Chest.Remotes.Functions.Quest")
		if qRemote and qRemote:IsA("RemoteFunction") then
			pcall(qRemote.InvokeServer, qRemote, "take", candidate.QuestName)
		end

		task.wait(0.15)
		QuestManager.DismissNpcDialogue(player)
		local active = QuestManager.HasActiveQuestGui(player)
		if active then
			QuestManager.State.CurrentQuest = candidate
			QuestManager.State.TargetMobName = candidate.MobName
			QuestManager.State.RemoteFails[candidate.QuestName] = 0
			QuestManager.State.Stage = "QuestReady"
		else
			local fails = (QuestManager.State.RemoteFails[candidate.QuestName] or 0) + 1
			QuestManager.State.RemoteFails[candidate.QuestName] = fails
			if fails >= 2 then
				QuestManager.State.Blacklist[candidate.QuestName] = os.clock() + 15
				QuestManager.State.RemoteFails[candidate.QuestName] = 0
			end
			QuestManager.State.Stage = "RetryTake"
		end
		QuestManager.State.Taking = false
	end)
end

function QuestManager.Step(player, root)
	local state = QuestManager.State
	local level = QuestManager.GetPlayerLevel(player)

	QuestManager.DismissNpcDialogue(player)

	local hasActive, activeBoardText = QuestManager.HasActiveQuestGui(player)
	if hasActive then
		if TeleportManager.State.Active and not TeleportManager.State.IsResume then
			TeleportManager.Cancel()
		end
		if not state.CurrentQuest then
			state.CurrentQuest = QuestManager.MatchQuestFromBoardText(activeBoardText, level)
		end
		state.TargetMobName = (state.CurrentQuest and state.CurrentQuest.MobName) or activeBoardText
		return false, state.TargetMobName
	else
		state.CurrentQuest = nil
		state.TargetMobName = nil
	end

	local candidate = QuestManager.SelectBestQuest(level)
	if not candidate then
		table.clear(state.Blacklist)
		candidate = QuestManager.SelectBestQuest(level)
	end
	if not candidate then
		state.Stage = "Free farm (no quest)"
		return false, nil
	end

	QuestManager.TriggerTakeAsync(player, candidate)
	return false, candidate.MobName
end

-- ============================================================================
-- MODULE 7: NavController
-- ============================================================================
local NavController = {
	Config = {
		Enabled = false,
		AutoQuestFarm = false,
		MobHopping = true,
		HopInterval = 0.55,
		AutoAttack = false,
		FastAttack = true,
		CycleAbilities = false,
		ExpandHitbox = true,
		HitboxSize = 26,
		AutoAuraA = false,
		AutoAuraB = false,
		AutoAllocate = false,
		SelectedStat = "Melee",
		HeightOffset = 8.5,
		SafeHoverOffset = 22,
		HopRadius = 180,
		SmoothAlpha = 0.45,
		AttackRange = 32,
		WorkspaceFolderName = "Monster.Mon",
		WorkspaceFolder = nil,
		StatusInterval = 0.15,
	},
	State = {
		Connections = {},
		Gui = nil,
		Panel = nil,
		Content = nil,
		StatusLabel = nil,
		Target = nil,
		HopIndex = 1,
		HopTimer = 0,
		CandidateCount = 0,
		Distance = 0,
		StatusTimer = 0,
		LastMobPos = nil,
		LastFarmCFrame = nil,
		LastFarmLabel = "Last Spot",
		CollisionCache = setmetatable({}, { __mode = "k" }),
		Stopped = false,
		RefreshFns = {},
	},
	StatOptions = { "Melee", "Defense", "Sword", "Fruit" },
	SlotOptions = { 0, 1, 2, 3 },
	SlotLabels = {
		[0] = "Tự do (Đang cầm)",
		[1] = "Ô số 1",
		[2] = "Ô số 2 (Võ)",
		[3] = "Ô số 3 (Kiếm)",
	},
	UI = {},
}

NavController.LocalPlayer = Players.LocalPlayer

function NavController:Connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(self.State.Connections, connection)
	return connection
end

function NavController:ResolveFolder(path)
	local current = workspace
	for segment in string.gmatch(path, "[^%.]+") do
		if segment ~= "workspace" and segment ~= "Workspace" then
			current = current and current:FindFirstChild(segment)
		end
		if not current then
			return nil
		end
	end
	return current
end

function NavController:GetDefaultFolder()
	local mon = self:ResolveFolder("Monster.Mon")
	if mon then
		self.Config.WorkspaceFolderName = "Monster.Mon"
		return mon
	end
	local monster = self:ResolveFolder("Monster")
	if monster then
		self.Config.WorkspaceFolderName = "Monster"
		return monster
	end
	return self:ResolveFolder(self.Config.WorkspaceFolderName)
end

function NavController:GetCharacterRoot()
	local character = self.LocalPlayer.Character
	if not character then
		return nil, nil
	end
	return character, character:FindFirstChild("HumanoidRootPart")
end

function NavController:IsValidNpc(model)
	if not model or not model:IsA("Model") or model == self.LocalPlayer.Character then
		return false
	end
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return false
	end
	return humanoid.Health > 0
end

local function stripLevelTag(name)
	return string.gsub(string.gsub(tostring(name or ""), "%s*%[.-%]", ""), "^%s*(.-)%s*$", "%1")
end

local function extractLevelTag(name)
	local num = string.match(tostring(name or ""), "%[%D*(%d+)%D*%]")
	return tonumber(num)
end

function NavController:GetMatchingMobs(mobName)
	local folder = self.Config.WorkspaceFolder
	if not folder or not folder.Parent then
		folder = self:GetDefaultFolder()
		self.Config.WorkspaceFolder = folder
	end
	local _, root = self:GetCharacterRoot()
	if not root then
		return {}
	end

	local cleanTarget = string.lower(stripLevelTag(mobName))
	local exactLower = string.lower(tostring(mobName or ""))
	local playerLvl = QuestManager.GetPlayerLevel(self.LocalPlayer)
	local maxAllowedLvl = playerLvl + 60
	local exactList = {}

	local function scanModels(models)
		for _, model in ipairs(models) do
			if self:IsValidNpc(model) then
				local mLow = string.lower(model.Name)
				local mClean = string.lower(stripLevelTag(model.Name))
				local mobLvl = extractLevelTag(model.Name) or tonumber(model:GetAttribute("Level"))

				local levelOk = (not self.Config.AutoQuestFarm) or (mobLvl == nil) or (mobLvl <= maxAllowedLvl)

				if levelOk then
					local isExact = (exactLower ~= "" and mLow == exactLower)
						or (cleanTarget ~= "" and mClean == cleanTarget)
						or (exactLower == "" and cleanTarget == "")

					if isExact then
						local dist = (model.HumanoidRootPart.Position - root.Position).Magnitude
						table.insert(exactList, { Model = model, Dist = dist })
					end
				end
			end
		end
	end

	if folder and folder.Parent then
		scanModels(folder:GetChildren())
	end

	if #exactList == 0 and cleanTarget ~= "" then
		local monsterRoot = workspace:FindFirstChild("Monster")
		if monsterRoot then
			scanModels(monsterRoot:GetDescendants())
		end
	end

	table.sort(exactList, function(a, b)
		if math.abs(a.Dist - b.Dist) < 2 then
			return a.Model:GetDebugId() < b.Model:GetDebugId()
		end
		return a.Dist < b.Dist
	end)

	return exactList
end

function NavController:SelectHopTarget(mobName, advanceHop)
	local list = self:GetMatchingMobs(mobName)
	self.State.CandidateCount = #list
	if #list == 0 then
		return nil, 0, list
	end

	if not self.Config.MobHopping or #list == 1 then
		self.State.HopIndex = 1
		return list[1].Model, list[1].Dist, list
	end

	local anchorPos = list[1].Model.HumanoidRootPart.Position
	local localGroup = {}
	for _, entry in ipairs(list) do
		if (entry.Model.HumanoidRootPart.Position - anchorPos).Magnitude <= self.Config.HopRadius then
			table.insert(localGroup, entry)
		end
	end
	if #localGroup == 0 then
		localGroup = list
	end

	if advanceHop then
		self.State.HopIndex = (self.State.HopIndex % #localGroup) + 1
	elseif self.State.HopIndex > #localGroup then
		self.State.HopIndex = 1
	end

	local chosen = localGroup[self.State.HopIndex]
	return chosen.Model, chosen.Dist, list
end

function NavController:RestoreCollisions()
	for part, original in pairs(self.State.CollisionCache) do
		if part and part.Parent then
			part.CanCollide = original
		end
		self.State.CollisionCache[part] = nil
	end
end

function NavController:SetAutoQuestFarm(value)
	self.Config.AutoQuestFarm = value
	if value then
		self.Config.Enabled = true
		self.Config.AutoAttack = true
		self.Config.MobHopping = true
		table.clear(QuestManager.State.Blacklist)
		table.clear(QuestManager.State.RemoteFails)
		QuestManager.State.NextTakeAt = 0
		QuestManager.LoadFromModule()
		if self.State.RefreshFns.Enabled then
			self.State.RefreshFns.Enabled()
		end
		if self.State.RefreshFns.AutoAttack then
			self.State.RefreshFns.AutoAttack()
		end
		if self.State.RefreshFns.MobHopping then
			self.State.RefreshFns.MobHopping()
		end
	else
		QuestManager.State.Stage = "Idle"
		self.State.LastMobPos = nil
		self.State.LastFarmCFrame = nil
		HitboxExpander.RestoreAll()
		TeleportManager.Cancel()
	end
end

function NavController:SetEnabled(value)
	self.Config.Enabled = value
	if value then
		self.Config.AutoAttack = true
		if self.State.RefreshFns.AutoAttack then
			self.State.RefreshFns.AutoAttack()
		end
	else
		TeleportManager.Cancel()
		HitboxExpander.RestoreAll()
		self:RestoreCollisions()
		self.State.Target = nil
		self.State.Distance = 0
		self.State.LastMobPos = nil
		self.State.LastFarmCFrame = nil
	end
end

function NavController:UpdateStatus()
	local label = self.State.StatusLabel
	if not label then
		return
	end
	local state = self.State
	local act = ActionDispatcher.State
	local targetName = state.Target and state.Target.Name or "none"
	local stageText = TeleportManager.State.Active and ("TP -> " .. TeleportManager.State.Label) or QuestManager.State.Stage
	local qName = QuestManager.State.TargetMobName or (QuestManager.State.CurrentQuest and QuestManager.State.CurrentQuest.QuestName) or "-"
	label.Text = string.format(
		"Stage: %s | Target: %s (%.1f)\nWant: %s | Mobs: %d (#%d)\nAct: %s | Calls: %d | Err: %d",
		stageText,
		targetName,
		state.Distance,
		qName,
		state.CandidateCount,
		state.HopIndex,
		act.LastAction,
		act.TotalCalls,
		act.TotalErrors
	)
end

function NavController.UI.New(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function NavController.UI.Button(text, size, color, parent)
	local button = NavController.UI.New("TextButton", {
		Size = size,
		BackgroundColor3 = color or Color3.fromRGB(45, 45, 55),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Color3.fromRGB(235, 235, 240),
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		AutoButtonColor = true,
	}, parent)
	NavController.UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
	return button
end

function NavController:MountGui(gui)
	local mounted = false
	if type(gethui) == "function" then
		local ok, container = pcall(gethui)
		if ok and typeof(container) == "Instance" then
			local parentOk = pcall(function()
				gui.Parent = container
			end)
			mounted = parentOk and gui.Parent == container
		end
	end
	if not mounted then
		local ok = pcall(function()
			gui.Parent = CoreGui
		end)
		mounted = ok and gui.Parent == CoreGui
	end
	if not mounted then
		gui.Parent = self.LocalPlayer:WaitForChild("PlayerGui")
	end
end

function NavController:MakeDraggable(handle, panel)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
	self:Connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
			local endedConn
			endedConn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if endedConn then
						endedConn:Disconnect()
					end
				end
			end)
		end
	end)
	self:Connect(handle.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	self:Connect(UserInputService.InputChanged, function(input)
		if dragging and input == dragInput and dragStart then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)
end

function NavController:AddToggle(parent, text, order, id, getter, setter)
	local button = self.UI.Button(text, UDim2.new(1, 0, 0, 34), nil, parent)
	button.LayoutOrder = order
	local function refresh()
		local on = getter()
		button.Text = text .. ": " .. (on and "ON" or "OFF")
		button.BackgroundColor3 = on and Color3.fromRGB(40, 120, 70) or Color3.fromRGB(45, 45, 55)
	end
	if id then
		self.State.RefreshFns[id] = refresh
	end
	self:Connect(button.Activated, function()
		setter(not getter())
		refresh()
	end)
	refresh()
	return button
end

function NavController:AddStepper(parent, text, order, key, step, minValue, maxValue, decimals, targetTable)
	local row = self.UI.New("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Color3.fromRGB(32, 32, 40),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	self.UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, row)

	self.UI.New("TextLabel", {
		Size = UDim2.new(0.45, 0, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(200, 200, 210),
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local minus = self.UI.Button("-", UDim2.fromOffset(34, 28), nil, row)
	minus.AnchorPoint = Vector2.new(1, 0.5)
	minus.Position = UDim2.new(1, -96, 0.5, 0)

	local valueLabel = self.UI.New("TextLabel", {
		Size = UDim2.fromOffset(50, 28),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -44, 0.5, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 13,
		Font = Enum.Font.GothamBold,
	}, row)

	local plus = self.UI.Button("+", UDim2.fromOffset(34, 28), nil, row)
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.new(1, -6, 0.5, 0)

	local tbl = targetTable or self.Config
	local function refresh()
		valueLabel.Text = string.format("%." .. decimals .. "f", tbl[key])
	end
	local function adjust(direction)
		local factor = 10 ^ decimals
		local value = math.clamp(tbl[key] + step * direction, minValue, maxValue)
		tbl[key] = math.floor(value * factor + 0.5) / factor
		refresh()
	end

	self:Connect(minus.Activated, function() adjust(-1) end)
	self:Connect(plus.Activated, function() adjust(1) end)
	refresh()
	return row
end

function NavController:BuildUI()
	local state = self.State
	local gui = self.UI.New("ScreenGui", {
		Name = "NavControllerGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	state.Gui = gui

	local miniBtn = self.UI.Button("KL", UDim2.fromOffset(44, 44), Color3.fromRGB(25, 25, 32), gui)
	miniBtn.Position = UDim2.fromOffset(14, 140)
	miniBtn.TextColor3 = Color3.fromRGB(235, 180, 50)
	miniBtn.Font = Enum.Font.GothamBold
	miniBtn.Visible = false
	self.UI.New("UIStroke", { Color = Color3.fromRGB(235, 180, 50), Thickness = 1.5 }, miniBtn)

	local panel = self.UI.New("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(315, 440),
		Position = UDim2.fromOffset(20, 75),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, gui)
	self.UI.New("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	self.UI.New("UIStroke", { Color = Color3.fromRGB(60, 60, 75), Thickness = 1 }, panel)
	state.Panel = panel

	local titleBar = self.UI.New("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color3.fromRGB(14, 14, 18),
		BorderSizePixel = 0,
	}, panel)

	self.UI.New("TextLabel", {
		Size = UDim2.new(1, -85, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = "ZAIBEOCUTO x TRAIANIMEIRL",
		TextColor3 = Color3.fromRGB(235, 180, 50),
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBar)

	local minBtn = self.UI.Button("-", UDim2.fromOffset(30, 26), Color3.fromRGB(60, 60, 75), titleBar)
	minBtn.AnchorPoint = Vector2.new(1, 0.5)
	minBtn.Position = UDim2.new(1, -40, 0.5, 0)

	local closeBtn = self.UI.Button("X", UDim2.fromOffset(30, 26), Color3.fromRGB(150, 45, 45), titleBar)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -6, 0.5, 0)

	state.StatusLabel = self.UI.New("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, -16, 0, 56),
		Position = UDim2.fromOffset(8, 40),
		BackgroundColor3 = Color3.fromRGB(12, 12, 16),
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Color3.fromRGB(150, 230, 170),
		TextSize = 11,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, panel)
	self.UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, state.StatusLabel)
	self.UI.New("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, state.StatusLabel)

	local content = self.UI.New("ScrollingFrame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 1, -100),
		Position = UDim2.fromOffset(0, 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	state.Content = content

	self.UI.New("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 10),
	}, content)
	self.UI.New("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, content)

	self:AddToggle(content, "AUTO QUEST + FARM", 1, "AutoQuestFarm",
		function() return self.Config.AutoQuestFarm end,
		function(v) self:SetAutoQuestFarm(v) end
	)
	self:AddToggle(content, "Auto Farm (Top Hover)", 2, "Enabled",
		function() return self.Config.Enabled end,
		function(v) self:SetEnabled(v) end
	)
	self:AddToggle(content, "Fast Attack (Siêu tốc M1)", 3, "FastAttack",
		function() return self.Config.FastAttack end,
		function(v) self.Config.FastAttack = v end
	)
	self:AddToggle(content, "Mở Rộng Hitbox Quái", 4, "ExpandHitbox",
		function() return self.Config.ExpandHitbox end,
		function(v)
			self.Config.ExpandHitbox = v
			if not v then
				HitboxExpander.RestoreAll()
			end
		end
	)
	self:AddToggle(content, "Đảo Quái Kéo Aggro", 5, "MobHopping",
		function() return self.Config.MobHopping end,
		function(v) self.Config.MobHopping = v end
	)
	self:AddToggle(content, "Auto Attack (M1)", 6, "AutoAttack",
		function() return self.Config.AutoAttack end,
		function(v) self.Config.AutoAttack = v end
	)
	self:AddToggle(content, "Auto Skill (Z/X/C/V)", 7, "CycleAbilities",
		function() return self.Config.CycleAbilities end,
		function(v) self.Config.CycleAbilities = v end
	)

	local slotBtn = self.UI.Button("Trang bị: " .. self.SlotLabels[ActionDispatcher.Config.SlotMode], UDim2.new(1, 0, 0, 34), Color3.fromRGB(55, 65, 95), content)
	slotBtn.LayoutOrder = 8
	self:Connect(slotBtn.Activated, function()
		local idx = table.find(self.SlotOptions, ActionDispatcher.Config.SlotMode) or 1
		local nextSlot = self.SlotOptions[(idx % #self.SlotOptions) + 1]
		ActionDispatcher.Config.SlotMode = nextSlot
		slotBtn.Text = "Trang bị: " .. self.SlotLabels[nextSlot]
	end)

	local npcSelectBtn = self.UI.Button("Chọn NPC Quest: [Bấm để quét]", UDim2.new(1, 0, 0, 34), Color3.fromRGB(40, 50, 70), content)
	npcSelectBtn.LayoutOrder = 9
	self:Connect(npcSelectBtn.Activated, function()
		QuestManager.State.LastNpcScan = 0
		local list = QuestManager.ScanNpcs()
		if #list == 0 then
			npcSelectBtn.Text = "NPC missing"
			return
		end
		QuestManager.State.SelectedNpcIndex = (QuestManager.State.SelectedNpcIndex % #list) + 1
		local item = list[QuestManager.State.SelectedNpcIndex]
		npcSelectBtn.Text = string.format("NPC: %s (Lv.%d)", item.Name, item.Level)
	end)

	local tpNpcBtn = self.UI.Button("Teleport tới NPC Quest đã chọn", UDim2.new(1, 0, 0, 34), Color3.fromRGB(55, 85, 130), content)
	tpNpcBtn.LayoutOrder = 10
	self:Connect(tpNpcBtn.Activated, function()
		local list = QuestManager.ScanNpcs()
		local item = list[QuestManager.State.SelectedNpcIndex]
		if item and item.Root and item.Root.Parent then
			TeleportManager.ToCFrame(item.Root.CFrame * CFrame.new(0, 0, 3), item.Name, false)
		end
	end)

	local stopTpBtn = self.UI.Button("Dừng Teleport khẩn cấp", UDim2.new(1, 0, 0, 30), Color3.fromRGB(110, 45, 45), content)
	stopTpBtn.LayoutOrder = 11
	self:Connect(stopTpBtn.Activated, function()
		TeleportManager.Cancel()
	end)

	self:AddToggle(content, "Auto Buso Haki", 12, "AutoAuraA",
		function() return self.Config.AutoAuraA end,
		function(v) self.Config.AutoAuraA = v end
	)
	self:AddToggle(content, "Auto Ken Haki", 13, "AutoAuraB",
		function() return self.Config.AutoAuraB end,
		function(v) self.Config.AutoAuraB = v end
	)
	self:AddToggle(content, "Auto Stats +10", 14, "AutoAllocate",
		function() return self.Config.AutoAllocate end,
		function(v) self.Config.AutoAllocate = v end
	)

	local statBtn = self.UI.Button("Chỉ số cộng: " .. self.Config.SelectedStat, UDim2.new(1, 0, 0, 34), nil, content)
	statBtn.LayoutOrder = 15
	self:Connect(statBtn.Activated, function()
		local idx = table.find(self.StatOptions, self.Config.SelectedStat) or 1
		self.Config.SelectedStat = self.StatOptions[(idx % #self.StatOptions) + 1]
		statBtn.Text = "Chỉ số cộng: " .. self.Config.SelectedStat
	end)

	self:AddStepper(content, "Tốc độ Fast M1 (s)", 16, "FastCooldown", 0.01, 0.04, 0.25, 2, ActionDispatcher.Config)
	self:AddStepper(content, "Kích thước Hitbox", 17, "HitboxSize", 2, 10, 50, 0)
	self:AddStepper(content, "Nhịp đảo quái (s)", 18, "HopInterval", 0.1, 0.2, 2.0, 2)
	self:AddStepper(content, "Độ cao đánh", 19, "HeightOffset", 0.5, 1, 50, 1)
	self:AddStepper(content, "Độ cao chờ", 20, "SafeHoverOffset", 2, 10, 60, 0)
	self:AddStepper(content, "Độ mượt bay", 21, "SmoothAlpha", 0.05, 0.05, 1, 2)

	self:Connect(minBtn.Activated, function()
		panel.Visible = false
		miniBtn.Visible = true
	end)
	self:Connect(miniBtn.Activated, function()
		miniBtn.Visible = false
		panel.Visible = true
	end)
	self:Connect(closeBtn.Activated, function()
		self:Stop()
	end)

	self:MakeDraggable(titleBar, panel)
	self:MakeDraggable(miniBtn, miniBtn)
	self:MountGui(gui)
end

function NavController:OnHeartbeat(dt)
	local state = self.State
	local config = self.Config
	if state.Stopped then
		return
	end

	state.StatusTimer = state.StatusTimer + dt
	if state.StatusTimer >= config.StatusInterval then
		state.StatusTimer = 0
		self:UpdateStatus()
	end

	local character, root = self:GetCharacterRoot()
	if not character or not root then
		return
	end

	if TeleportManager.Update(dt, root) then
		return
	end

	local desiredMobName = nil
	if config.AutoQuestFarm then
		local blockCombat, mobName = QuestManager.Step(self.LocalPlayer, root)
		desiredMobName = mobName
		if blockCombat then
			return
		end
	end

	if not config.Enabled then
		if config.AutoAttack or config.CycleAbilities then
			ActionDispatcher.StepAction(self.LocalPlayer, character, root.Position, config.AutoAttack, config.CycleAbilities, config.FastAttack)
		end
		return
	end

	state.HopTimer = state.HopTimer + dt
	local shouldAdvance = config.MobHopping and (state.HopTimer >= config.HopInterval) and (state.Distance <= config.AttackRange)
	local allMatching = nil
	if shouldAdvance or not state.Target or not self:IsValidNpc(state.Target) then
		if shouldAdvance then
			state.HopTimer = 0
		end
		state.Target, state.Distance, allMatching = self:SelectHopTarget(desiredMobName, shouldAdvance)
	else
		allMatching = self:GetMatchingMobs(desiredMobName)
		state.CandidateCount = #allMatching
	end

	local target = state.Target
	if target and self:IsValidNpc(target) then
		QuestManager.State.Stage = config.MobHopping and "HopAttack" or "Attack"
		local targetRoot = target.HumanoidRootPart
		state.LastMobPos = targetRoot.Position

		if allMatching then
			HitboxExpander.Apply(allMatching, config.ExpandHitbox, config.HitboxSize)
		end

		local goal = CFrame.new(targetRoot.Position)
			* CFrame.new(0, config.HeightOffset, 0)
			* CFrame.Angles(math.rad(-90), 0, 0)

		state.LastFarmCFrame = goal
		state.LastFarmLabel = stripLevelTag(target.Name)

		local distToGoal = (goal.Position - root.Position).Magnitude
		if distToGoal > 35 then
			local flySpeed = (distToGoal > TeleportManager.Config.LongRangeThreshold)
				and TeleportManager.Config.LongRangeSpeed
				or TeleportManager.Config.Speed
			local step = math.min(distToGoal, flySpeed * math.min(dt, 0.1))
			root.CFrame = CFrame.new(root.Position + (goal.Position - root.Position).Unit * step) * goal.Rotation
		else
			local alpha = 1 - (1 - math.clamp(config.SmoothAlpha, 0.01, 1)) ^ (dt * 60)
			root.CFrame = root.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
		end

		state.Distance = (targetRoot.Position - root.Position).Magnitude

		if (config.AutoAttack or config.CycleAbilities) and state.Distance <= config.AttackRange then
			ActionDispatcher.StepAction(self.LocalPlayer, character, targetRoot.Position, config.AutoAttack, config.CycleAbilities, config.FastAttack)
		end
	else
		state.Distance = 0
		if config.AutoQuestFarm then
			QuestManager.State.Stage = "HoverWaitRespawn"
		end

		if state.LastMobPos then
			local safeGoal = CFrame.new(state.LastMobPos)
				* CFrame.new(0, config.SafeHoverOffset, 0)
				* CFrame.Angles(math.rad(-90), 0, 0)
			local distToSafe = (safeGoal.Position - root.Position).Magnitude
			if distToSafe > 35 then
				local step = math.min(distToSafe, TeleportManager.Config.Speed * math.min(dt, 0.1))
				root.CFrame = CFrame.new(root.Position + (safeGoal.Position - root.Position).Unit * step) * safeGoal.Rotation
			else
				local alpha = 1 - (1 - math.clamp(config.SmoothAlpha, 0.01, 1)) ^ (dt * 60)
				root.CFrame = root.CFrame:Lerp(safeGoal, math.clamp(alpha, 0, 1))
			end
		end
	end
end

function NavController:OnStepped()
	if self.State.Stopped or (not self.Config.Enabled and not TeleportManager.State.Active and not self.Config.AutoQuestFarm) then
		return
	end

	local character, root = self:GetCharacterRoot()
	if not character then
		return
	end

	local cache = self.State.CollisionCache
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if cache[descendant] == nil then
				cache[descendant] = descendant.CanCollide
			end
			descendant.CanCollide = false
		end
	end

	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function NavController:Stop()
	local state = self.State
	if state.Stopped then
		return
	end
	state.Stopped = true

	self.Config.Enabled = false
	self.Config.AutoQuestFarm = false
	self.Config.MobHopping = false
	self.Config.AutoAttack = false
	self.Config.FastAttack = false
	self.Config.ExpandHitbox = false
	self.Config.AutoAuraA = false
	self.Config.AutoAuraB = false
	self.Config.AutoAllocate = false

	ActionDispatcher.State.Destroyed = true
	StatusSync.Active = false
	TeleportManager.Cancel()
	HitboxExpander.RestoreAll()

	for _, connection in ipairs(state.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(state.Connections)

	self:RestoreCollisions()

	if state.Gui then
		pcall(function()
			state.Gui:Destroy()
		end)
		state.Gui = nil
	end

	if env.StopNavController == self.StopFn then
		env.StopNavController = nil
	end
end

function NavController:Start()
	self.StopFn = function()
		self:Stop()
	end
	env.StopNavController = self.StopFn

	self.Config.WorkspaceFolder = self:GetDefaultFolder()
	QuestManager.LoadFromModule()
	StatusSync.StartLoops(self.LocalPlayer, self.Config)
	self:BuildUI()

	self:Connect(RunService.Heartbeat, function(dt)
		self:OnHeartbeat(dt)
	end)
	self:Connect(RunService.Stepped, function()
		self:OnStepped()
	end)
	self:Connect(self.LocalPlayer.CharacterAdded, function(newChar)
		table.clear(self.State.CollisionCache)
		self.State.Target = nil

		if (self.Config.Enabled or self.Config.AutoQuestFarm) and self.State.LastFarmCFrame then
			task.spawn(function()
				local newRoot = newChar:WaitForChild("HumanoidRootPart", 5)
				if newRoot and not self.State.Stopped and (self.Config.Enabled or self.Config.AutoQuestFarm) and self.State.LastFarmCFrame then
					QuestManager.State.Stage = "ResumeFarm"
					TeleportManager.ToCFrame(self.State.LastFarmCFrame, self.State.LastFarmLabel, true)
				end
			end)
		end
	end)
	if self.State.Gui then
		self:Connect(self.State.Gui.Destroying, function()
			self:Stop()
		end)
	end

	self:UpdateStatus()
end

local ok, err = pcall(function()
	NavController:Start()
end)
if not ok then
	warn("[NavController] Boot error:", err)
end
