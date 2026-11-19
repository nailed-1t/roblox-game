-- The tablet's Fish Tank app: a side-on (2D-looking) view of the game's fish tank (the
-- imported ocean bowl, workspace.fish_tank_test), spinning, with the three fish
-- leaping from one rim right across to the other whenever the server announces
-- a jump (see the FishTank server script). Tap a fish in the air for 10 points.
-- Also used by the fish over the real tank (FishTank3D) for the picture, the
-- jump path and catching, so both always show the same jump.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local FishApp = {}
FishApp.__index = FishApp

FishApp.IMAGE = "rbxassetid://84321219156286" -- assets/jumping_fish.png (383x110)
FishApp.TINTS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 190, 90),
	Color3.fromRGB(140, 200, 255),
}
FishApp.SPIN_SPEED = math.rad(10) -- the ocean bowl turns this much a second
local JUMP_HEIGHT = 70 -- how far above the rim the leader leaps
local LAGS = { 0, 0.1, 0.2 } -- the school follows the leader a little behind
local SIDE = { 0, -10, 10 } -- and a little to each side
local FISH_LENGTH = 63

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local player = Players.LocalPlayer

-- ask the server for the points (shared by the app and the 3D tank)
function FishApp.catch(id: number): number
	local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
	local remote = remotes and remotes:FindFirstChild("CatchFish")
	if not remote then
		return 0
	end
	local ok, gained = pcall(function()
		return remote:InvokeServer(id)
	end)
	return if ok and type(gained) == "number" then gained else 0
end

-- the current jump, from the attributes the server sets
function FishApp.readJump(): { [string]: any }?
	local id = workspace:GetAttribute("FishJumpId")
	if not id then
		return nil
	end
	return {
		id = id,
		at = workspace:GetAttribute("FishJumpAt") or 0,
		length = workspace:GetAttribute("FishJumpLength") or 3.2,
		angle = math.rad(workspace:GetAttribute("FishJumpAngle") or 0),
		fish = workspace:GetAttribute("FishJumpFish") or 1,
	}
end

-- how far through the jump we are (0..1 while the fish are in the air)
function FishApp.progress(jump): number
	return if jump then (workspace:GetServerTimeNow() - jump.at) / jump.length else -1
end

-- the bowl's turn right now (the same for every player)
function FishApp.spin(): number
	return (workspace:GetServerTimeNow() * FishApp.SPIN_SPEED) % (2 * math.pi)
end

-- where each of the three fish is at progress t of the jump: a CFrame, or
-- nil while that fish is in the water. center/radius/top describe the bowl.
-- The plane's +X is the fish's head; it faces sideways so you see its profile.
function FishApp.school(jump, t: number, center: Vector3, radius: number, top: number): { CFrame? }
	local result = {}
	local out = Vector3.new(math.cos(jump.angle), 0, math.sin(jump.angle))
	local side = Vector3.new(-out.Z, 0, out.X)
	local ground = Vector3.new(center.X, 0, center.Z)
	local from = ground + out * (radius - 10)
	local to = ground - out * (radius - 10)
	local maxLag = LAGS[#LAGS]
	for i = 1, #FishApp.TINTS do
		-- the jump's fish leads, the other two follow
		local rank = ((i - jump.fish) % #FishApp.TINTS) + 1
		local u = (t - LAGS[rank]) / (1 - maxLag)
		if u < 0 or u > 1 then
			continue
		end
		local offset = side * SIDE[rank]
		local height = JUMP_HEIGHT - (rank - 1) * 8
		local function at(v: number): Vector3
			return from:Lerp(to, v) + offset + Vector3.new(0, top - 15 + math.sin(v * math.pi) * (height + 15), 0)
		end
		local p = at(u)
		local x = (at(u + 0.01) - p).Unit
		local y = side:Cross(x).Unit
		result[i] = CFrame.fromMatrix(p, x, y, x:Cross(y))
	end
	return result
end

-- a fish: a flat plane with the picture on both sides
function FishApp.makeFish(i: number, scale: number?): Part
	local length = FISH_LENGTH * (scale or 1)
	local plane = Instance.new("Part")
	plane.Name = "Fish" .. i
	plane.Anchored = true
	plane.CanCollide = false
	plane.CanTouch = false
	plane.CanQuery = true
	plane.CastShadow = false
	plane.Transparency = 1
	plane.Size = Vector3.new(length, length * 110 / 383, 0.2)
	plane.CFrame = CFrame.new(0, -5000, 0)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local decal = Instance.new("Decal")
		decal.Texture = FishApp.IMAGE
		decal.Color3 = FishApp.TINTS[i]
		decal.Face = face
		decal.Parent = plane
	end
	return plane
end

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, ch in ipairs(children or {}) do
		ch.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(scale: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(scale, 0) })
end

local function text(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = Color3.fromRGB(245, 246, 250),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p)
end

local function points(): number?
	local stats = player and player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Points")
	return if value then value.Value else nil
end

function FishApp.new(pages: Instance)
	local self = setmetatable({}, FishApp)

	local page = new("Frame", {
		Name = "Fish",
		BackgroundColor3 = Color3.fromRGB(8, 22, 48),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Visible = false,
		Parent = pages,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(40, 70, 120), Color3.fromRGB(6, 14, 34)),
		}),
	})
	self.page = page

	-- the 3D view of the real tank
	local view = new("ViewportFrame", {
		Name = "TankView",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 160, 185),
		LightColor = Color3.fromRGB(255, 250, 235),
		LightDirection = Vector3.new(-0.4, -1, -0.5),
		Active = true,
		Parent = page,
	})
	local world = new("WorldModel", { Parent = view })
	-- a narrow lens from far away flattens it into a 2D side view
	local camera = new("Camera", { FieldOfView = 10.5, Parent = view })
	view.CurrentCamera = camera
	self.view, self.world, self.camera = view, world, camera
	self.fishes = {}
	for i = 1, #FishApp.TINTS do
		self.fishes[i] = FishApp.makeFish(i)
		self.fishes[i].Parent = world
	end
	task.spawn(function()
		self:_loadTank()
	end)

	-- header
	local bar = new("Frame", {
		Name = "Header",
		Position = UDim2.fromScale(0.03, 0.04),
		Size = UDim2.fromScale(0.94, 0.11),
		BackgroundColor3 = Color3.fromRGB(10, 30, 60),
		BackgroundTransparency = 0.45,
		ZIndex = 5,
		Parent = page,
	}, { corner(0.4) })
	text({
		Position = UDim2.fromScale(0.03, 0.18),
		Size = UDim2.fromScale(0.5, 0.64),
		FontFace = FONT_BOLD,
		Text = "🐟 Fish Tank",
		ZIndex = 6,
		Parent = bar,
	})
	self.pointsLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.22),
		Size = UDim2.fromScale(0.4, 0.56),
		FontFace = FONT_BOLD,
		TextColor3 = Color3.fromRGB(255, 200, 90),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		ZIndex = 6,
		Parent = bar,
	})
	text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.8, 0.06),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 225, 255),
		Text = "Click a fish while it jumps for +10 points!",
		ZIndex = 5,
		Parent = page,
	})

	-- current jump from the server
	self.jump = FishApp.readJump()
	self.caughtId = nil
	workspace:GetAttributeChangedSignal("FishJumpId"):Connect(function()
		self.jump = FishApp.readJump()
	end)

	view.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_tapped(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	task.defer(function()
		local stats = player:WaitForChild("leaderstats", 60)
		local value = stats and stats:WaitForChild("Points", 60)
		if value then
			value.Changed:Connect(function()
				self:_refresh()
			end)
		end
		self:_refresh()
	end)

	RunService.RenderStepped:Connect(function()
		if page.Visible and page.AbsoluteSize.X > 0 then
			self:_animate()
		end
	end)
	return self
end

-- copy the real tank into the view, centred, and point the camera at it
function FishApp:_loadTank()
	local tank = workspace:WaitForChild("fish_tank_test", 120)
	if not tank then
		return
	end
	local bowl = tank:IsA("BasePart") and tank or tank:FindFirstChildWhichIsA("BasePart", true)
	while not bowl do
		tank.DescendantAdded:Wait()
		bowl = tank:FindFirstChildWhichIsA("BasePart", true)
	end
	local copy = bowl:Clone()
	for _, child in ipairs(copy:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CFrame = CFrame.new()
	copy.Parent = self.world
	self.bowl = copy
	local size = copy.Size
	self.radius = math.max(size.X, size.Z) / 2
	self.top = size.Y / 2
	-- straight from the side, level with the middle of the leap, so it looks
	-- 2D; the whole bowl and the top of the leap fit between header and hint
	local r = self.radius
	self.camera.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.48, r * 13.9), Vector3.new(0, r * 0.48, 0))
end

function FishApp:_refresh()
	local p = points()
	self.pointsLabel.Text = if p then ("⭐ " .. p .. " points") else ""
end

function FishApp:_animate()
	if not self.bowl then
		return
	end
	self.bowl.CFrame = CFrame.Angles(0, FishApp.spin(), 0)
	local jump = self.jump
	local t = FishApp.progress(jump)
	local spots = {}
	if t >= 0 and t <= 1 then
		-- on the tablet the leap always goes across the screen (left to right
		-- or right to left), so you see the fish side-on
		local across = { fish = jump.fish, angle = if math.cos(jump.angle) >= 0 then 0 else math.pi }
		spots = FishApp.school(across, t, Vector3.zero, self.radius, self.top)
	end
	for i, fish in ipairs(self.fishes) do
		fish.CFrame = spots[i] or CFrame.new(0, -5000, 0)
		local faded = jump and self.caughtId == jump.id
		for _, decal in ipairs(fish:GetChildren()) do
			if decal:IsA("Decal") then
				decal.Transparency = if faded then 0.5 else 0
			end
		end
	end
end

-- the ray from the view's camera through a point on the view
function FishApp:_ray(screen: Vector2): (Vector3, Vector3)
	local view = self.view
	local rel = screen - view.AbsolutePosition
	local w, h = view.AbsoluteSize.X, view.AbsoluteSize.Y
	local nx = rel.X / w * 2 - 1
	local ny = 1 - rel.Y / h * 2
	local tanHalf = math.tan(math.rad(self.camera.FieldOfView) / 2)
	local dir = self.camera.CFrame:VectorToWorldSpace(Vector3.new(nx * tanHalf * w / h, ny * tanHalf, -1))
	return self.camera.CFrame.Position, dir.Unit
end

function FishApp:_tapped(screen: Vector2)
	local jump = self.jump
	if not jump or self.caughtId == jump.id then
		return
	end
	local t = FishApp.progress(jump)
	if t < 0 or t > 1 then
		return
	end
	-- the tablet's screen ignores the top bar inset; depending on the device an
	-- input's position may or may not include it, so try both
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = self.fishes
	local hit
	for _, shift in ipairs({ 0, GuiService:GetGuiInset().Y }) do
		local origin, dir = self:_ray(screen + Vector2.new(0, shift))
		hit = self.world:Raycast(origin, dir * 2000, params)
		if hit then
			screen += Vector2.new(0, shift)
			break
		end
	end
	if not hit then
		return
	end
	self.caughtId = jump.id
	local where = UDim2.fromOffset(screen.X - self.page.AbsolutePosition.X, screen.Y - self.page.AbsolutePosition.Y)
	task.spawn(function()
		local gained = FishApp.catch(jump.id)
		local label = text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = where,
			Size = UDim2.fromScale(0.3, 0.09),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = FONT_HEAVY,
			TextColor3 = if gained > 0 then Color3.fromRGB(255, 220, 90) else Color3.fromRGB(220, 230, 240),
			TextStrokeTransparency = 0.3,
			Text = if gained > 0 then ("+" .. gained .. " points!") else "Too slow!",
			ZIndex = 7,
			Parent = self.page,
		})
		TweenService:Create(label, TweenInfo.new(1.2), {
			Position = where - UDim2.fromScale(0, 0.15),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(1.3, function()
			label:Destroy()
		end)
	end)
end

return FishApp
