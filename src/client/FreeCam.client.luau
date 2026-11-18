-- Free-fly camera. Press the key (default "L") to detach the camera from the
-- character and fly it around; the avatar stays where it is (still riding
-- the train) and doesn't move. Press the key again to go back to first person.
--
-- Controls while flying:
--   Mouse        look around
--   W A S D      move
--   E / Space    up
--   Q / Ctrl     down
--   Shift        faster

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local TOGGLE_KEY = Enum.KeyCode.L
local SPEED = 60 -- studs per second
local FAST_MULTIPLIER = 3
local LOOK_SENSITIVITY = 0.25 -- degrees per pixel of mouse movement

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local flying = false
local yaw, pitch = 0, 0
local position = Vector3.zero
local renderConnection: RBXScriptConnection? = nil
local savedWalkSpeed, savedJumpHeight = 16, 7.2

local MOVE_KEYS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.E] = Vector3.new(0, 1, 0),
	[Enum.KeyCode.Space] = Vector3.new(0, 1, 0),
	[Enum.KeyCode.Q] = Vector3.new(0, -1, 0),
	[Enum.KeyCode.LeftControl] = Vector3.new(0, -1, 0),
}

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- While flying, swallow movement keys so they don't also reach the character.
local function sinkInput()
	return Enum.ContextActionResult.Sink
end
local sunkKeys = {}
for key in pairs(MOVE_KEYS) do
	table.insert(sunkKeys, key)
end

-- First person hides your own body; show it while the camera is away.
local function showOwnAvatar()
	local character = player.Character
	if not character then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = 0
		end
	end
end

local function startFlying()
	flying = true
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	position = camera.CFrame.Position

	-- freeze the avatar in place (it keeps riding the train)
	local humanoid = getHumanoid()
	if humanoid then
		savedWalkSpeed, savedJumpHeight = humanoid.WalkSpeed, humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	end
	ContextActionService:BindActionAtPriority("FreeCamSink", sinkInput, false, Enum.ContextActionPriority.High.Value, table.unpack(sunkKeys))

	camera.CameraType = Enum.CameraType.Scriptable

	renderConnection = RunService.RenderStepped:Connect(function(dt)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta()
		yaw -= math.rad(delta.X * LOOK_SENSITIVITY)
		pitch = math.clamp(pitch - math.rad(delta.Y * LOOK_SENSITIVITY), math.rad(-89), math.rad(89))

		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local move = Vector3.zero
		for key, dir in pairs(MOVE_KEYS) do
			if UserInputService:IsKeyDown(key) then
				move += dir
			end
		end
		if move.Magnitude > 0 then
			local speed = SPEED
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				speed *= FAST_MULTIPLIER
			end
			local horizontal = rotation:VectorToWorldSpace(Vector3.new(move.X, 0, move.Z))
			local worldMove = horizontal + Vector3.new(0, move.Y, 0)
			position += worldMove.Unit * speed * dt
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(position) * rotation
		showOwnAvatar()
	end)
end

local function stopFlying()
	flying = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	ContextActionService:UnbindAction("FreeCamSink")
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.WalkSpeed = savedWalkSpeed
		humanoid.JumpHeight = savedJumpHeight
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
end

local function toggle()
	if flying then
		stopFlying()
	else
		startFlying()
	end
end

-- Listen for the key at high priority so nothing else can swallow it.
-- (ContextActionService ignores keys typed into chat automatically.)
ContextActionService:BindActionAtPriority("FreeCamToggle", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 1, TOGGLE_KEY)

-- Lets other scripts (and tests) switch the free camera too.
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "Toggle"
toggleEvent.Event:Connect(toggle)
toggleEvent.Parent = script

-- Respawning while flying puts the camera back on the new character.
player.CharacterAdded:Connect(function()
	if flying then
		stopFlying()
	end
end)
