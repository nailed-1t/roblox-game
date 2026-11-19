-- The tablet's Fish Tank app: an aquarium where the fish leaps out from the
-- edges of the screen whenever the server announces a jump (see the
-- FishTank server script). Tap it while it's in the air for 10 points.
-- Also used by the 3D fish (FishTank3D) for the picture and for catching.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FishApp = {}
FishApp.__index = FishApp

FishApp.IMAGE = "rbxassetid://84321219156286" -- assets/jumping_fish.png (383x110)
local ASPECT = 383 / 110

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
		BackgroundColor3 = Color3.fromRGB(20, 70, 130),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Visible = false,
		Parent = pages,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 190, 240)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(30, 110, 190)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 50, 110)),
			}),
		}),
	})
	self.page = page

	-- light rays from the top
	for i, x in ipairs({ 0.18, 0.42, 0.7 }) do
		new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, -0.1),
			Size = UDim2.fromScale(0.08 + i * 0.02, 0.9),
			Rotation = 12,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Parent = page,
		}, {
			new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
	end

	-- sand, rocks and seaweed at the bottom
	new("Frame", {
		Name = "Sand",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.12),
		BackgroundColor3 = Color3.fromRGB(214, 186, 128),
		BorderSizePixel = 0,
		Parent = page,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(232, 206, 150), Color3.fromRGB(170, 140, 90)),
		}),
	})
	for i, info in ipairs({ { 0.12, 0.09, 0.1 }, { 0.8, 0.12, 0.08 }, { 0.55, 0.07, 0.06 } }) do
		new("Frame", {
			Name = "Rock" .. i,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(info[1], 0.93),
			Size = UDim2.fromScale(info[2], info[3]),
			BackgroundColor3 = Color3.fromRGB(96, 104, 120),
			BorderSizePixel = 0,
			Parent = page,
		}, { corner(0.5) })
	end
	self.weeds = {}
	for i, x in ipairs({ 0.06, 0.2, 0.34, 0.66, 0.9 }) do
		local weed = new("Frame", {
			Name = "Weed" .. i,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, 0.92),
			Size = UDim2.fromScale(0.025, 0.25 + (i % 3) * 0.08),
			BackgroundColor3 = Color3.fromRGB(60, 170, 90),
			BorderSizePixel = 0,
			Parent = page,
		}, { corner(0.5) })
		table.insert(self.weeds, weed)
	end

	-- bubbles drifting up
	self.bubbles = {}
	local rng = Random.new()
	for i = 1, 14 do
		local size = rng:NextNumber(0.012, 0.03)
		local b = new("Frame", {
			Name = "Bubble" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(size, size),
			BackgroundColor3 = Color3.fromRGB(220, 245, 255),
			BackgroundTransparency = 0.55,
			Parent = page,
		}, { corner(0.5), new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
		table.insert(self.bubbles, { frame = b, x = rng:NextNumber(0.03, 0.97), speed = rng:NextNumber(0.05, 0.14), phase = rng:NextNumber(0, 1) })
	end

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
	self.hint = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.8, 0.06),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(60, 40, 20),
		Text = "Click the fish while it jumps for +10 points!",
		ZIndex = 5,
		Parent = page,
	})

	-- the fish
	local fish = new("ImageButton", {
		Name = "Fish",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundTransparency = 1,
		Image = FishApp.IMAGE,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 4,
		Parent = page,
	}, { new("UIAspectRatioConstraint", { AspectRatio = ASPECT }) })
	self.fish = fish
	fish.Activated:Connect(function()
		self:_tapped()
	end)

	-- current jump from the server
	self.jump = nil
	self.caughtId = nil
	local function readJump()
		local id = workspace:GetAttribute("FishJumpId")
		if id then
			self.jump = {
				id = id,
				at = workspace:GetAttribute("FishJumpAt") or 0,
				length = workspace:GetAttribute("FishJumpLength") or 2.4,
				edge = workspace:GetAttribute("FishJumpEdge") or 0,
				pos = workspace:GetAttribute("FishJumpPos") or 0.5,
			}
		end
	end
	readJump()
	workspace:GetAttributeChangedSignal("FishJumpId"):Connect(readJump)

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

	self.started = os.clock()
	RunService.RenderStepped:Connect(function()
		if page.Visible then
			self:_animate()
		end
	end)
	return self
end

function FishApp:_refresh()
	local p = points()
	self.pointsLabel.Text = if p then ("⭐ " .. p .. " points") else ""
end

-- where the fish is at time t (0..1) of its jump, plus its tilt
local function path(edge: number, pos: number, t: number): (Vector2, number)
	local h = math.sin(t * math.pi) -- 0 -> 1 -> 0
	local slide = (t - 0.5) * 0.3
	local p
	if edge == 0 then -- up from the bottom
		p = Vector2.new(pos + slide, 1.15 - h * 0.75)
	elseif edge == 1 then -- in from the left
		p = Vector2.new(-0.18 + h * 0.5, pos + slide)
	elseif edge == 2 then -- in from the right
		p = Vector2.new(1.18 - h * 0.5, pos - slide)
	else -- down from the top
		p = Vector2.new(pos - slide, -0.15 + h * 0.6)
	end
	return p, h
end

function FishApp:_animate()
	local t = os.clock() - self.started
	-- bubbles and swaying weed
	for _, b in ipairs(self.bubbles) do
		local y = 1 - ((t * b.speed + b.phase) % 1) * 1.1
		b.frame.Position = UDim2.fromScale(b.x + math.sin(t * 2 + b.phase * 6) * 0.01, y)
	end
	for i, w in ipairs(self.weeds) do
		w.Rotation = math.sin(t * 1.2 + i) * 6
	end
	-- the fish
	local jump = self.jump
	local u = if jump then (workspace:GetServerTimeNow() - jump.at) / jump.length else -1
	if u < 0 or u > 1 then
		self.fish.Visible = false
		return
	end
	local p = path(jump.edge, jump.pos, u)
	local q = path(jump.edge, jump.pos, math.min(u + 0.02, 1.02))
	local d = q - p
	self.fish.Visible = true
	self.fish.Position = UDim2.fromScale(p.X, p.Y)
	-- head is on the left of the picture, so point the left end along the motion
	local angle = math.deg(math.atan2(d.Y * 0.62, d.X)) -- screen is wider than tall
	self.fish.Rotation = angle + 180
	if d.X > 0 then
		-- moving right: flip it over so it isn't upside down
		self.fish.Rotation = angle
		self.fish.ImageRectOffset = Vector2.new(383, 0)
		self.fish.ImageRectSize = Vector2.new(-383, 110)
	else
		self.fish.ImageRectOffset = Vector2.zero
		self.fish.ImageRectSize = Vector2.zero
	end
	self.fish.ImageTransparency = if self.caughtId == jump.id then 0.6 else 0
end

function FishApp:_tapped()
	local jump = self.jump
	if not jump or self.caughtId == jump.id then
		return
	end
	self.caughtId = jump.id
	local where = self.fish.Position
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
