-- The abilities sold in the shop.
--   Ardor Scream: a yell that throws everyone within range away from you
--                 and ragdolls them for a moment.
--   Head Swap:    swaps your avatar with the closest player's for a minute.
-- Clients ask with ShopRemotes.UseAbility; the server checks ownership and
-- cooldowns. ShopRemotes.AbilityFx tells clients what happened (ragdoll your
-- own character, cooldown started, short messages).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ShopItems = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ShopItems"))
local remotes = ReplicatedStorage:WaitForChild("ShopRemotes")

local function remote(class: string, name: string)
	local r = remotes:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local useRemote = remote("RemoteEvent", "UseAbility") :: RemoteEvent
local fxRemote = remote("RemoteEvent", "AbilityFx") :: RemoteEvent

local SCREAM_RANGE = 22
local SCREAM_PUSH = 65
local SCREAM_LIFT = 32
local RAGDOLL_SECONDS = 2.5
local SWAP_RANGE = 40
local SWAP_SECONDS = 60

local itemsById = {}
for _, item in ipairs(ShopItems) do
	itemsById[item.id] = item
end

local readyAt = {} -- [player][id] = os.clock() when usable again

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------- ragdoll

local ragdolled = {} -- [character] = { motors, made }

local function ragdoll(player: Player, push: Vector3)
	local character = player.Character
	if not character or ragdolled[character] then
		return
	end
	local state = { motors = {}, made = {}, collide = {} }
	ragdolled[character] = state
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Name ~= "RootJoint" and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = motor.Part1
			table.insert(state.made, a0)
			table.insert(state.made, a1)
			table.insert(state.made, socket)
			motor.Enabled = false
			table.insert(state.motors, motor)
			if not state.collide[motor.Part1] then
				state.collide[motor.Part1] = motor.Part1.CanCollide
				motor.Part1.CanCollide = true
			end
		end
	end
	fxRemote:FireClient(player, "ragdoll", true, push)
	task.delay(RAGDOLL_SECONDS, function()
		if ragdolled[character] ~= state then
			return
		end
		ragdolled[character] = nil
		for _, motor in ipairs(state.motors) do
			if motor.Parent then
				motor.Enabled = true
			end
		end
		for _, inst in ipairs(state.made) do
			inst:Destroy()
		end
		for part, was in pairs(state.collide) do
			if part.Parent then
				part.CanCollide = was
			end
		end
		if player.Character == character then
			fxRemote:FireClient(player, "ragdoll", false)
		end
	end)
end

---------------------------------------------------------------- Ardor Scream

local function shout(character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "ArdorShout"
	board.Size = UDim2.fromScale(9, 2.2)
	board.StudsOffset = Vector3.new(0, 3, 0)
	board.LightInfluence = 0
	board.MaxDistance = 250
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.TextScaled = true
	text.Text = "AAAAAAAAH!!"
	text.TextColor3 = Color3.fromRGB(255, 196, 92)
	text.TextStrokeColor3 = Color3.fromRGB(120, 20, 0)
	text.TextStrokeTransparency = 0
	text.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	text.Parent = board
	board.Parent = head
	TweenService:Create(text, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(board, 1.7)

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/swoosh.wav"
	sound.PlaybackSpeed = 0.55
	sound.Volume = 1.5
	sound.RollOffMaxDistance = 120
	sound.Parent = head
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function shockwave(at: Vector3)
	for i, color in ipairs({ Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 230, 160) }) do
		local ring = Instance.new("Part")
		ring.Name = "ArdorWave"
		ring.Shape = Enum.PartType.Ball
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Size = Vector3.new(2, 2, 2)
		ring.CFrame = CFrame.new(at)
		ring.Parent = workspace
		local d = SCREAM_RANGE * 2 * (if i == 1 then 1 else 0.7)
		TweenService:Create(ring, TweenInfo.new(0.45 + i * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(d, d, d),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.8)
	end
end

local function ardorScream(player: Player): (boolean, string?)
	local root = rootOf(player)
	if not root then
		return false, nil
	end
	shout(player.Character)
	shockwave(root.Position)
	local hit = 0
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot = other ~= player and rootOf(other)
		if otherRoot then
			local offset = otherRoot.Position - root.Position
			local distance = offset.Magnitude
			if distance <= SCREAM_RANGE then
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local away = if flat.Magnitude > 0.05 then flat.Unit else root.CFrame.LookVector
				local strength = 1 - 0.5 * (distance / SCREAM_RANGE) -- closer = harder
				ragdoll(other, away * SCREAM_PUSH * strength + Vector3.new(0, SCREAM_LIFT * strength, 0))
				hit += 1
			end
		end
	end
	return true, if hit == 0 then "Nobody was close enough to hear it." else nil
end

---------------------------------------------------------------- Head Swap

local swapped = {} -- [character] = original HumanoidDescription

local function puff(at: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(at)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 170, 255))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Speed = NumberRange.new(6, 12)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = p
	p.Parent = workspace
	smoke:Emit(40)
	Debris:AddItem(p, 2)
end

local function describe(character: Model): HumanoidDescription?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local ok, desc = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	return if ok then desc else nil
end

local function apply(character: Model, desc: HumanoidDescription)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		pcall(function()
			humanoid:ApplyDescription(desc)
		end)
	end
end

local function headSwap(player: Player): (boolean, string?)
	local root = rootOf(player)
	if not root then
		return false, nil
	end
	local best, bestDistance = nil, SWAP_RANGE
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot = other ~= player and rootOf(other)
		if otherRoot then
			local d = (otherRoot.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = other, d
			end
		end
	end
	if not best then
		return false, "Nobody is close enough to swap with."
	end
	local a, b = player.Character, best.Character
	local descA, descB = describe(a), describe(b)
	if not descA or not descB then
		return false, "The swap didn't work, try again."
	end
	-- remember each body's real look (only the first time, if swapped twice)
	swapped[a] = swapped[a] or descA
	swapped[b] = swapped[b] or descB
	puff(root.Position)
	puff(best.Character.HumanoidRootPart.Position)
	apply(a, descB)
	apply(b, descA)
	fxRemote:FireClient(best, "message", player.DisplayName .. " swapped bodies with you!")
	task.delay(SWAP_SECONDS, function()
		for _, character in ipairs({ a, b }) do
			local original = swapped[character]
			if original and character.Parent then
				swapped[character] = nil
				apply(character, original)
				local r = character:FindFirstChild("HumanoidRootPart")
				if r then
					puff(r.Position)
				end
			end
		end
	end)
	return true, "You swapped bodies with " .. best.DisplayName .. "!"
end

---------------------------------------------------------------- requests

local USE = {
	ardor = ardorScream,
	headswap = headSwap,
}

useRemote.OnServerEvent:Connect(function(player: Player, id: any)
	local item = typeof(id) == "string" and itemsById[id]
	local use = item and USE[item.id]
	if not use or not player:GetAttribute("Owned_" .. item.id) then
		return
	end
	readyAt[player] = readyAt[player] or {}
	local now = os.clock()
	if (readyAt[player][item.id] or 0) > now then
		return
	end
	local ok, message = use(player)
	if ok then
		readyAt[player][item.id] = now + item.cooldown
		fxRemote:FireClient(player, "cooldown", item.id, item.cooldown)
	end
	if message then
		fxRemote:FireClient(player, "message", message)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	readyAt[player] = nil
end)
