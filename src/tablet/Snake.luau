-- The tablet's Snake app (runs on the client only).
--   Arrow keys or WASD steer (only while the Snake screen is up, so you
--   don't walk around at the same time), or click the arrow pad.
--   Eat apples to grow; hitting a wall or yourself ends the run.
--   The game pauses by itself when you leave the app or put the tablet away.
-- Points (paid by the server, Economy script): 1 per apple, +100 for
-- filling the whole board. A run is paid when it ends (or when you start a
-- new one over a paused run).

local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function snakeRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
	return remotes and remotes:FindFirstChild("Snake") :: RemoteFunction?
end

local Snake = {}
Snake.__index = Snake

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local SIZE = 17 -- board is SIZE x SIZE
local START_STEP = 0.14 -- seconds per move at the start
local FASTEST_STEP = 0.07
local SPEEDUP = 0.0025 -- per apple eaten

local COLORS = {
	page = Color3.fromRGB(16, 18, 26),
	card = Color3.fromRGB(28, 31, 42),
	line = Color3.fromRGB(60, 66, 84),
	text = Color3.fromRGB(245, 246, 250),
	sub = Color3.fromRGB(170, 176, 192),
	boardA = Color3.fromRGB(30, 46, 36),
	boardB = Color3.fromRGB(34, 52, 40),
	body = Color3.fromRGB(88, 204, 108),
	bodyDark = Color3.fromRGB(60, 168, 84),
	head = Color3.fromRGB(150, 240, 140),
	apple = Color3.fromRGB(232, 64, 64),
	dead = Color3.fromRGB(150, 150, 150),
	green = Color3.fromRGB(52, 199, 89),
	red = Color3.fromRGB(255, 105, 97),
}

local DIRS = {
	up = Vector2.new(0, -1),
	down = Vector2.new(0, 1),
	left = Vector2.new(-1, 0),
	right = Vector2.new(1, 0),
}

local KEYS = {
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.D] = "right",
}

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
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p)
end

-- is this frame actually on screen (it and all its parents shown)?
local function onScreen(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function key(cell: Vector2): number
	return cell.Y * SIZE + cell.X + 1
end

---------------------------------------------------------------- build

function Snake.new(pages: Instance)
	local self = setmetatable({}, Snake)
	self.best = 0
	self.state = "ready" -- ready | playing | paused | over

	local page = new("Frame", {
		Name = "Snake",
		BackgroundColor3 = COLORS.page,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	})
	self.page = page

	local panel = new("Frame", {
		Name = "Panel",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.035, 0.04),
		Size = UDim2.fromScale(0.33, 0.9),
		Parent = page,
	})
	text({ Name = "Title", Size = UDim2.fromScale(1, 0.09), FontFace = FONT_BOLD, Text = "🐍 Snake", Parent = panel })

	local card = new("Frame", {
		Name = "Scores",
		Position = UDim2.fromScale(0, 0.13),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = COLORS.card,
		Parent = panel,
	}, { corner(0.14), new("UIStroke", { Color = COLORS.line, Transparency = 0.4 }) })
	local function score(name: string, title: string, x: number): TextLabel
		text({
			Name = name .. "Title",
			Position = UDim2.fromScale(x, 0.14),
			Size = UDim2.fromScale(0.42, 0.26),
			TextColor3 = COLORS.sub,
			FontFace = FONT_BOLD,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = title,
			Parent = card,
		})
		return text({
			Name = name,
			Position = UDim2.fromScale(x, 0.42),
			Size = UDim2.fromScale(0.42, 0.46),
			FontFace = FONT_HEAVY,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "0",
			Parent = card,
		})
	end
	self.scoreLabel = score("Score", "SCORE", 0.05)
	self.bestLabel = score("Best", "BEST", 0.53)

	local play = new("TextButton", {
		Name = "Play",
		Position = UDim2.fromScale(0, 0.37),
		Size = UDim2.fromScale(1, 0.1),
		BackgroundColor3 = COLORS.green,
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = FONT_BOLD,
		TextScaled = true,
		Text = "Play",
		AutoButtonColor = true,
		Parent = panel,
	}, { corner(0.3), new("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }) })
	self.playButton = play
	play.Activated:Connect(function()
		if self.state == "playing" then
			self:pause()
		elseif self.state == "paused" then
			self:resume()
		else
			self:start()
		end
	end)

	-- arrow pad (for clicking / touch)
	local pad = new("Frame", {
		Name = "Pad",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.51),
		Size = UDim2.fromScale(0.62, 0.3),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 1.5 }) })
	local arrows = {
		up = { "▲", 0.5, 0.17 },
		left = { "◀", 0.18, 0.62 },
		down = { "▼", 0.5, 0.62 },
		right = { "▶", 0.82, 0.62 },
	}
	for dir, info in pairs(arrows) do
		local b = new("TextButton", {
			Name = dir,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(info[2], info[3]),
			Size = UDim2.fromScale(0.3, 0.42),
			BackgroundColor3 = COLORS.card,
			TextColor3 = COLORS.text,
			FontFace = FONT_BOLD,
			TextScaled = true,
			Text = info[1],
			AutoButtonColor = true,
			Parent = pad,
		}, { corner(0.25), new("UIStroke", { Color = COLORS.line, Transparency = 0.4 }), new("UIPadding", { PaddingTop = UDim.new(0.25, 0), PaddingBottom = UDim.new(0.25, 0) }) })
		b.Activated:Connect(function()
			self:steer(dir)
		end)
	end

	self.statusLabel = text({
		Name = "Status",
		Position = UDim2.fromScale(0, 0.84),
		Size = UDim2.fromScale(1, 0.065),
		FontFace = FONT_BOLD,
		TextColor3 = COLORS.sub,
		Text = "",
		Parent = panel,
	})
	text({
		Name = "Hint",
		Position = UDim2.fromScale(0, 0.92),
		Size = UDim2.fromScale(1, 0.05),
		TextColor3 = COLORS.sub,
		Text = "1 point per apple · fill the board: +100",
		Parent = panel,
	})

	-- board
	local board = new("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromScale(0.6, 0.93),
		BackgroundColor3 = Color3.fromRGB(20, 30, 24),
		Parent = page,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(0.03),
		new("UIStroke", { Color = COLORS.line, Transparency = 0.3 }),
	})
	self.board = board
	self.cells = {}
	local margin = 0.02
	local step = (1 - 2 * margin) / SIZE
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			local cell = new("Frame", {
				Name = "C" .. x .. "_" .. y,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(margin + x * step, margin + y * step),
				Size = UDim2.fromScale(step, step),
				BackgroundColor3 = if (x + y) % 2 == 0 then COLORS.boardA else COLORS.boardB,
				Parent = board,
			})
			self.cells[y * SIZE + x + 1] = cell
		end
	end

	-- the pieces drawn on top of the checkerboard
	local function piece(name: string, color: Color3, radius: number, size: number): Frame
		return new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(size, size),
			BackgroundColor3 = color,
			ZIndex = 2,
		}, { corner(radius) })
	end
	self.piece = piece

	-- apple with a little leaf
	local apple = piece("Apple", COLORS.apple, 0.5, 0.8)
	new("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.2, 0.18),
		Size = UDim2.fromScale(0.25, 0.25),
		BackgroundColor3 = Color3.fromRGB(255, 170, 170),
		ZIndex = 3,
		Parent = apple,
	}, { corner(0.5) })
	new("Frame", {
		Name = "Leaf",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.62, 0.08),
		Size = UDim2.fromScale(0.34, 0.2),
		Rotation = -25,
		BackgroundColor3 = Color3.fromRGB(90, 200, 90),
		ZIndex = 3,
		Parent = apple,
	}, { corner(0.5) })
	self.apple = apple

	-- big message over the board (Press Play / Game over / Paused)
	self.banner = text({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.14),
		FontFace = FONT_HEAVY,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 5,
		Text = "",
		Parent = board,
	})

	self.segments = {} -- Frames for the snake body, reused
	self:reset()

	-- game loop + keyboard while the screen is up
	self.bound = false
	self.clock = 0
	self.heartbeat = RunService.Heartbeat:Connect(function(dt)
		local shown = onScreen(page)
		self:_bindKeys(shown)
		if self.state == "playing" then
			if not shown then
				self:pause()
				return
			end
			self.clock += dt
			local stepTime = math.max(FASTEST_STEP, START_STEP - SPEEDUP * self.eaten)
			while self.clock >= stepTime and self.state == "playing" do
				self.clock -= stepTime
				self:_step()
			end
		end
	end)
	return self
end

function Snake:_bindKeys(on: boolean)
	if on == self.bound then
		return
	end
	self.bound = on
	if on then
		local keys = {}
		for k in pairs(KEYS) do
			table.insert(keys, k)
		end
		ContextActionService:BindActionAtPriority("TabletSnake", function(_, state, input)
			if state == Enum.UserInputState.Begin then
				local dir = KEYS[input.KeyCode]
				if dir then
					if self.state == "ready" or self.state == "over" then
						self:start()
					elseif self.state == "paused" then
						self:resume()
					end
					self:steer(dir)
				end
			end
			return Enum.ContextActionResult.Sink -- don't walk while playing
		end, false, Enum.ContextActionPriority.High.Value + 2, table.unpack(keys))
	else
		ContextActionService:UnbindAction("TabletSnake")
	end
end

---------------------------------------------------------------- game

function Snake:reset()
	local mid = math.floor(SIZE / 2)
	self.body = { Vector2.new(mid, mid), Vector2.new(mid - 1, mid), Vector2.new(mid - 2, mid) } -- head first
	self.dir = DIRS.right
	self.queue = {}
	self.eaten = 0
	self.score = 0
	self.clock = 0
	self:_placeApple()
	self:_draw()
	self:_refreshPanel()
end

function Snake:start()
	-- a paused run that's being thrown away still pays for its apples
	if self.state == "paused" or self.state == "playing" then
		self:_claim(false)
	end
	self:reset()
	self.state = "playing"
	self.won = false
	self.reward = nil
	self.run = (self.run or 0) + 1
	self.ticket = nil
	self.claimed = false
	local run = self.run
	task.spawn(function()
		local r = snakeRemote()
		local ok, token = pcall(function()
			return r and r:InvokeServer("start")
		end)
		if ok and self.run == run then
			self.ticket = token
			if self.state == "over" and not self.claimed then
				self:_claim(self.won)
			end
		end
	end)
	self:_refreshPanel()
end

-- send this run's apples to the server to be paid
function Snake:_claim(filled: boolean)
	if self.claimed or not self.ticket then
		return -- ticket still coming: claimed when it arrives
	end
	self.claimed = true
	local token, apples, run = self.ticket, self.eaten, self.run
	self.ticket = nil
	task.spawn(function()
		local r = snakeRemote()
		local ok, gained = pcall(function()
			return r and r:InvokeServer("finish", token, apples, filled)
		end)
		if self.run == run then
			self.reward = if ok and type(gained) == "number" then gained else 0
			self:_refreshPanel()
		end
	end)
end

function Snake:pause()
	if self.state == "playing" then
		self.state = "paused"
		self:_refreshPanel()
	end
end

function Snake:resume()
	if self.state == "paused" then
		self.state = "playing"
		self.clock = 0
		self:_refreshPanel()
	end
end

function Snake:steer(name: string)
	local dir = DIRS[name]
	if not dir then
		return
	end
	if self.state == "ready" or self.state == "over" then
		self:start()
	elseif self.state == "paused" then
		self:resume()
	end
	-- compare with the last queued turn so quick double-taps work
	local last = self.queue[#self.queue] or self.dir
	if dir == last or dir == -last or #self.queue >= 2 then
		return
	end
	table.insert(self.queue, dir)
end

function Snake:_placeApple()
	local taken = {}
	for _, c in ipairs(self.body) do
		taken[key(c)] = true
	end
	local free = {}
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			if not taken[y * SIZE + x + 1] then
				table.insert(free, Vector2.new(x, y))
			end
		end
	end
	self.food = if #free > 0 then free[math.random(1, #free)] else nil
end

function Snake:_step()
	if #self.queue > 0 then
		self.dir = table.remove(self.queue, 1)
	end
	local head = self.body[1] + self.dir
	local grows = self.food ~= nil and head == self.food
	-- walls
	if head.X < 0 or head.Y < 0 or head.X >= SIZE or head.Y >= SIZE then
		self:_die()
		return
	end
	-- itself (the tail tip moves away this step unless we're growing)
	local last = if grows then #self.body else #self.body - 1
	for i = 1, last do
		if self.body[i] == head then
			self:_die()
			return
		end
	end
	table.insert(self.body, 1, head)
	if grows then
		self.eaten += 1
		self.score += 1
		self:_placeApple()
		if not self.food then
			-- filled the whole board
			self.state = "over"
			self.won = true
			if self.score > self.best then
				self.best = self.score
			end
			self:_claim(true)
		end
	else
		table.remove(self.body)
	end
	self:_draw()
	self:_refreshPanel()
end

function Snake:_die()
	self.state = "over"
	self.won = false
	if self.score > self.best then
		self.best = self.score
	end
	self:_claim(false)
	self:_draw()
	self:_refreshPanel()
end

---------------------------------------------------------------- drawing

function Snake:_draw()
	local dead = self.state == "over" and not self.won
	for i, c in ipairs(self.body) do
		local seg = self.segments[i]
		if not seg then
			seg = self.piece("Seg" .. i, COLORS.body, 0.3, 0.9)
			self.segments[i] = seg
		end
		seg.Parent = self.cells[key(c)]
		local isHead = i == 1
		seg.BackgroundColor3 = if dead then COLORS.dead elseif isHead then COLORS.head elseif i % 2 == 0 then COLORS.body else COLORS.bodyDark
		seg.Size = UDim2.fromScale(if isHead then 0.96 else 0.86, if isHead then 0.96 else 0.86)
		-- eyes on the head, looking the way it moves
		local eyes = seg:FindFirstChild("Eyes")
		if isHead then
			if not eyes then
				eyes = new("Frame", { Name = "Eyes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = seg })
				for _, n in ipairs({ "A", "B" }) do
					new("Frame", {
						Name = n,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromScale(0.24, 0.24),
						BackgroundColor3 = Color3.fromRGB(20, 30, 20),
						ZIndex = 4,
						Parent = eyes,
					}, { corner(0.5) })
				end
			end
			eyes.Visible = true
			local d = self.dir
			local side = Vector2.new(-d.Y, d.X)
			local center = Vector2.new(0.5, 0.5) + d * 0.18
			local a = center + side * 0.2
			local b = center - side * 0.2
			eyes.A.Position = UDim2.fromScale(a.X, a.Y)
			eyes.B.Position = UDim2.fromScale(b.X, b.Y)
		elseif eyes then
			eyes.Visible = false
		end
	end
	for i = #self.body + 1, #self.segments do
		self.segments[i].Parent = nil
	end
	self.apple.Parent = if self.food then self.cells[key(self.food)] else nil
end

function Snake:_refreshPanel()
	self.scoreLabel.Text = tostring(self.score)
	self.bestLabel.Text = tostring(math.max(self.best, self.score))
	local s = self.state
	self.playButton.Text = if s == "playing" then "Pause" elseif s == "paused" then "Resume" elseif s == "over" then "Play again" else "Play"
	self.playButton.BackgroundColor3 = if s == "playing" then Color3.fromRGB(90, 96, 120) else COLORS.green
	if s == "ready" then
		self.banner.Text = "Press Play or an arrow key"
		self.banner.TextColor3 = COLORS.text
		self.statusLabel.Text = "Eat the apples 🍎"
		self.statusLabel.TextColor3 = COLORS.sub
	elseif s == "paused" then
		self.banner.Text = "Paused"
		self.banner.TextColor3 = COLORS.text
		self.statusLabel.Text = "Paused"
		self.statusLabel.TextColor3 = COLORS.sub
	elseif s == "over" then
		self.banner.Text = if self.won then "You filled the board!" else "Game over"
		self.banner.TextColor3 = if self.won then COLORS.green else COLORS.red
		if self.reward and self.reward > 0 then
			self.statusLabel.Text = string.format("Score %d · +%d points", self.score, self.reward)
		else
			self.statusLabel.Text = string.format("Length %d · Score %d", #self.body, self.score)
		end
		self.statusLabel.TextColor3 = if self.won then COLORS.green else COLORS.red
	else
		self.banner.Text = ""
		self.statusLabel.Text = string.format("Length %d", #self.body)
		self.statusLabel.TextColor3 = COLORS.sub
	end
end

return Snake
