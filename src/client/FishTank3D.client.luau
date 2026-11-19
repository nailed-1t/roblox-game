-- Three fish that leap as a little school from one rim of the 3D fish tank
-- (workspace.fish_tank_test, a spinning bowl of ocean) right across to the
-- opposite rim whenever the server announces a jump (see the FishTank server
-- script). Click a fish while it's in the air for 10 points.
-- The fish are flat planes with the fish picture for now (only you see
-- them; the server just says when and where they jump).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local FishApp = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("FishApp"))

local SCALE = 7 -- the tank is far from the train, so the fish are big
local JUMP_HEIGHT = 70 -- how far above the rim they leap at the top of the arc
local SPIN_SPEED = math.rad(10) -- the ocean bowl turns this much a second
local LAGS = { 0, 0.1, 0.2 } -- the school follows the leader a little behind
local SIDE = { 0, -10, 10 } -- and a little to each side

local camera = workspace.CurrentCamera
local tank = workspace:WaitForChild("fish_tank_test", 60)
if not tank then
	return
end
-- the tank model is set to always stream in, but wait for its mesh anyway
local bowl = tank:IsA("BasePart") and tank or tank:FindFirstChildWhichIsA("BasePart", true)
while not bowl do
	tank.DescendantAdded:Wait()
	bowl = tank:FindFirstChildWhichIsA("BasePart", true)
end

---------------------------------------------------------------- fish
-- for now each fish is a flat plane with the fish picture on both sides,
-- in three tints

local FISH_LENGTH = 9 * SCALE
local TINTS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 190, 90),
	Color3.fromRGB(140, 200, 255),
}

local folder = Instance.new("Folder")
folder.Name = "JumpingFish"
folder.Parent = camera -- only drawn for you

local fishes = {}
for i, tint in ipairs(TINTS) do
	local plane = Instance.new("Part")
	plane.Name = "Fish" .. i
	plane.Anchored = true
	plane.CanCollide = false
	plane.CanTouch = false
	plane.CanQuery = true
	plane.CastShadow = false
	plane.Transparency = 1
	plane.Size = Vector3.new(FISH_LENGTH, FISH_LENGTH * 110 / 383, 0.2)
	plane.CFrame = CFrame.new(0, -5000, 0)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local decal = Instance.new("Decal")
		decal.Texture = FishApp.IMAGE
		decal.Color3 = tint
		decal.Face = face
		decal.Parent = plane
	end
	plane.Parent = folder
	fishes[i] = { model = plane }
end

local function place(fish, cf: CFrame?)
	fish.model.CFrame = cf or CFrame.new(0, -5000, 0) -- parked out of sight
end

---------------------------------------------------------------- jumps

-- the bowl's resting pose, taken once before it starts turning (its size is
-- read live: a mesh can report a different size until it has fully loaded)
local baseCF = bowl.CFrame
local function tankShape(): (Vector3, number, number)
	local size = bowl.Size
	return baseCF.Position, math.max(size.X, size.Z) / 2, baseCF.Position.Y + size.Y / 2
end

---------------------------------------------------------------- spinning ocean
-- each player's game turns the bowl locally, so it's smooth for everyone
RunService.RenderStepped:Connect(function()
	local angle = (workspace:GetServerTimeNow() * SPIN_SPEED) % (2 * math.pi)
	bowl.CFrame = CFrame.new(baseCF.Position) * CFrame.Angles(0, angle, 0) * baseCF.Rotation
end)

local jump = nil -- { id, at, length, angle, fish }
local function readJump()
	local id = workspace:GetAttribute("FishJumpId")
	if id then
		jump = {
			id = id,
			at = workspace:GetAttribute("FishJumpAt") or 0,
			length = workspace:GetAttribute("FishJumpLength") or 2.4,
			angle = math.rad(workspace:GetAttribute("FishJumpAngle") or 0),
			fish = workspace:GetAttribute("FishJumpFish") or 1,
		}
	end
end
readJump()
workspace:GetAttributeChangedSignal("FishJumpId"):Connect(readJump)

local function inAir(): (boolean, number)
	if not jump then
		return false, 0
	end
	local t = (workspace:GetServerTimeNow() - jump.at) / jump.length
	return t >= 0 and t <= 1, t
end

local shown = {} -- fish currently in the air

RunService.RenderStepped:Connect(function()
	local flying, t = inAir()
	if not flying then
		for _, fish in ipairs(fishes) do
			if shown[fish] then
				place(fish, nil)
				shown[fish] = nil
			end
		end
		return
	end
	local center, radius, top = tankShape()
	local out = Vector3.new(math.cos(jump.angle), 0, math.sin(jump.angle))
	local side = Vector3.new(-out.Z, 0, out.X)
	local ground = Vector3.new(center.X, 0, center.Z) -- heights are added below
	local from = ground + out * (radius - 10)
	local to = ground - out * (radius - 10)
	local maxLag = LAGS[#LAGS]
	for i, fish in ipairs(fishes) do
		-- the jump's fish leads, the other two follow
		local rank = ((i - jump.fish) % #fishes) + 1
		local u = (t - LAGS[rank]) / (1 - maxLag)
		if u < 0 or u > 1 then
			if shown[fish] then
				place(fish, nil)
				shown[fish] = nil
			end
			continue
		end
		local offset = side * SIDE[rank]
		local height = JUMP_HEIGHT - (rank - 1) * 8
		local function at(v: number): Vector3
			return from:Lerp(to, v) + offset + Vector3.new(0, top - 15 + math.sin(v * math.pi) * (height + 15), 0)
		end
		local p = at(u)
		local ahead = at(u + 0.01)
		-- side-on to the tank's middle line so you see the fish's profile, the
		-- picture's head (the plane's +X seen from the front) leading the way
		local x = (ahead - p).Unit
		local z = side
		local y = z:Cross(x).Unit
		z = x:Cross(y)
		place(fish, CFrame.fromMatrix(p, x, y, z))
		shown[fish] = true
	end
end)

---------------------------------------------------------------- catching

local function pop(text: string, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = camera
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(40, 12)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 210, 90)
	label.TextStrokeTransparency = 0.2
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	label.Parent = board
	TweenService:Create(anchor, TweenInfo.new(1.2), { CFrame = anchor.CFrame + Vector3.new(0, 25, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if not inAir() or not next(shown) then
		return
	end
	local inset = GuiService:GetGuiInset()
	local mouse = UserInputService:GetMouseLocation() - Vector2.new(0, inset.Y)
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		mouse = camera.ViewportSize / 2
	end
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {}
	for fish in pairs(shown) do
		table.insert(list, fish.model)
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not hit then
		return
	end
	local id = jump.id
	local where = hit.Instance.Position
	task.spawn(function()
		local gained = FishApp.catch(id)
		if gained > 0 then
			pop("+" .. gained .. " points!", where)
		end
	end)
end)
