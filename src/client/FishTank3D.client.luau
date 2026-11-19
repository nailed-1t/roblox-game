-- Three fish that leap over the rim of the 3D fish tank (workspace.fish_tank_test)
-- whenever the server announces a jump (see the FishTank server script).
-- Click the fish while it's in the air for 10 points.
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
local JUMP_HEIGHT = 45 -- how far above the rim they leap
local JUMP_ALONG = 50 -- how far along the rim they travel

local camera = workspace.CurrentCamera
local tank = workspace:WaitForChild("fish_tank_test", 60)
if not tank then
	return
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

local function tankShape(): (Vector3, number, number)
	local cf, size = tank:GetBoundingBox()
	return cf.Position, math.max(size.X, size.Z) / 2, cf.Position.Y + size.Y / 2
end

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

local shown = nil
RunService.RenderStepped:Connect(function()
	local flying, t = inAir()
	local fish = flying and fishes[jump.fish] or nil
	if shown and shown ~= fish then
		place(shown, nil)
	end
	shown = fish
	if not fish then
		return
	end
	local center, radius, top = tankShape()
	local out = Vector3.new(math.cos(jump.angle), 0, math.sin(jump.angle))
	local along = Vector3.new(-out.Z, 0, out.X)
	local rim = center + out * (radius - 8)
	-- arc: up out of the water, over, and back down
	local function at(u: number): Vector3
		return rim + along * ((u - 0.5) * JUMP_ALONG) + Vector3.new(0, top - 12 + math.sin(u * math.pi) * (JUMP_HEIGHT + 12), 0)
	end
	local p = at(t)
	local ahead = at(t + 0.01)
	-- lie flat facing out of the tank, the picture's head (left side, which is
	-- the plane's +X when seen from the front) leading the way
	local x = (ahead - p).Unit
	local z = -out
	local y = z:Cross(x).Unit
	place(fish, CFrame.fromMatrix(p, x, y, z))
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
	if not inAir() or not shown then
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
	params.FilterDescendantsInstances = { shown.model }
	if not workspace:Raycast(ray.Origin, ray.Direction * 3000, params) then
		return
	end
	local id = jump.id
	local where = shown.model.Position
	task.spawn(function()
		local gained = FishApp.catch(id)
		if gained > 0 then
			pop("+" .. gained .. " points!", where)
		end
	end)
end)
