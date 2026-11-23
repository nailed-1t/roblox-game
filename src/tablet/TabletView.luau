-- Builds and draws the tablet's screen: device frame, status bar, home
-- screen, the Chess app (lobby + board) and the Shop app, plus notification
-- banners. It only draws; TabletUI (the controller) decides what to show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("TabletShared")
local PieceArt = require(shared:WaitForChild("PieceArt"))
local ShopItems = require(shared:WaitForChild("ShopItems"))
local TabletArt = require(shared:WaitForChild("TabletArt"))
local Minesweeper = require(shared:WaitForChild("Minesweeper"))
local Snake = require(shared:WaitForChild("Snake"))
local FishApp = require(shared:WaitForChild("FishApp"))
local ChimeApp = require(shared:WaitForChild("ChimeApp"))

local TabletView = {}
TabletView.__index = TabletView

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_MED = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)

local C = {
	bezel = Color3.fromRGB(18, 18, 22),
	text = Color3.fromRGB(245, 246, 250),
	sub = Color3.fromRGB(170, 176, 192),
	card = Color3.fromRGB(28, 31, 42),
	cardLine = Color3.fromRGB(60, 66, 84),
	blue = Color3.fromRGB(64, 132, 255),
	green = Color3.fromRGB(52, 199, 89),
	red = Color3.fromRGB(255, 69, 58),
	gray = Color3.fromRGB(72, 76, 92),
	light = Color3.fromRGB(238, 216, 182),
	dark = Color3.fromRGB(176, 133, 96),
	selected = Color3.fromRGB(246, 230, 92),
	lastMove = Color3.fromRGB(205, 210, 106),
	check = Color3.fromRGB(235, 80, 70),
}

---------------------------------------------------------------- helpers

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, ch in ipairs(children) do
			ch.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: UDim): UICorner
	return new("UICorner", { CornerRadius = radius })
end

local function stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = C.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return new("TextLabel", defaults)
end

local function button(props: { [string]: any }, bg: Color3, textColor: Color3?): TextButton
	local b = new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
		FontFace = FONT_BOLD,
		TextColor3 = textColor or C.text,
		TextScaled = true,
	}, { corner(UDim.new(0.3, 0)), new("UIPadding", {
		PaddingTop = UDim.new(0.22, 0),
		PaddingBottom = UDim.new(0.22, 0),
		PaddingLeft = UDim.new(0.08, 0),
		PaddingRight = UDim.new(0.08, 0),
	}) })
	for k, v in pairs(props) do
		(b :: any)[k] = v
	end
	return b
end

local function clear(frame: Instance, keep: { [string]: boolean }?)
	for _, ch in ipairs(frame:GetChildren()) do
		if not (ch:IsA("UIListLayout") or ch:IsA("UIGridLayout") or ch:IsA("UIPadding") or ch:IsA("UICorner") or ch:IsA("UIStroke")) then
			if not (keep and keep[ch.Name]) then
				ch:Destroy()
			end
		end
	end
end

---------------------------------------------------------------- construction

-- options.fullscreen: fill the parent exactly (for drawing onto the tablet
-- model's own screen) instead of drawing a device frame around the screen
function TabletView.new(parent: Instance, options: { fullscreen: boolean? }?)
	local self = setmetatable({}, TabletView)
	self.callbacks = {}
	local fullscreen = options ~= nil and options.fullscreen == true

	-- device body (landscape)
	local device = new("Frame", {
		Name = "Device",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = C.bezel,
		Parent = parent,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1.55 }),
		corner(UDim.new(0.06, 0)),
		stroke(Color3.fromRGB(90, 92, 100), 2, 0.2),
	})
	self.device = device
	if fullscreen then
		device.Size = UDim2.fromScale(1, 1)
		device.BackgroundTransparency = 1
		device:FindFirstChildOfClass("UIAspectRatioConstraint"):Destroy()
		device:FindFirstChildOfClass("UIStroke"):Destroy()
		device:FindFirstChildOfClass("UICorner"):Destroy()
	end
	-- front camera on the left bezel
	new("Frame", {
		Name = "Camera",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.0145, 0.5),
		Size = UDim2.fromScale(0.008, 0.0125),
		BackgroundColor3 = Color3.fromRGB(40, 44, 60),
		Visible = not fullscreen,
		Parent = device,
	}, { corner(UDim.new(0.5, 0)) })

	local screen = new("Frame", {
		Name = "Screen",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.955, 0.93),
		BackgroundColor3 = Color3.fromRGB(10, 12, 20),
		ClipsDescendants = true,
		Parent = device,
	}, { corner(UDim.new(0.035, 0)) })
	self.screen = screen
	if fullscreen then
		screen.Size = UDim2.fromScale(1, 1)
		screen:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.02, 0)
	end

	-- wallpaper
	new("Frame", {
		Name = "Wallpaper",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = screen,
	}, {
		new("UIGradient", {
			Rotation = 35,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 52, 120)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 120, 150)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(104, 58, 160)),
			}),
		}),
	})

	self:_buildStatusBar(screen)

	-- pages live below the status bar
	local pages = new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.06),
		Size = UDim2.fromScale(1, 0.94),
		Parent = screen,
	})
	self.pages = {
		home = self:_buildHome(pages),
		chess = self:_buildChess(pages),
		shop = self:_buildShop(pages),
		mines = Minesweeper.new(pages).page,
		snake = Snake.new(pages).page,
		fish = FishApp.new(pages).page,
		chime = ChimeApp.new(pages).page,
	}

	self:_buildHomeIndicator(screen)
	self:_buildBanner(screen)
	self:showPage("home")
	return self
end

function TabletView:on(name: string, fn: (...any) -> ())
	self.callbacks[name] = fn
end

function TabletView:_fire(name: string, ...)
	local fn = self.callbacks[name]
	if fn then
		fn(...)
	end
end

function TabletView:_buildStatusBar(screen: Frame)
	local bar = new("Frame", {
		Name = "StatusBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.06),
		ZIndex = 5,
		Parent = screen,
	})
	self.timeLabel = label({
		Name = "Time",
		Position = UDim2.fromScale(0.03, 0.2),
		Size = UDim2.fromScale(0.2, 0.6),
		FontFace = FONT_BOLD,
		Text = "12:00",
		ZIndex = 5,
		Parent = bar,
	})
	label({
		Name = "Signal",
		Position = UDim2.fromScale(0.78, 0.2),
		Size = UDim2.fromScale(0.13, 0.6),
		Text = "📶  100%",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = bar,
	})
	local battery = new("Frame", {
		Name = "Battery",
		Position = UDim2.fromScale(0.92, 0.28),
		Size = UDim2.fromScale(0.04, 0.44),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = bar,
	}, { corner(UDim.new(0.3, 0)), stroke(C.text, 1.2, 0.2) })
	new("Frame", {
		Position = UDim2.fromScale(0.1, 0.15),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = battery,
	}, { corner(UDim.new(0.2, 0)) })
end

-- puts a drawn app icon (from the art sheet) on a button; false if no sheet
local function iconArt(button: GuiButton, art: string?): boolean
	local img = art and TabletArt.image(art)
	if not img then
		return false
	end
	button.BackgroundTransparency = 1
	local grad = button:FindFirstChildOfClass("UIGradient")
	if grad then
		grad:Destroy()
	end
	img.Size = UDim2.fromScale(1, 1)
	img.Parent = button
	return true
end

local function appIcon(parent: Instance, name: string, colors: { Color3 }, glyph: string?, piece: string?, order: number, art: string?): TextButton
	local holder = new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	local icon = new("TextButton", {
		Name = "Icon",
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = holder,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(UDim.new(0.24, 0)),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(colors[1], colors[2]),
		}),
	})
	if iconArt(icon, art) then
		-- drawn icon
	elseif piece then
		local pieceArt = PieceArt.make(piece)
		pieceArt.Size = UDim2.fromScale(0.72, 0.72)
		pieceArt.AnchorPoint = Vector2.new(0.5, 0.5)
		pieceArt.Position = UDim2.fromScale(0.5, 0.5)
		pieceArt.Parent = icon
	elseif glyph then
		label({
			Size = UDim2.fromScale(0.6, 0.6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = glyph,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = icon,
		})
	end
	label({
		Name = "Name",
		Position = UDim2.fromScale(0, 0.82),
		Size = UDim2.fromScale(1, 0.18),
		Text = name,
		FontFace = FONT_MED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = holder,
	})
	return icon
end

function TabletView:_buildHome(pages: Frame): Frame
	local home = new("Frame", { Name = "Home", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pages })

	-- widget: time + Deepwoken update counter
	local widget = new("Frame", {
		Name = "Widget",
		Position = UDim2.fromScale(0.04, 0.05),
		Size = UDim2.fromScale(0.36, 0.42),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		Parent = home,
	}, { corner(UDim.new(0.12, 0)), stroke(Color3.new(1, 1, 1), 1, 0.8) })
	self.widgetTime = label({
		Position = UDim2.fromScale(0.08, 0.08),
		Size = UDim2.fromScale(0.84, 0.36),
		FontFace = FONT_BOLD,
		Text = "12:00",
		Parent = widget,
	})
	self.widgetDate = label({
		Position = UDim2.fromScale(0.08, 0.44),
		Size = UDim2.fromScale(0.84, 0.12),
		TextColor3 = C.sub,
		Text = "",
		Parent = widget,
	})
	label({
		Position = UDim2.fromScale(0.08, 0.64),
		Size = UDim2.fromScale(0.84, 0.1),
		TextColor3 = C.sub,
		Text = "SINCE DEEPWOKEN LAST UPDATED",
		FontFace = FONT_MED,
		Parent = widget,
	})
	self.widgetCounter = label({
		Position = UDim2.fromScale(0.08, 0.76),
		Size = UDim2.fromScale(0.84, 0.15),
		Text = "--d --h --m --s",
		FontFace = FONT_BOLD,
		TextColor3 = Color3.fromRGB(120, 220, 255),
		Parent = widget,
	})

	-- app grid
	local grid = new("Frame", {
		Name = "Apps",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.45, 0.05),
		Size = UDim2.fromScale(0.5, 0.6),
		Parent = home,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.fromScale(0.22, 0.42),
			CellPadding = UDim2.fromScale(0.04, 0.06),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local chessIcon = appIcon(grid, "Chess", { Color3.fromRGB(196, 148, 92), Color3.fromRGB(120, 78, 40) }, nil, "wN", 1, "appChess")
	local shopIcon = appIcon(grid, "Shop", { Color3.fromRGB(255, 159, 67), Color3.fromRGB(238, 82, 120) }, "🛍️", nil, 2, "appShop")
	local minesIcon = appIcon(grid, "Minesweeper", { Color3.fromRGB(96, 110, 150), Color3.fromRGB(40, 46, 70) }, "💣", nil, 3, "appMines")
	local snakeIcon = appIcon(grid, "Snake", { Color3.fromRGB(120, 220, 110), Color3.fromRGB(30, 120, 60) }, "🐍", nil, 4)
	local fishIcon = appIcon(grid, "Fish Tank", { Color3.fromRGB(110, 200, 255), Color3.fromRGB(20, 80, 170) }, "🐟", nil, 5)
	local chimeIcon = appIcon(grid, "Chime of Conflict", { Color3.fromRGB(230, 80, 110), Color3.fromRGB(60, 16, 40) }, "🔔", nil, 6)
	self.appIcons = { chess = chessIcon, shop = shopIcon, mines = minesIcon, snake = snakeIcon, fish = fishIcon, chime = chimeIcon }
	chessIcon.Activated:Connect(function()
		self:_fire("openApp", "chess")
	end)
	shopIcon.Activated:Connect(function()
		self:_fire("openApp", "shop")
	end)
	minesIcon.Activated:Connect(function()
		self:_fire("openApp", "mines")
	end)
	snakeIcon.Activated:Connect(function()
		self:_fire("openApp", "snake")
	end)
	fishIcon.Activated:Connect(function()
		self:_fire("openApp", "fish")
	end)
	chimeIcon.Activated:Connect(function()
		self:_fire("openApp", "chime")
	end)

	-- dock
	local dock = new("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.4, 0.22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Parent = home,
	}, {
		corner(UDim.new(0.25, 0)),
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.06, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, info in ipairs({
		{ "chess", { Color3.fromRGB(196, 148, 92), Color3.fromRGB(120, 78, 40) }, nil, "wN", "appChess" },
		{ "shop", { Color3.fromRGB(255, 159, 67), Color3.fromRGB(238, 82, 120) }, "🛍️", nil, "appShop" },
		{ "mines", { Color3.fromRGB(96, 110, 150), Color3.fromRGB(40, 46, 70) }, "💣", nil, "appMines" },
	}) do
		local b = new("TextButton", {
			Name = info[1],
			Text = "",
			LayoutOrder = i,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.24, 0.75),
			Parent = dock,
		}, {
			new("UIAspectRatioConstraint", { AspectRatio = 1 }),
			corner(UDim.new(0.24, 0)),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(info[2][1], info[2][2]) }),
		})
		if iconArt(b, info[5]) then
			-- drawn icon
		elseif info[4] then
			local art = PieceArt.make(info[4])
			art.Size = UDim2.fromScale(0.72, 0.72)
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			art.Parent = b
		else
			label({
				Size = UDim2.fromScale(0.6, 0.6),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Text = info[3],
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = b,
			})
		end
		b.Activated:Connect(function()
			self:_fire("openApp", info[1])
		end)
	end
	self.dock = dock
	return home
end

-- During a Chime of Conflict match only some apps are allowed; nil = all.
function TabletView:setAllowedApps(allowed: { [string]: boolean }?)
	self.allowedApps = allowed
	for key, icon in pairs(self.appIcons or {}) do
		-- hide the whole slot (icon and name) so the grid closes up
		local slot = icon.Parent :: GuiObject
		slot.Visible = allowed == nil or allowed[key] == true
	end
	if self.dock then
		self.dock.Visible = allowed == nil
	end
	if allowed and self.currentPage and self.currentPage ~= "home" and not allowed[self.currentPage] then
		self:showPage("home")
	end
end

function TabletView:_buildHomeIndicator(screen: Frame)
	local hit = new("TextButton", {
		Name = "HomeIndicator",
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.3, 0.045),
		ZIndex = 20,
		Parent = screen,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.75, 0.22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		ZIndex = 20,
		Parent = hit,
	}, { corner(UDim.new(0.5, 0)) })
	hit.Activated:Connect(function()
		self:_fire("home")
	end)
end

---------------------------------------------------------------- pages

function TabletView:showPage(name: string)
	for key, page in pairs(self.pages) do
		page.Visible = key == name
	end
	self.currentPage = name
end

-- app page with a title bar
local function appPage(pages: Frame, name: string, title: string, subtitle: string): (Frame, Frame, TextLabel)
	local page = new("Frame", {
		Name = name,
		BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	})
	label({
		Name = "Title",
		Position = UDim2.fromScale(0.04, 0.03),
		Size = UDim2.fromScale(0.5, 0.08),
		FontFace = FONT_BOLD,
		Text = title,
		Parent = page,
	})
	local sub = label({
		Name = "Subtitle",
		Position = UDim2.fromScale(0.04, 0.115),
		Size = UDim2.fromScale(0.6, 0.045),
		TextColor3 = C.sub,
		Text = subtitle,
		Parent = page,
	})
	local body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.74),
		Parent = page,
	})
	return page, body, sub
end

---------------------------------------------------------------- chess

-- board colour themes (light square, dark square, coordinate text)
TabletView.BOARD_THEMES = {
	{ key = "wood", name = "Wood", light = Color3.fromRGB(238, 216, 182), dark = Color3.fromRGB(176, 133, 96), coord = Color3.fromRGB(90, 60, 40) },
	{ key = "green", name = "Green", light = Color3.fromRGB(235, 236, 208), dark = Color3.fromRGB(115, 149, 82), coord = Color3.fromRGB(70, 90, 50) },
	{ key = "blue", name = "Blue", light = Color3.fromRGB(222, 227, 230), dark = Color3.fromRGB(140, 162, 173), coord = Color3.fromRGB(70, 90, 110) },
	{ key = "gray", name = "Gray", light = Color3.fromRGB(200, 200, 204), dark = Color3.fromRGB(120, 120, 128), coord = Color3.fromRGB(60, 60, 66) },
}
local THEME_BY_KEY = {}
for _, t in ipairs(TabletView.BOARD_THEMES) do
	THEME_BY_KEY[t.key] = t
end

TabletView.TIME_CHOICES = {
	{ key = "bullet", name = "Bullet 1|0" },
	{ key = "blitz", name = "Blitz 3|2" },
	{ key = "rapid", name = "Rapid 10|0" },
	{ key = "none", name = "No clock" },
}
TabletView.VARIANT_CHOICES = {
	{ key = "standard", name = "Standard" },
	{ key = "chess960", name = "Chess960" },
	{ key = "koth", name = "King of the Hill" },
	{ key = "threecheck", name = "3-Check" },
}
-- on/off settings, in the order they are listed
TabletView.TOGGLES = {
	{ key = "legalMoves", name = "Show legal moves" },
	{ key = "lastMove", name = "Highlight last move" },
	{ key = "coordinates", name = "Show coordinates" },
	{ key = "premoves", name = "Allow premoves" },
	{ key = "autoQueen", name = "Always promote to queen" },
	{ key = "confirmResign", name = "Tap twice to resign" },
	{ key = "flip", name = "Flip the board" },
}

local PREMOVE = Color3.fromRGB(230, 90, 90)

-- a row of choice chips; returns { [key] = button }
local function chipRow(parent: Instance, y: number, title: string, choices, onPick: (string) -> ()): { [string]: TextButton }
	label({ Position = UDim2.fromScale(0.04, y + 0.012), Size = UDim2.fromScale(0.1, 0.05), TextColor3 = C.sub, Text = title, Parent = parent })
	local chips = {}
	for i, choice in ipairs(choices) do
		local b = button({
			Name = choice.key,
			Text = choice.name,
			Position = UDim2.fromScale(0.14 + (i - 1) * 0.2, y),
			Size = UDim2.fromScale(0.19, 0.07),
		}, C.card, C.text)
		b.Parent = parent
		b.Activated:Connect(function()
			onPick(choice.key)
		end)
		chips[choice.key] = b
	end
	return chips
end

function TabletView:_buildChess(pages: Frame): Frame
	local page = new("Frame", {
		Name = "Chess",
		BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	})
	self.chessPage = page

	-- lobby -------------------------------------------------------------
	local lobby = new("Frame", { Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = page })
	label({ Position = UDim2.fromScale(0.04, 0.025), Size = UDim2.fromScale(0.5, 0.075), FontFace = FONT_BOLD, Text = "Chess", Parent = lobby })
	label({
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.7, 0.04),
		TextColor3 = C.sub,
		Text = "Pick a mode, then challenge someone or the computer. Win = +50 points",
		Parent = lobby,
	})
	local gear = button({ Name = "Settings", Text = "⚙ Settings", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.96, 0.03), Size = UDim2.fromScale(0.17, 0.07) }, C.card)
	gear.Parent = lobby
	gear.Activated:Connect(function()
		self:_fire("settings")
	end)

	self.timeChips = chipRow(lobby, 0.16, "Time", TabletView.TIME_CHOICES, function(key)
		self:_fire("pickTime", key)
	end)
	self.variantChips = chipRow(lobby, 0.245, "Variant", TabletView.VARIANT_CHOICES, function(key)
		self:_fire("pickVariant", key)
	end)

	local playersCard = new("Frame", {
		Name = "PlayersCard",
		Position = UDim2.fromScale(0.04, 0.345),
		Size = UDim2.fromScale(0.54, 0.62),
		BackgroundColor3 = C.card,
		Parent = lobby,
	}, { corner(UDim.new(0.05, 0)), stroke(C.cardLine, 1, 0.3) })
	label({ Position = UDim2.fromScale(0.05, 0.035), Size = UDim2.fromScale(0.9, 0.075), FontFace = FONT_BOLD, Text = "Play", Parent = playersCard })
	self.playerList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.03, 0.14),
		Size = UDim2.fromScale(0.94, 0.83),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = playersCard,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local invitesCard = new("Frame", {
		Name = "InvitesCard",
		Position = UDim2.fromScale(0.61, 0.345),
		Size = UDim2.fromScale(0.35, 0.33),
		BackgroundColor3 = C.card,
		Parent = lobby,
	}, { corner(UDim.new(0.08, 0)), stroke(C.cardLine, 1, 0.3) })
	label({ Position = UDim2.fromScale(0.07, 0.05), Size = UDim2.fromScale(0.86, 0.14), FontFace = FONT_BOLD, Text = "Challenges", Parent = invitesCard })
	self.inviteList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.05, 0.23),
		Size = UDim2.fromScale(0.9, 0.52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = invitesCard,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.outgoingLabel = label({
		Name = "Outgoing",
		Position = UDim2.fromScale(0.07, 0.77),
		Size = UDim2.fromScale(0.86, 0.2),
		TextColor3 = C.sub,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = invitesCard,
	})

	local liveCard = new("Frame", {
		Name = "LiveCard",
		Position = UDim2.fromScale(0.61, 0.695),
		Size = UDim2.fromScale(0.35, 0.27),
		BackgroundColor3 = C.card,
		Parent = lobby,
	}, { corner(UDim.new(0.08, 0)), stroke(C.cardLine, 1, 0.3) })
	label({ Position = UDim2.fromScale(0.07, 0.06), Size = UDim2.fromScale(0.86, 0.17), FontFace = FONT_BOLD, Text = "👁 Live games", Parent = liveCard })
	self.liveList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.05, 0.29),
		Size = UDim2.fromScale(0.9, 0.66),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = liveCard,
	}, { new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.lobby = lobby

	-- game --------------------------------------------------------------
	local gameFrame = new("Frame", { Name = "Game", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = page })
	local board = new("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.03, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = Color3.fromRGB(60, 40, 26),
		Parent = gameFrame,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
		corner(UDim.new(0.015, 0)),
		new("UIPadding", {
			PaddingTop = UDim.new(0.012, 0),
			PaddingBottom = UDim.new(0.012, 0),
			PaddingLeft = UDim.new(0.012, 0),
			PaddingRight = UDim.new(0.012, 0),
		}),
	})
	self.squares = {} -- [row][col] in screen order (row 1 = top)
	for row = 1, 8 do
		self.squares[row] = {}
		for col = 1, 8 do
			local sq = new("TextButton", {
				Name = string.format("Sq%d_%d", row, col),
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Position = UDim2.fromScale((col - 1) / 8, (row - 1) / 8),
				Size = UDim2.fromScale(1 / 8, 1 / 8),
				BackgroundColor3 = if (row + col) % 2 == 0 then C.light else C.dark,
				Parent = board,
			})
			local hl = new("Frame", {
				Name = "Highlight",
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
				Parent = sq,
			})
			local dot = new("Frame", {
				Name = "Dot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.3, 0.3),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BackgroundTransparency = 0.6,
				Visible = false,
				ZIndex = 3,
				Parent = sq,
			}, { corner(UDim.new(0.5, 0)) })
			local ring = new("Frame", {
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.92, 0.92),
				BackgroundTransparency = 1,
				Visible = false,
				ZIndex = 3,
				Parent = sq,
			}, { corner(UDim.new(0.5, 0)), stroke(Color3.fromRGB(30, 30, 30), 3, 0.45) })
			local pieceHolder = new("Frame", {
				Name = "PieceHolder",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.86, 0.86),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Parent = sq,
			})
			-- coordinates on the edge squares
			if col == 1 then
				label({ Name = "Rank", Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.3, 0.25), Text = "", TextTransparency = 0.25, TextColor3 = Color3.fromRGB(90, 60, 40), FontFace = FONT_BOLD, Parent = sq })
			end
			if row == 8 then
				label({ Name = "File", Position = UDim2.fromScale(0.68, 0.72), Size = UDim2.fromScale(0.3, 0.25), Text = "", TextTransparency = 0.25, TextColor3 = Color3.fromRGB(90, 60, 40), FontFace = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right, Parent = sq })
			end
			self.squares[row][col] = { button = sq, highlight = hl, dot = dot, ring = ring, piece = pieceHolder, code = nil }
			sq.Activated:Connect(function()
				self:_fire("square", row, col)
			end)
			-- right-click cancels a premove (like chess.com)
			sq.MouseButton2Click:Connect(function()
				self:_fire("cancelPremove")
			end)
		end
	end
	self.board = board

	-- side panel
	local side = new("Frame", {
		Name = "Side",
		Position = UDim2.fromScale(0.6, 0.04),
		Size = UDim2.fromScale(0.37, 0.92),
		BackgroundTransparency = 1,
		Parent = gameFrame,
	})
	local function playerCard(name: string, y: number)
		local card = new("Frame", {
			Name = name,
			Position = UDim2.fromScale(0, y),
			Size = UDim2.fromScale(1, 0.12),
			BackgroundColor3 = C.card,
			Parent = side,
		}, { corner(UDim.new(0.2, 0)), stroke(C.cardLine, 1, 0.3) })
		local swatch = new("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.04, 0.5),
			Size = UDim2.fromScale(0.09, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = card,
		}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(UDim.new(0.5, 0)), stroke(Color3.fromRGB(120, 120, 120), 1) })
		local nameLabel = label({ Position = UDim2.fromScale(0.17, 0.18), Size = UDim2.fromScale(0.5, 0.38), FontFace = FONT_BOLD, Text = "", Parent = card })
		local tag = label({ Position = UDim2.fromScale(0.17, 0.58), Size = UDim2.fromScale(0.5, 0.26), TextColor3 = C.sub, Text = "", Parent = card })
		local clockBox = new("Frame", {
			Name = "Clock",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.29, 0.72),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			Visible = false,
			Parent = card,
		}, { corner(UDim.new(0.25, 0)) })
		local clockText = label({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
			Text = "",
			Parent = clockBox,
		})
		new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0), Parent = clockBox })
		return { card = card, name = nameLabel, swatch = swatch, tag = tag, clock = clockBox, clockText = clockText }
	end
	self.oppCardInfo = playerCard("Opponent", 0)
	self.meCardInfo = playerCard("You", 0.68)

	self.statusLabel = label({
		Name = "Status",
		Position = UDim2.fromScale(0, 0.135),
		Size = UDim2.fromScale(1, 0.065),
		FontFace = FONT_BOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = side,
	})
	self.modeLabel = label({
		Name = "Mode",
		Position = UDim2.fromScale(0, 0.205),
		Size = UDim2.fromScale(1, 0.04),
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = side,
	})
	local movesCard = new("Frame", {
		Name = "Moves",
		Position = UDim2.fromScale(0, 0.26),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = C.card,
		Parent = side,
	}, { corner(UDim.new(0.06, 0)), stroke(C.cardLine, 1, 0.3) })
	self.moveList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.05, 0.05),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = movesCard,
	}, { new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- buttons: [Resign] [Draw] [⚙] while playing; [Back]/[Stop watching] [⚙] otherwise
	self.resignButton = button({ Name = "Resign", Text = "Resign", Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(0.41, 0.1) }, Color3.fromRGB(70, 30, 34), Color3.fromRGB(255, 120, 110))
	self.resignButton.Parent = side
	self.resignButton.Activated:Connect(function()
		self:_fire("resign")
	end)
	self.drawButton = button({ Name = "Draw", Text = "Offer draw", Position = UDim2.fromScale(0.44, 0.84), Size = UDim2.fromScale(0.39, 0.1) }, C.gray)
	self.drawButton.Parent = side
	self.drawButton.Activated:Connect(function()
		self:_fire("draw")
	end)
	self.backButton = button({ Name = "Back", Text = "Back to lobby", Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(0.83, 0.1), Visible = false }, C.blue)
	self.backButton.Parent = side
	self.backButton.Activated:Connect(function()
		self:_fire("leaveGame")
	end)
	local gameGear = button({ Name = "Settings", Text = "⚙", Position = UDim2.fromScale(0.86, 0.84), Size = UDim2.fromScale(0.14, 0.1) }, C.card)
	gameGear.Parent = side
	gameGear.Activated:Connect(function()
		self:_fire("settings")
	end)

	-- promotion picker
	local promo = new("Frame", {
		Name = "Promotion",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.2),
		BackgroundColor3 = C.card,
		Visible = false,
		ZIndex = 10,
		Parent = board,
	}, { corner(UDim.new(0.15, 0)), stroke(C.cardLine, 2) })
	self.promoButtons = {}
	for i, kind in ipairs({ "Q", "R", "B", "N" }) do
		local b = new("TextButton", {
			Name = kind,
			Text = "",
			BackgroundColor3 = C.light,
			Position = UDim2.fromScale(0.04 + (i - 1) * 0.24, 0.12),
			Size = UDim2.fromScale(0.2, 0.76),
			ZIndex = 11,
			Parent = promo,
		}, { corner(UDim.new(0.2, 0)) })
		b.Activated:Connect(function()
			self:_fire("promote", kind)
		end)
		self.promoButtons[kind] = b
	end
	self.promoFrame = promo
	self.gameFrame = gameFrame

	self:_buildChessSettings(page)
	return page
end

-- the settings panel (over the lobby or the game)
function TabletView:_buildChessSettings(page: Frame)
	local shade = new("TextButton", {
		Name = "SettingsShade",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
		Parent = page,
	})
	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.9),
		BackgroundColor3 = C.card,
		Active = true, -- clicks on the panel don't fall through and close it
		ZIndex = 21,
		Parent = shade,
	}, { corner(UDim.new(0.05, 0)), stroke(C.cardLine, 1, 0.2) })
	local function z(inst)
		inst.ZIndex = 22
		return inst
	end
	z(label({ Position = UDim2.fromScale(0.06, 0.035), Size = UDim2.fromScale(0.6, 0.075), FontFace = FONT_BOLD, Text = "Chess settings", Parent = panel }))
	z(label({ Position = UDim2.fromScale(0.06, 0.135), Size = UDim2.fromScale(0.3, 0.05), TextColor3 = C.sub, Text = "Board", Parent = panel }))
	self.themeChips = {}
	for i, theme in ipairs(TabletView.BOARD_THEMES) do
		local chip = z(new("TextButton", {
			Name = theme.key,
			Text = "",
			AutoButtonColor = true,
			Position = UDim2.fromScale(0.3 + (i - 1) * 0.165, 0.12),
			Size = UDim2.fromScale(0.14, 0.08),
			BackgroundColor3 = theme.dark,
			Parent = panel,
		}, { corner(UDim.new(0.2, 0)) }))
		-- half light, half dark, with the name on top
		z(new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = theme.light, BorderSizePixel = 0, Parent = chip }, { corner(UDim.new(0.2, 0)) }))
		z(label({ Position = UDim2.fromScale(0, 0.25), Size = UDim2.fromScale(1, 0.5), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(20, 20, 24), FontFace = FONT_BOLD, Text = theme.name, Parent = chip }))
		local ring = new("UIStroke", { Color = C.selected, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = chip })
		chip.Activated:Connect(function()
			self:_fire("setting", "theme", theme.key)
		end)
		self.themeChips[theme.key] = ring
	end
	self.toggleSwitches = {}
	for i, t in ipairs(TabletView.TOGGLES) do
		local y = 0.23 + (i - 1) * 0.085
		local row = z(new("TextButton", {
			Name = t.key,
			Text = "",
			AutoButtonColor = true,
			Position = UDim2.fromScale(0.05, y),
			Size = UDim2.fromScale(0.9, 0.072),
			BackgroundColor3 = Color3.fromRGB(38, 42, 56),
			Parent = panel,
		}, { corner(UDim.new(0.25, 0)) }))
		z(label({ Position = UDim2.fromScale(0.04, 0.2), Size = UDim2.fromScale(0.7, 0.6), FontFace = FONT_MED, Text = t.name, Parent = row }))
		local track = z(new("Frame", {
			Name = "Switch",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.11, 0.7),
			BackgroundColor3 = C.gray,
			Parent = row,
		}, { corner(UDim.new(0.5, 0)) }))
		local knob = z(new("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.06, 0.5),
			Size = UDim2.fromScale(0.42, 0.8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = track,
		}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(UDim.new(0.5, 0)) }))
		knob.ZIndex = 23
		row.Activated:Connect(function()
			self:_fire("setting", t.key, nil) -- nil = flip it
		end)
		self.toggleSwitches[t.key] = { track = track, knob = knob }
	end
	local done = button({ Name = "Done", Text = "Done", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.4, 0.1) }, C.blue)
	done.ZIndex = 22
	done.Parent = panel
	done.Activated:Connect(function()
		self:_fire("closeSettings")
	end)
	shade.Activated:Connect(function()
		self:_fire("closeSettings")
	end)
	self.settingsShade = shade
end

function TabletView:showChessSettings(visible: boolean, settings)
	self.settingsShade.Visible = visible
	if not visible or not settings then
		return
	end
	for key, ring in pairs(self.themeChips) do
		ring.Thickness = if settings.theme == key then 3 else 0
	end
	for key, sw in pairs(self.toggleSwitches) do
		local on = settings[key] == true
		sw.track.BackgroundColor3 = if on then C.green else C.gray
		sw.knob.Position = if on then UDim2.fromScale(0.52, 0.5) else UDim2.fromScale(0.06, 0.5)
	end
end

function TabletView:showChessScreen(which: string) -- "lobby" or "game"
	self.lobby.Visible = which == "lobby"
	self.gameFrame.Visible = which == "game"
end

local function avatarCircle(parent: Instance, userId: number, name: string, thumbnails: { [number]: string })
	local holder = new("Frame", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.02, 0.5),
		Size = UDim2.fromScale(0.12, 0.8),
		BackgroundColor3 = C.gray,
		Parent = parent,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(UDim.new(0.5, 0)) })
	label({
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(string.sub(name, 1, 1)),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = FONT_BOLD,
		Parent = holder,
	}, nil)
	local img = thumbnails[userId]
	if img then
		new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = img,
			Parent = holder,
		}, { corner(UDim.new(0.5, 0)) })
	end
end

-- players: { {id, name, state = "free"|"waiting"} }
-- invites: { {from, name, seconds, modeName} }
-- live:    { {id, white, black, modeName, moves, bot} }
-- mode:    { time, variant } picked in the lobby
function TabletView:renderLobby(players, invites, outgoingText: string, thumbnails: { [number]: string }, live, mode)
	for key, chip in pairs(self.timeChips) do
		chip.BackgroundColor3 = if mode and mode.time == key then C.blue else C.card
	end
	for key, chip in pairs(self.variantChips) do
		chip.BackgroundColor3 = if mode and mode.variant == key then C.blue else C.card
	end

	clear(self.playerList)
	-- the computer is always there
	local bot = new("Frame", {
		Name = "Computer",
		LayoutOrder = 0,
		Size = UDim2.new(1, -6, 0, 44),
		BackgroundColor3 = Color3.fromRGB(44, 40, 66),
		Parent = self.playerList,
	}, { corner(UDim.new(0.25, 0)) })
	local botFace = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.02, 0.5),
		Size = UDim2.fromScale(0.12, 0.8),
		BackgroundColor3 = Color3.fromRGB(90, 70, 150),
		Parent = bot,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(UDim.new(0.5, 0)) })
	label({ Size = UDim2.fromScale(1, 1), Text = "🤖", TextXAlignment = Enum.TextXAlignment.Center, Parent = botFace })
	label({ Position = UDim2.fromScale(0.17, 0.25), Size = UDim2.fromScale(0.3, 0.5), FontFace = FONT_MED, Text = "Computer", Parent = bot })
	for i, level in ipairs({ { "easy", "Easy" }, { "medium", "Medium" }, { "hard", "Hard" } }) do
		local b = button({
			Name = level[1],
			Text = level[2],
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97 - (3 - i) * 0.185, 0.5),
			Size = UDim2.fromScale(0.175, 0.72),
		}, Color3.fromRGB(110, 80, 190))
		b.Parent = bot
		b.Activated:Connect(function()
			self:_fire("computer", level[1])
		end)
	end
	if #players == 0 then
		label({
			Name = "Empty",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 34),
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Nobody else is on the train yet",
			Parent = self.playerList,
		})
	end
	for i, p in ipairs(players) do
		local row = new("Frame", {
			Name = "Player" .. p.id,
			LayoutOrder = i + 1,
			Size = UDim2.new(1, -6, 0, 44),
			BackgroundColor3 = Color3.fromRGB(38, 42, 56),
			Parent = self.playerList,
		}, { corner(UDim.new(0.25, 0)) })
		avatarCircle(row, p.id, p.name, thumbnails)
		label({ Position = UDim2.fromScale(0.17, 0.25), Size = UDim2.fromScale(0.5, 0.5), FontFace = FONT_MED, Text = p.name, Parent = row })
		local isWaiting = p.state == "waiting"
		local b = button({
			Name = "Action",
			Text = if isWaiting then "Cancel" else "Challenge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.28, 0.72),
		}, if isWaiting then C.gray else C.blue)
		b.Parent = row
		b.Activated:Connect(function()
			if isWaiting then
				self:_fire("cancelChallenge")
			else
				self:_fire("challenge", p.id)
			end
		end)
	end

	clear(self.inviteList)
	self.inviteCountdowns = {}
	if #invites == 0 then
		label({
			Name = "Empty",
			Size = UDim2.new(1, 0, 0, 26),
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "No challenges yet",
			Parent = self.inviteList,
		})
	end
	for i, inv in ipairs(invites) do
		local row = new("Frame", {
			Name = "Invite" .. inv.from,
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 70),
			BackgroundColor3 = Color3.fromRGB(38, 42, 56),
			Parent = self.inviteList,
		}, { corner(UDim.new(0.18, 0)) })
		label({ Position = UDim2.fromScale(0.06, 0.06), Size = UDim2.fromScale(0.9, 0.26), FontFace = FONT_BOLD, Text = inv.name, Parent = row })
		self.inviteCountdowns[inv.from] = label({
			Position = UDim2.fromScale(0.06, 0.34),
			Size = UDim2.fromScale(0.9, 0.2),
			TextColor3 = C.sub,
			Text = string.format("%s  ·  %ds", inv.modeName or "wants to play", math.max(0, math.ceil(inv.seconds))),
			Parent = row,
		})
		local accept = button({ Text = "Accept", Position = UDim2.fromScale(0.05, 0.6), Size = UDim2.fromScale(0.43, 0.34) }, C.green)
		accept.Parent = row
		local decline = button({ Text = "Decline", Position = UDim2.fromScale(0.52, 0.6), Size = UDim2.fromScale(0.43, 0.34) }, C.gray)
		decline.Parent = row
		accept.Activated:Connect(function()
			self:_fire("respond", inv.from, true)
		end)
		decline.Activated:Connect(function()
			self:_fire("respond", inv.from, false)
		end)
	end
	self.inviteModes = {}
	for _, inv in ipairs(invites) do
		self.inviteModes[inv.from] = inv.modeName
	end
	self.outgoingLabel.Text = outgoingText

	clear(self.liveList)
	if not live or #live == 0 then
		label({
			Name = "Empty",
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "No games right now",
			Parent = self.liveList,
		})
	end
	for i, g in ipairs(live or {}) do
		local row = new("Frame", {
			Name = "Game" .. g.id,
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 40),
			BackgroundColor3 = Color3.fromRGB(38, 42, 56),
			Parent = self.liveList,
		}, { corner(UDim.new(0.25, 0)) })
		label({ Position = UDim2.fromScale(0.05, 0.1), Size = UDim2.fromScale(0.66, 0.44), FontFace = FONT_MED, Text = g.white .. " vs " .. g.black, Parent = row })
		label({ Position = UDim2.fromScale(0.05, 0.56), Size = UDim2.fromScale(0.66, 0.32), TextColor3 = C.sub, Text = g.modeName, Parent = row })
		local watch = button({ Text = "Watch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.5), Size = UDim2.fromScale(0.27, 0.7) }, C.blue)
		watch.Parent = row
		watch.Activated:Connect(function()
			self:_fire("watch", g.id)
		end)
	end
end

-- refresh just the countdown texts (cheaper than rebuilding the lists)
function TabletView:updateCountdowns(secondsByFrom: { [number]: number }, outgoingText: string)
	for from, lbl in pairs(self.inviteCountdowns or {}) do
		local secs = secondsByFrom[from]
		if secs and lbl.Parent then
			lbl.Text = string.format("%s  ·  %ds", (self.inviteModes and self.inviteModes[from]) or "wants to play", math.max(0, math.ceil(secs)))
		end
	end
	self.outgoingLabel.Text = outgoingText
end

local function clockString(seconds: number): string
	seconds = math.max(0, seconds)
	if seconds < 10 then
		return string.format("0:%04.1f", math.floor(seconds * 10) / 10)
	end
	local s = math.ceil(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

-- clocks: { w, b, running } seconds left, or nil for no clock
function TabletView:updateClocks(clocks, bottomColor: string)
	for _, info in ipairs({ { self.meCardInfo, bottomColor }, { self.oppCardInfo, if bottomColor == "w" then "b" else "w" } }) do
		local card, color = info[1], info[2]
		card.clock.Visible = clocks ~= nil
		if clocks then
			local left = clocks[color]
			card.clockText.Text = clockString(left)
			local running = clocks.running == color
			card.clock.BackgroundColor3 = if running and left < 10 then Color3.fromRGB(150, 40, 40)
				elseif running then Color3.fromRGB(235, 236, 240)
				else Color3.fromRGB(20, 22, 30)
			card.clockText.TextColor3 = if running and left >= 10 then Color3.fromRGB(20, 20, 24) else C.text
		end
	end
end

-- snap: game snapshot from the server
-- view: {
--   bottom = "w"/"b" (side at the bottom), me = "w"/"b" or nil when watching,
--   selected = {r, c}?, targets = {Move}, premove = {fr, fc, tr, tc}?,
--   status, statusColor, settings, resignText, drawText }
function TabletView:renderGame(snap, view)
	local settings = view.settings or {}
	local theme = THEME_BY_KEY[settings.theme or "wood"] or TabletView.BOARD_THEMES[1]
	local flip = view.bottom == "b"
	local kingR, kingC
	if snap.inCheck then
		for r = 1, 8 do
			for c = 1, 8 do
				if snap.board[r][c] == snap.turn .. "K" then
					kingR, kingC = r, c
				end
			end
		end
	end
	local targetSet = {}
	if settings.legalMoves ~= false then
		for _, m in ipairs(view.targets or {}) do
			targetSet[m.tr * 10 + m.tc] = true
		end
	end
	local pre = view.premove
	for row = 1, 8 do
		for col = 1, 8 do
			local r = if flip then row else 9 - row
			local c = if flip then 9 - col else col
			local sq = self.squares[row][col]
			sq.button.BackgroundColor3 = if (row + col) % 2 == 0 then theme.light else theme.dark
			local code = snap.board[r][c]
			if sq.code ~= code then
				sq.code = code
				for _, ch in ipairs(sq.piece:GetChildren()) do
					ch:Destroy()
				end
				if code ~= "" then
					PieceArt.make(code).Parent = sq.piece
				end
			end
			-- highlight
			local hl = sq.highlight
			hl.BackgroundTransparency = 1
			if settings.lastMove ~= false and snap.last and ((snap.last.fr == r and snap.last.fc == c) or (snap.last.tr == r and snap.last.tc == c)) then
				hl.BackgroundColor3 = C.lastMove
				hl.BackgroundTransparency = 0.45
			end
			if pre and ((pre.fr == r and pre.fc == c) or (pre.tr == r and pre.tc == c)) then
				hl.BackgroundColor3 = PREMOVE
				hl.BackgroundTransparency = 0.35
			end
			if view.selected and view.selected[1] == r and view.selected[2] == c then
				hl.BackgroundColor3 = C.selected
				hl.BackgroundTransparency = 0.35
			end
			if kingR == r and kingC == c then
				hl.BackgroundColor3 = C.check
				hl.BackgroundTransparency = 0.3
			end
			local isTarget = targetSet[r * 10 + c] == true
			sq.dot.Visible = isTarget and code == ""
			sq.ring.Visible = isTarget and code ~= ""
			-- coordinates
			local rank = sq.button:FindFirstChild("Rank")
			if rank then
				rank.Text = if settings.coordinates ~= false then tostring(r) else ""
				rank.TextColor3 = theme.coord
			end
			local file = sq.button:FindFirstChild("File")
			if file then
				file.Text = if settings.coordinates ~= false then string.sub("abcdefgh", c, c) else ""
				file.TextColor3 = theme.coord
			end
		end
	end

	local bottom = view.bottom
	local top = if bottom == "w" then "b" else "w"
	local function sideInfo(color: string)
		return if color == "w" then snap.white else snap.black
	end
	local function tagFor(color: string): string
		local text = if color == "w" then "White" else "Black"
		if snap.variant == "threecheck" and snap.checks then
			text ..= string.format("  ·  checks %d/3", snap.checks[color] or 0)
		end
		if snap.turn == color and not snap.over then
			text ..= if view.me == color then "  ·  your move" else "  ·  to move"
		end
		return text
	end
	for _, pair in ipairs({ { self.meCardInfo, bottom }, { self.oppCardInfo, top } }) do
		local card, color = pair[1], pair[2]
		local who = sideInfo(color)
		card.name.Text = who.name .. (if view.me == color then " (you)" else "")
		card.swatch.BackgroundColor3 = if color == "w" then Color3.new(1, 1, 1) else Color3.fromRGB(30, 30, 34)
		card.tag.Text = tagFor(color)
		card.card.BackgroundColor3 = if (snap.turn == color and not snap.over) then Color3.fromRGB(34, 60, 44) else C.card
	end
	self.statusLabel.Text = view.status or ""
	self.statusLabel.TextColor3 = view.statusColor or C.text
	local modeText = snap.modeName or ""
	if snap.variant == "koth" then
		modeText ..= "  ·  reach the centre to win"
	end
	if (snap.spectators or 0) > 0 then
		modeText ..= string.format("  ·  👁 %d", snap.spectators)
	end
	self.modeLabel.Text = modeText

	local playing = view.me ~= nil and not snap.over
	local vsBot = snap.white.bot or snap.black.bot
	self.resignButton.Visible = playing
	self.resignButton.Text = view.resignText or "Resign"
	self.drawButton.Visible = playing and not vsBot
	self.drawButton.Text = view.drawText or "Offer draw"
	self.backButton.Visible = not playing
	self.backButton.Text = if view.me == nil and not snap.over then "Stop watching" else "Back to lobby"

	-- move list
	clear(self.moveList)
	local moves = snap.moves or {}
	for i = 1, #moves, 2 do
		local n = (i + 1) // 2
		local row = label({
			Name = "Move" .. n,
			LayoutOrder = n,
			Size = UDim2.new(1, 0, 0, 18),
			TextScaled = false,
			TextSize = 15,
			FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
			Text = string.format("%2d.  %-8s %s", n, moves[i], moves[i + 1] or ""),
			Parent = self.moveList,
		})
		row.TextColor3 = C.text
	end
	self.moveList.CanvasPosition = Vector2.new(0, 1e6)
end

function TabletView:showPromotion(color: string?)
	if not color then
		self.promoFrame.Visible = false
		return
	end
	for kind, b in pairs(self.promoButtons) do
		for _, ch in ipairs(b:GetChildren()) do
			if ch.Name == "Piece" then
				ch:Destroy()
			end
		end
		local art = PieceArt.make(color .. kind)
		art.ZIndex = 12
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 12
			end
		end
		art.Parent = b
	end
	self.promoFrame.Visible = true
end

---------------------------------------------------------------- shop

function TabletView:_buildShop(pages: Frame): Frame
	local page, body = appPage(pages, "Shop", "Shop", "New items are on the way")
	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(0.31, 0, 0, 150),
			CellPadding = UDim2.new(0.035, 0, 0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local items = ShopItems
	local showPlaceholders = #items == 0
	local count = if showPlaceholders then 6 else #items
	for i = 1, count do
		local item = if showPlaceholders then nil else items[i]
		local card = new("Frame", {
			Name = if item then item.id else ("Soon" .. i),
			LayoutOrder = i,
			BackgroundColor3 = C.card,
			Parent = grid,
		}, { corner(UDim.new(0.1, 0)), stroke(C.cardLine, 1, 0.3) })
		local art = new("Frame", {
			Name = "Art",
			Position = UDim2.fromScale(0.06, 0.06),
			Size = UDim2.fromScale(0.88, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = card,
		}, {
			corner(UDim.new(0.12, 0)),
			new("UIGradient", {
				Rotation = 45,
				Color = if item
					then ColorSequence.new(Color3.fromRGB(255, 159, 67), Color3.fromRGB(238, 82, 120))
					else ColorSequence.new(Color3.fromRGB(70, 74, 92), Color3.fromRGB(44, 46, 60)),
			}),
		})
		label({
			Size = UDim2.fromScale(0.5, 0.6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Text = if item then (item.icon or "🎁") else "🔒",
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = art,
		})
		label({
			Position = UDim2.fromScale(0.07, 0.6),
			Size = UDim2.fromScale(0.86, 0.13),
			FontFace = FONT_BOLD,
			Text = if item then item.name else "Coming soon",
			Parent = card,
		})
		label({
			Position = UDim2.fromScale(0.07, 0.74),
			Size = UDim2.fromScale(0.86, 0.1),
			TextColor3 = C.sub,
			Text = if item then (item.description or "") else "Check back later",
			Parent = card,
		})
		local price = button({
			Text = if item then (tostring(item.price) .. " coins") else "—",
			Position = UDim2.fromScale(0.07, 0.86),
			Size = UDim2.fromScale(0.86, 0.11),
			Active = item ~= nil,
			AutoButtonColor = item ~= nil,
		}, if item then C.blue else C.gray)
		price.Parent = card
		if item then
			price.Activated:Connect(function()
				self:_fire("buy", item.id)
			end)
		end
	end
	return page
end

---------------------------------------------------------------- banner

function TabletView:_buildBanner(screen: Frame)
	local banner = new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.25),
		Size = UDim2.fromScale(0.46, 0.17),
		BackgroundColor3 = Color3.fromRGB(36, 40, 54),
		BackgroundTransparency = 0.05,
		ZIndex = 30,
		Visible = false,
		Parent = screen,
	}, { corner(UDim.new(0.2, 0)), stroke(Color3.fromRGB(90, 96, 120), 1, 0.3) })
	local icon = new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.035, 0.5),
		Size = UDim2.fromScale(0.13, 0.6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 31,
		Parent = banner,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(UDim.new(0.24, 0)),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(196, 148, 92), Color3.fromRGB(120, 78, 40)) }),
	})
	local art = PieceArt.make("wN")
	art.Size = UDim2.fromScale(0.75, 0.75)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	for _, d in ipairs(art:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 32
		end
	end
	art.Parent = icon
	self.bannerTitle = label({ Position = UDim2.fromScale(0.2, 0.14), Size = UDim2.fromScale(0.5, 0.26), FontFace = FONT_BOLD, Text = "", ZIndex = 31, Parent = banner })
	self.bannerBody = label({ Position = UDim2.fromScale(0.2, 0.46), Size = UDim2.fromScale(0.45, 0.22), TextColor3 = C.sub, Text = "", ZIndex = 31, Parent = banner })
	local yes = button({ Name = "Yes", Text = "Accept", Position = UDim2.fromScale(0.67, 0.18), Size = UDim2.fromScale(0.29, 0.3), ZIndex = 31 }, C.green)
	yes.Parent = banner
	local no = button({ Name = "No", Text = "Decline", Position = UDim2.fromScale(0.67, 0.55), Size = UDim2.fromScale(0.29, 0.3), ZIndex = 31 }, C.gray)
	no.Parent = banner
	self.banner, self.bannerYes, self.bannerNo = banner, yes, no
	yes.Activated:Connect(function()
		self:_fire("bannerYes")
	end)
	no.Activated:Connect(function()
		self:_fire("bannerNo")
	end)
end

-- show a notification banner; buttons appear when withButtons is true
function TabletView:showBanner(title: string, body: string, withButtons: boolean)
	self.bannerTitle.Text = title
	self.bannerBody.Text = body
	self.bannerYes.Visible = withButtons
	self.bannerNo.Visible = withButtons
	self.banner.Size = if withButtons then UDim2.fromScale(0.46, 0.17) else UDim2.fromScale(0.36, 0.12)
	self.banner.Visible = true
	TweenService:Create(self.banner, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.075),
	}):Play()
end

function TabletView:hideBanner()
	local t = TweenService:Create(self.banner, TweenInfo.new(0.2), { Position = UDim2.fromScale(0.5, -0.25) })
	t:Play()
	t.Completed:Connect(function()
		if self.banner.Position.Y.Scale < 0 then
			self.banner.Visible = false
		end
	end)
end

function TabletView:setClock(timeText: string, dateText: string, counterText: string)
	self.timeLabel.Text = timeText
	self.widgetTime.Text = timeText
	self.widgetDate.Text = dateText
	self.widgetCounter.Text = counterText
end

return TabletView
