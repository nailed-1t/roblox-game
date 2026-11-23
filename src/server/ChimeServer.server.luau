-- "Chime of Conflict": a two-player match in the Looping Rooms map
-- (workspace.ChimeMap). See TabletShared.ChimeShared for the settings.
--
-- * Challenge someone from the tablet app; when they accept, each of you is
--   put in one of the two rooms at opposite ends of the map.
-- * Your tablet only has Snake and Minesweeper (and this app) during the
--   match. They pay coins (the Economy script sends them here instead of
--   points); coins only exist for this match.
-- * Spend coins on items (Death Token, Extra Energy) or on robots that go
--   after your opponent:
--     Glare  - leaves when a flashlight is shone on it; walks through doors
--     Brute  - stopped by a shut door (it bangs on it, then gives up)
--     Hollow - leaves if your mask is on when it reaches you
-- * Shutting your door (E or the door button) and using the flashlight cost energy.
-- * Get caught without a Death Token and you lose. 8 minutes without a
--   winner is a draw. Leaving or dying also loses.
--
-- Player attributes during a match (they replicate, so the tablet and the
-- on-screen controls read them): ChimeMatch, ChimeSide ("A"/"B"),
-- ChimeOpponent, ChimeCoins, ChimeEnergy, ChimeTokens, ChimeMask, ChimeFlash,
-- ChimeDoor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")

local Shared = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ChimeShared"))

local INVITE_SECONDS = 30
local CATCH_DELAY = 1.2 -- seconds between the jumpscare and being caught
local GLARE_WINDOW = 7 -- seconds Glare waits in your room before it catches you
local GLARE_LIGHT_NEEDED = 1 -- seconds of flashlight that send Glare away
local BRUTE_BANG_SECONDS = 6 -- how long Brute bangs on a shut door
local BRUTE_DRAIN = 4 -- energy per second Brute's banging costs you
local HOLLOW_WAIT = 3 -- seconds Hollow stares at you before deciding

local robotInfo = {}
for _, r in ipairs(Shared.ROBOTS) do
	robotInfo[r.id] = r
end
local itemInfo = {}
for _, it in ipairs(Shared.ITEMS) do
	itemInfo[it.id] = it
end

local remotes = ReplicatedStorage:FindFirstChild("ChimeRemotes") or Instance.new("Folder")
remotes.Name = "ChimeRemotes"
remotes.Parent = ReplicatedStorage
local event = remotes:FindFirstChild("Chime") or Instance.new("RemoteEvent")
event.Name = "Chime"
event.Parent = remotes

-- robots walk through the players' invisible doorway barrier (and each other)
pcall(function()
	PhysicsService:RegisterCollisionGroup("ChimeRobots")
	PhysicsService:RegisterCollisionGroup("ChimeBarrier")
end)
PhysicsService:CollisionGroupSetCollidable("ChimeRobots", "ChimeBarrier", false)
PhysicsService:CollisionGroupSetCollidable("ChimeRobots", "ChimeRobots", false)

local map = workspace:WaitForChild("ChimeMap")
map:WaitForChild("Plane.004")

local function send(player: Player, action: string, data: any)
	if typeof(player) == "Instance" and player.Parent then
		event:FireClient(player, action, data or {})
	end
end

local function nameOf(player: Player): string
	return player.DisplayName or player.Name
end

---------------------------------------------------------------- doors

local matchFolder = map:FindFirstChild("Match") or Instance.new("Folder")
matchFolder.Name = "Match"
matchFolder.Parent = map

local doors = {} -- [side] = { part, closedCF, openCF, closed }
local match = nil -- the match being played (only one: there is one map)

local function setDoor(side: string, closed: boolean, quiet: boolean?)
	local d = doors[side]
	if d.closed == closed then
		return
	end
	d.closed = closed
	local post = matchFolder:FindFirstChild("DoorButton" .. side)
	local button = post and post:FindFirstChild("Button") :: BasePart?
	if button then
		button.Color = if closed then Color3.fromRGB(220, 60, 60) else Color3.fromRGB(60, 200, 90)
	end
	TweenService:Create(d.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = if closed then d.closedCF else d.openCF }):Play()
	if not quiet then
		d.sound:Play()
	end
	if match and match.players[side] then
		match.players[side]:SetAttribute("ChimeDoor", closed)
	end
end

local onDoorClicked -- set below

for _, side in ipairs({ "A", "B" }) do
	local cf, size = Shared.door(side)
	for _, old in ipairs(matchFolder:GetChildren()) do
		if old.Name == "Door" .. side or old.Name == "Barrier" .. side then
			old:Destroy()
		end
	end
	local door = Instance.new("Part")
	door.Name = "Door" .. side
	door.Anchored = true
	door.CanCollide = false -- it stops robots by rule, not by physics
	door.Material = Enum.Material.DiamondPlate
	door.Color = Color3.fromRGB(70, 72, 80)
	door.Size = size
	local openCF = cf + Vector3.new(0, size.Y * 0.92, 0)
	door.CFrame = openCF
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = door
	local sound = Instance.new("Sound")
	sound.SoundId = Shared.SOUNDS.door
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 120
	sound.Parent = door
	door.Parent = matchFolder
	doors[side] = { part = door, closedCF = cf, openCF = openCF, closed = false, sound = sound }
	click.MouseClick:Connect(function(player)
		onDoorClicked(player, side)
	end)
	-- once open the shutter hides in the wall above the doorway, so each room
	-- also gets a door button (and players can press E)
	for _, old in ipairs(matchFolder:GetChildren()) do
		if old.Name == "DoorButton" .. side then
			old:Destroy()
		end
	end
	local d = Shared.sign(side)
	local s = Shared.scale()
	local buttonPos = Shared.at(d * 28.6, 2.3, 0)
	local post = Instance.new("Part")
	post.Name = "DoorButton" .. side
	post.Anchored = true
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(60, 60, 66)
	post.Size = Vector3.new(0.5, 1.15 * s, 0.5)
	post.CFrame = CFrame.new(buttonPos + Vector3.new(0, post.Size.Y / 2, 0))
	local button = Instance.new("Part")
	button.Name = "Button"
	button.Anchored = true
	button.Material = Enum.Material.Neon
	button.Color = Color3.fromRGB(60, 200, 90)
	button.Size = Vector3.new(1.4, 1.4, 1.4)
	button.CFrame = CFrame.new(buttonPos + Vector3.new(0, post.Size.Y + 0.6, 0))
	button.Parent = post
	local buttonClick = Instance.new("ClickDetector")
	buttonClick.MaxActivationDistance = 40
	buttonClick.Parent = button
	buttonClick.MouseClick:Connect(function(player)
		onDoorClicked(player, side)
	end)
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(110, 22)
	label.StudsOffset = Vector3.new(0, 1.5, 0)
	label.MaxDistance = 40
	label.LightInfluence = 0
	local labelText = Instance.new("TextLabel")
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.fromScale(1, 1)
	labelText.Text = "DOOR (E)"
	labelText.TextColor3 = Color3.new(1, 1, 1)
	labelText.TextStrokeTransparency = 0.3
	labelText.Font = Enum.Font.GothamBold
	labelText.TextScaled = true
	labelText.Parent = label
	label.Parent = button
	post.Parent = matchFolder
	-- players can't walk out of their room; robots walk straight through this
	local barrier = Instance.new("Part")
	barrier.Name = "Barrier" .. side
	barrier.Anchored = true
	barrier.Transparency = 1
	barrier.CanQuery = false
	barrier.CanTouch = false
	barrier.CastShadow = false
	barrier.Size = Vector3.new(1, size.Y + 4, size.Z)
	barrier.CFrame = cf
	barrier.CollisionGroup = "ChimeBarrier"
	barrier.Parent = matchFolder
end

---------------------------------------------------------------- robots
-- Every player side owns one robot of each kind. They stand in their alcove
-- (workspace.ChimeMap.Robots) and, once woken with coins, creep toward the
-- other room FNAF-style: frozen in place, jumping one camera spot at a time.

local robotsFolder = map:FindFirstChild("Robots") or Instance.new("Folder")
robotsFolder.Name = "Robots"
robotsFolder.Parent = map

local function makeRobotModel(kind: string): Model
	local info = robotInfo[kind]
	local folder = ServerStorage:FindFirstChild("ChimeRobots")
	local template = folder and folder:FindFirstChild(kind)
	local model: Model
	if template then
		model = template:Clone() -- the real model, once it has been made
	else
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = info.color
		desc.TorsoColor = info.color:Lerp(Color3.new(0, 0, 0), 0.25)
		desc.LeftArmColor = info.color
		desc.RightArmColor = info.color
		desc.LeftLegColor = info.color:Lerp(Color3.new(0, 0, 0), 0.4)
		desc.RightLegColor = info.color:Lerp(Color3.new(0, 0, 0), 0.4)
		model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
		-- glowing eyes instead of a face
		local head = model:FindFirstChild("Head") :: BasePart
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		for _, x in ipairs({ -0.28, 0.28 }) do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(0.28, 0.28, 0.28)
			eye.Material = Enum.Material.Neon
			eye.Color = Color3.fromRGB(255, 255, 230)
			eye.CanCollide = false
			eye.Massless = true
			eye.CFrame = head.CFrame * CFrame.new(x, 0.12, -0.56)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = eye
			weld.Parent = eye
			eye.Parent = model
		end
	end
	model.Name = info.name
	model:SetAttribute("ChimeRobot", kind)
	return model
end

-- set up a robot model as a frozen animatronic (anchored, no collisions)
local function prepareRobot(model: Model, kind: string, owner: string)
	local info = robotInfo[kind]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		humanoid.PlatformStand = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CollisionGroup = "ChimeRobots"
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart
	if not model.PrimaryPart then
		model.PrimaryPart = root
	end
	-- a name tag (handy on the cameras)
	if not root:FindFirstChild("NameTag") then
		local tag = Instance.new("BillboardGui")
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(120, 24)
		tag.StudsOffset = Vector3.new(0, 3.4, 0)
		tag.MaxDistance = 140
		tag.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = string.upper(info.name)
		text.TextColor3 = info.color
		text.TextStrokeTransparency = 0.3
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.Parent = tag
		tag.Parent = root
	end
	-- its sound tells you it is coming (louder as it gets closer)
	local sound = root:FindFirstChild("Presence") :: Sound?
	if not sound then
		local s = Instance.new("Sound")
		s.Name = "Presence"
		s.Looped = true
		s.Volume = 1.6
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 110
		s.Parent = root
		sound = s
	end
	local presence = sound :: Sound
	presence.SoundId = Shared.SOUNDS[kind]
	model:SetAttribute("ChimeRobot", kind)
	model:SetAttribute("ChimeOwner", owner)
	model.Name = info.name .. " (" .. owner .. ")"
end

local nextRobotId = 0
local robots = {} -- [owner side][kind] = robot record

local function homeOf(r): CFrame
	return Shared.robotSpot(r.owner, r.kind, if r.owner == "A" then "B" else "A", 1)
end

local function setStage(r, stage: number)
	r.stage = stage
	local victim = if r.owner == "A" then "B" else "A"
	r.model:PivotTo(Shared.robotSpot(r.owner, r.kind, victim, stage))
	r.model:SetAttribute("ChimeStage", stage)
end

for _, owner in ipairs({ "A", "B" }) do
	robots[owner] = {}
	for _, info in ipairs(Shared.ROBOTS) do
		local name = info.name .. " (" .. owner .. ")"
		local model = robotsFolder:FindFirstChild(name) :: any
		local folder = ServerStorage:FindFirstChild("ChimeRobots")
		if model and folder and folder:FindFirstChild(info.id) then
			model:Destroy() -- the real model has arrived: swap it in
			model = nil
		end
		if not model then
			model = makeRobotModel(info.id)
		end
		prepareRobot(model, info.id, owner)
		nextRobotId += 1
		local r = {
			id = nextRobotId,
			kind = info.id,
			owner = owner,
			model = model,
			root = model.PrimaryPart,
			active = false,
			stage = 1,
			light = 0,
		}
		robots[owner][info.id] = r
		setStage(r, 1)
		model.Parent = robotsFolder
	end
end

local function setTag(r, text: string)
	local tag = r.root:FindFirstChild("NameTag")
	local label = tag and tag:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = string.upper(text)
	end
end

local function robotAlive(r): boolean
	return r.active and match ~= nil and match == r.match and not r.match.over
end

-- back to its alcove, asleep again
local function removeRobot(r)
	if not r.active then
		return
	end
	r.active = false
	if r.match then
		r.match.robots[r.id] = nil
	end
	r.match = nil
	r.victim = nil
	local sound = r.root:FindFirstChild("Presence") :: Sound?
	if sound then
		sound:Stop()
	end
	r.model:SetAttribute("ChimeVictim", nil)
	r.model:SetAttribute("ChimeRobotId", nil)
	r.model:SetAttribute("ChimeState", nil)
	setTag(r, robotInfo[r.kind].name)
	setStage(r, 1)
end

local function retreat(r)
	if not r.active then
		return
	end
	r.model:SetAttribute("ChimeState", "leaving")
	task.wait(0.6)
	removeRobot(r)
end

local endMatch -- set below

local function playAt(parent: Instance, id: string, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 150
	s.Parent = parent
	s:Play()
	task.delay(6, function()
		s:Destroy()
	end)
end

-- the robot has got to its victim
local function catch(r)
	if not robotAlive(r) then
		return
	end
	local victim = r.victim
	local character = victim.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	r.model:SetAttribute("ChimeState", "catching")
	if root then
		local look = Vector3.new(root.Position.X, r.root.Position.Y, root.Position.Z)
		r.model:PivotTo(CFrame.lookAt(r.root.Position, look))
	end
	send(victim, "jumpscare", { robot = r.kind })
	playAt(r.root, Shared.SOUNDS.scream, 2)
	task.wait(CATCH_DELAY)
	if not robotAlive(r) then
		return
	end
	local tokens = victim:GetAttribute("ChimeTokens") or 0
	if tokens > 0 then
		victim:SetAttribute("ChimeTokens", tokens - 1)
		send(victim, "toast", { text = "💀 Your Death Token saved you from " .. robotInfo[r.kind].name .. "!" })
		local sender = r.match.players[r.owner]
		if sender then
			send(sender, "toast", { text = nameOf(victim) .. " used a Death Token against your " .. robotInfo[r.kind].name })
		end
		removeRobot(r)
		return
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		r.match.caughtBy = robotInfo[r.kind].name
		humanoid.Health = 0 -- the Died handler ends the match
	end
	removeRobot(r)
end

-- wait for movement opportunities until one succeeds (FNAF style)
local function waitForMove(r, stop: (() -> boolean)?): boolean
	local info = robotInfo[r.kind]
	while true do
		local untilTime = os.clock() + info.interval
		while os.clock() < untilTime do
			task.wait(0.1)
			if not robotAlive(r) or (stop and stop()) then
				return false
			end
		end
		if math.random() < info.chance then
			return true
		end
	end
end

local function runRobot(r)
	r.light = 0
	r.root:FindFirstChild("Presence"):Play()
	r.model:SetAttribute("ChimeState", "coming")
	local victimSide = if r.owner == "A" then "B" else "A"

	local function flashedAway(): boolean
		return r.kind == "glare" and r.light >= GLARE_LIGHT_NEEDED
	end
	local function repel()
		playAt(r.root, Shared.SOUNDS.chime, 1.2)
		send(r.victim, "toast", { text = "✨ Glare fled from the light!" })
		retreat(r)
	end

	-- creep up to the door, one spot at a time
	while r.stage < Shared.STAGE_DOOR do
		if not waitForMove(r, flashedAway) then
			if robotAlive(r) and flashedAway() then
				repel()
			end
			return
		end
		setStage(r, r.stage + 1)
	end

	if r.kind == "brute" and doors[victimSide].closed then
		-- bang on the door until it gives up (or the door opens)
		r.model:SetAttribute("ChimeState", "banging")
		local untilTime = os.clock() + BRUTE_BANG_SECONDS
		local door = doors[victimSide]
		while os.clock() < untilTime and door.closed and robotAlive(r) do
			playAt(door.part, Shared.SOUNDS.bang, 1.5)
			-- shake the door a little
			door.part.CFrame = door.closedCF * CFrame.new(0, 0, (math.random() - 0.5) * 0.6)
			local e = r.victim:GetAttribute("ChimeEnergy") or 0
			r.victim:SetAttribute("ChimeEnergy", math.max(0, e - BRUTE_DRAIN))
			task.wait(1)
			if door.closed then
				door.part.CFrame = door.closedCF
			end
		end
		if not robotAlive(r) then
			return
		end
		if door.closed then
			send(r.victim, "toast", { text = "🚪 Brute gave up on your door." })
			retreat(r)
			return
		end
		-- the door gave way: straight in
		setStage(r, Shared.STAGE_INSIDE)
	else
		-- one more opportunity and it's in the room
		if not waitForMove(r, flashedAway) then
			if robotAlive(r) and flashedAway() then
				repel()
			end
			return
		end
		if r.kind == "brute" and doors[victimSide].closed then
			-- shut in its face at the last moment
			send(r.victim, "toast", { text = "🚪 Brute gave up on your door." })
			retreat(r)
			return
		end
		setStage(r, Shared.STAGE_INSIDE)
	end
	r.model:SetAttribute("ChimeState", "inside")

	if r.kind == "glare" then
		local untilTime = os.clock() + GLARE_WINDOW
		while os.clock() < untilTime and robotAlive(r) do
			if flashedAway() then
				repel()
				return
			end
			task.wait(0.1)
		end
		catch(r)
	elseif r.kind == "hollow" then
		task.wait(HOLLOW_WAIT)
		if not robotAlive(r) then
			return
		end
		if r.victim:GetAttribute("ChimeMask") == true then
			send(r.victim, "toast", { text = "🎭 Hollow didn't recognise you and left." })
			retreat(r)
		else
			catch(r)
		end
	else
		catch(r)
	end
end

local function summon(m, senderSide: string, kind: string): boolean
	local r = robots[senderSide][kind]
	if r.active then
		return false
	end
	local victimSide = if senderSide == "A" then "B" else "A"
	r.active = true
	r.match = m
	r.victim = m.players[victimSide]
	setStage(r, 1)
	if r.victim == m.players[senderSide] then
		r.active = false -- never hunt your own owner
		r.match = nil
		r.victim = nil
		return false
	end
	setTag(r, robotInfo[kind].name .. " · " .. m.names[senderSide])
	r.model:SetAttribute("ChimeRobotId", r.id)
	r.model:SetAttribute("ChimeVictim", r.victim.UserId)
	m.robots[r.id] = r
	task.spawn(function()
		local ok, err = pcall(runRobot, r)
		if not ok then
			warn("[Chime] robot error:", err)
			removeRobot(r)
		end
	end)
	return true
end

---------------------------------------------------------------- matches

local invites = {} -- [fromUserId] = { from, to, expires }
local nextMatchId = 0

local function clearPlayer(player: Player)
	for _, name in ipairs({ "ChimeMatch", "ChimeSide", "ChimeOpponent", "ChimeCoins", "ChimeEnergy", "ChimeTokens", "ChimeMask", "ChimeFlash", "ChimeDoor" }) do
		player:SetAttribute(name, nil)
	end
end

local function sideOf(player: Player): string?
	if not match then
		return nil
	end
	for side, p in pairs(match.players) do
		if p == player then
			return side
		end
	end
	return nil
end

endMatch = function(m, winnerSide: string?, reason: string)
	if m.over then
		return
	end
	m.over = true
	for _, r in pairs(m.robots) do
		removeRobot(r)
	end
	for _, side in ipairs({ "A", "B" }) do
		setDoor(side, false, true)
	end
	for side, p in pairs(m.players) do
		local result = if winnerSide == nil then "draw" elseif winnerSide == side then "win" else "lose"
		send(p, "ended", { result = result, reason = reason, opponent = m.names[if side == "A" then "B" else "A"] })
		if typeof(p) == "Instance" and p.Parent then
			clearPlayer(p)
		end
	end
	for _, c in ipairs(m.connections) do
		c:Disconnect()
	end
	if match == m then
		match = nil
	end
	-- back to the train after a moment
	task.delay(4, function()
		for _, p in pairs(m.players) do
			if typeof(p) == "Instance" and p.Parent then
				p:LoadCharacter()
			end
		end
	end)
end

local function startMatch(a: Player, b: Player)
	if match then
		return false
	end
	for fromId, inv in pairs(invites) do
		if inv.from == a or inv.from == b or inv.to == a or inv.to == b then
			invites[fromId] = nil
		end
	end
	nextMatchId += 1
	local m = {
		id = nextMatchId,
		players = { A = a, B = b },
		names = { A = nameOf(a), B = nameOf(b) },
		robots = {},
		started = os.clock(),
		over = false,
		connections = {},
	}
	match = m
	for side, p in pairs(m.players) do
		local other = if side == "A" then b else a
		p:SetAttribute("ChimeMatch", m.id)
		p:SetAttribute("ChimeSide", side)
		p:SetAttribute("ChimeOpponent", nameOf(other))
		p:SetAttribute("ChimeCoins", 0)
		p:SetAttribute("ChimeEnergy", Shared.START_ENERGY)
		p:SetAttribute("ChimeTokens", 0)
		p:SetAttribute("ChimeMask", false)
		p:SetAttribute("ChimeFlash", false)
		p:SetAttribute("ChimeDoor", false)
	end
	for side, p in pairs(m.players) do
		task.spawn(function()
			local spawnCF = Shared.roomSpawn(side)
			pcall(function()
				p:RequestStreamAroundAsync(spawnCF.Position, 10)
			end)
			local character = p.Character
			if character then
				character:PivotTo(spawnCF)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					table.insert(m.connections, humanoid.Died:Connect(function()
						if not m.over then
							endMatch(m, if side == "A" then "B" else "A", "caught")
						end
					end))
				end
			end
			send(p, "match", { id = m.id, side = side, opponent = m.names[if side == "A" then "B" else "A"] })
		end)
	end
	return true
end

-- energy use, every quarter second
task.spawn(function()
	while true do
		task.wait(0.25)
		local m = match
		if m and not m.over then
			if os.clock() - m.started > Shared.MATCH_SECONDS then
				endMatch(m, nil, "time")
			else
				for side, p in pairs(m.players) do
					local e = p:GetAttribute("ChimeEnergy") or 0
					local use = 0
					if doors[side].closed then
						use += Shared.DOOR_DRAIN
					end
					if p:GetAttribute("ChimeFlash") then
						use += Shared.FLASH_DRAIN
					end
					if use > 0 then
						e = math.max(0, e - use * 0.25)
						p:SetAttribute("ChimeEnergy", e)
					end
					if e <= 0 then
						-- out of power: the door rolls up and the light dies
						if doors[side].closed then
							setDoor(side, false)
							send(p, "toast", { text = "⚡ Out of energy! Your door opened." })
						end
						if p:GetAttribute("ChimeFlash") then
							p:SetAttribute("ChimeFlash", false)
						end
					end
				end
			end
		end
	end
end)

onDoorClicked = function(player: Player, side: string)
	local mySide = sideOf(player)
	if mySide ~= side or not match or match.over then
		return
	end
	local closing = not doors[side].closed
	if closing and (player:GetAttribute("ChimeEnergy") or 0) <= 0 then
		send(player, "toast", { text = "⚡ No energy to shut the door." })
		return
	end
	setDoor(side, closing)
end

---------------------------------------------------------------- requests

local lastCall = {}

event.OnServerEvent:Connect(function(player: Player, action: any, data: any)
	if type(action) ~= "string" then
		return
	end
	data = if type(data) == "table" then data else {}
	local now = os.clock()
	if action ~= "flashHit" then
		if lastCall[player] and now - lastCall[player] < 0.15 then
			return
		end
		lastCall[player] = now
	end

	if action == "challenge" then
		local target = if type(data.target) == "number" then Players:GetPlayerByUserId(data.target) else nil
		if not target or target == player or sideOf(player) then
			return
		end
		if match then
			send(player, "outgoing", { name = nameOf(target), status = "busy" })
			return
		end
		-- they already challenged you? then it's on
		local theirs = invites[target.UserId]
		if theirs and theirs.to == player then
			startMatch(target, player)
			return
		end
		local old = invites[player.UserId]
		if old then
			send(old.to, "inviteGone", { from = player.UserId })
		end
		invites[player.UserId] = { from = player, to = target, expires = now + INVITE_SECONDS }
		send(target, "invite", { from = player.UserId, name = nameOf(player), seconds = INVITE_SECONDS })
		send(player, "outgoing", { name = nameOf(target), status = "waiting", seconds = INVITE_SECONDS })
	elseif action == "cancel" then
		local inv = invites[player.UserId]
		if inv then
			invites[player.UserId] = nil
			send(inv.to, "inviteGone", { from = player.UserId })
			send(player, "outgoing", { status = "cancelled" })
		end
	elseif action == "respond" then
		local inv = if type(data.from) == "number" then invites[data.from] else nil
		if not inv or inv.to ~= player then
			return
		end
		invites[data.from] = nil
		if data.accept == true then
			if match then
				send(player, "toast", { text = "Someone is already playing Chime of Conflict — try again after their match." })
				send(inv.from, "outgoing", { name = nameOf(player), status = "busy" })
				return
			end
			startMatch(inv.from, player)
		else
			send(inv.from, "outgoing", { name = nameOf(player), status = "declined" })
		end
	elseif action == "sync" then
		for fromId, inv in pairs(invites) do
			if inv.to == player then
				send(player, "invite", { from = fromId, name = nameOf(inv.from), seconds = inv.expires - now })
			end
		end
		send(player, "busy", { busy = match ~= nil })
	else
		-- everything below needs a match
		local side = sideOf(player)
		local m = match
		if not side or not m or m.over then
			return
		end
		if action == "buy" then
			local id = data.id
			local coins = player:GetAttribute("ChimeCoins") or 0
			local robot = type(id) == "string" and robotInfo[id]
			local item = type(id) == "string" and itemInfo[id]
			local price = if robot then robot.price elseif item then item.price else nil
			if not price then
				return
			end
			if coins < price then
				send(player, "toast", { text = string.format("You need %d more coins.", price - coins) })
				return
			end
			if robot then
				if robots[side][id].active then
					send(player, "toast", { text = robot.name .. " is already out hunting." })
					return
				end
				player:SetAttribute("ChimeCoins", coins - price)
				summon(m, side, id)
				send(player, "toast", { text = "🤖 " .. robot.name .. " is on its way to " .. m.names[if side == "A" then "B" else "A"] .. "!" })
			elseif id == "token" then
				player:SetAttribute("ChimeCoins", coins - price)
				player:SetAttribute("ChimeTokens", (player:GetAttribute("ChimeTokens") or 0) + 1)
				send(player, "toast", { text = "💀 You have a Death Token." })
			elseif id == "energy" then
				local e = player:GetAttribute("ChimeEnergy") or 0
				if e >= Shared.MAX_ENERGY then
					send(player, "toast", { text = "Your energy is already full." })
					return
				end
				player:SetAttribute("ChimeCoins", coins - price)
				player:SetAttribute("ChimeEnergy", math.min(Shared.MAX_ENERGY, e + 40))
				send(player, "toast", { text = "🔋 +40 energy" })
			end
		elseif action == "door" then
			onDoorClicked(player, side)
		elseif action == "flash" then
			local on = data.on == true
			if on and ((player:GetAttribute("ChimeEnergy") or 0) <= 0 or player:GetAttribute("ChimeMask")) then
				on = false
			end
			player:SetAttribute("ChimeFlash", on)
		elseif action == "flashHit" then
			-- the client says its flashlight is on a robot; check it's plausible
			if not player:GetAttribute("ChimeFlash") then
				return
			end
			local r = type(data.robot) == "number" and m.robots[data.robot]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not r or r.victim ~= player or not root then
				return
			end
			if (r.root.Position - root.Position).Magnitude > 90 then
				return
			end
			local last = r.lastLight or 0
			r.lastLight = now
			r.light += math.min(now - last, 0.3)
		elseif action == "mask" then
			local on = data.on == true
			player:SetAttribute("ChimeMask", on)
			if on then
				player:SetAttribute("ChimeFlash", false)
			end
		elseif action == "forfeit" then
			endMatch(m, if side == "A" then "B" else "A", "forfeit")
		end
	end
end)

-- challenges time out
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for fromId, inv in pairs(invites) do
			if now >= inv.expires then
				invites[fromId] = nil
				send(inv.to, "inviteGone", { from = fromId })
				send(inv.from, "outgoing", { name = nameOf(inv.to), status = "expired" })
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
	for fromId, inv in pairs(invites) do
		if inv.from == player or inv.to == player then
			invites[fromId] = nil
			if inv.from == player then
				send(inv.to, "inviteGone", { from = fromId })
			else
				send(inv.from, "outgoing", { name = nameOf(player), status = "left" })
			end
		end
	end
	local side = sideOf(player)
	if side and match then
		endMatch(match, if side == "A" then "B" else "A", "left")
	end
end)

-- Studio only: test a match on your own against a stand-in opponent, and send
-- robots at yourself. ServerStorage.ChimeTest:Invoke("solo", player),
-- :Invoke("summon", "glare"|"brute"|"hollow"), :Invoke("coins", player, n)
if game:GetService("RunService"):IsStudio() then
	local test = ServerStorage:FindFirstChild("ChimeTest") or Instance.new("BindableFunction")
	test.Name = "ChimeTest"
	test.Parent = ServerStorage
	test.OnInvoke = function(command: string, a: any, b: any)
		if command == "solo" then
			local attrs = {}
			local standIn = {
				Name = "Stand-in",
				DisplayName = "Stand-in",
				UserId = -1,
				Character = nil,
				SetAttribute = function(_, k, v)
					attrs[k] = v
				end,
				GetAttribute = function(_, k)
					return attrs[k]
				end,
				RequestStreamAroundAsync = function() end,
			}
			return startMatch(a, standIn :: any)
		elseif command == "summon" and match then
			summon(match, "B", a)
			return true
		elseif command == "coins" then
			a:SetAttribute("ChimeCoins", b)
			return true
		elseif command == "end" and match then
			endMatch(match, nil, "time")
			return true
		end
		return false
	end
end
