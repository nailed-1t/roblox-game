-- The tablet's Minesweeper app: builds its page and runs the game (all on the
-- client, nothing goes to the server).
--   Click a tile to dig, right-click (or turn on Flag mode) to plant a flag.
--   Clicking a number whose flags are all placed digs the tiles around it.
--   The first dig is always safe.
-- Wins earn points (Easy 10, Normal 20, Hard 30), paid by the server
-- (Economy script) through ShopRemotes.Mines.
-- During a Chime of Conflict match the boards are smaller (ChimeShared.MINES_LEVELS).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("TabletShared")
local TabletArt = require(shared:WaitForChild("TabletArt"))
local ChimeShared = require(shared:WaitForChild("ChimeShared"))

local Minesweeper = {}
Minesweeper.__index = Minesweeper

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local LEVELS = {
	{ key = "easy", name = "Easy", size = 9, mines = 10, points = 10 },
	{ key = "medium", name = "Normal", size = 12, mines = 24, points = 20 },
	{ key = "hard", name = "Hard", size = 16, mines = 40, points = 30 },
}

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function minesRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
	return remotes and remotes:FindFirstChild("Mines") :: RemoteFunction?
end

local function myPoints(): number?
	local stats = player and player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Points")
	return if value then value.Value else nil
end

local COLORS = {
	page = Color3.fromRGB(16, 18, 26),
	card = Color3.fromRGB(28, 31, 42),
	line = Color3.fromRGB(60, 66, 84),
	text = Color3.fromRGB(245, 246, 250),
	sub = Color3.fromRGB(170, 176, 192),
	blue = Color3.fromRGB(64, 132, 255),
	covered = Color3.fromRGB(92, 108, 148),
	open = Color3.fromRGB(36, 40, 54),
	boom = Color3.fromRGB(214, 64, 58),
	win = Color3.fromRGB(52, 199, 89),
	lose = Color3.fromRGB(255, 105, 97),
}

local NUMBER_COLORS = {
	Color3.fromRGB(102, 170, 255),
	Color3.fromRGB(98, 214, 128),
	Color3.fromRGB(255, 104, 104),
	Color3.fromRGB(186, 132, 255),
	Color3.fromRGB(255, 168, 76),
	Color3.fromRGB(80, 220, 220),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(160, 164, 176),
}

local FALLBACK = { mine = "💣", flag = "🚩", wrong = "❌", boom = "💥", happy = "🙂", dead = "😵", cool = "😎", wow = "😮", stopwatch = "⏱" }

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

-- a picture from the art sheet, or an emoji if the sheet isn't set up yet
local function picture(parent: Instance, name: string, size: number): GuiObject
	local img = TabletArt.image(name)
	if img then
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(size, size)
		img.Parent = parent
		return img
	end
	return text({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		Text = FALLBACK[name] or "?",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = parent,
	})
end

local function setPicture(holder: Instance, name: string?)
	for _, ch in ipairs(holder:GetChildren()) do
		if ch:GetAttribute("Pic") then
			ch:Destroy()
		end
	end
	if name then
		local pic = picture(holder, name, 0.78)
		pic:SetAttribute("Pic", true)
		pic.ZIndex = 3
	end
end

---------------------------------------------------------------- build

-- the same three levels, smaller, for Chime of Conflict matches
local CHIME_LEVELS = {}
for _, lv in ipairs(LEVELS) do
	local small = ChimeShared.MINES_LEVELS[lv.key]
	CHIME_LEVELS[lv.key] = {
		key = lv.key,
		name = lv.name,
		size = small.size,
		mines = small.mines,
		points = lv.points,
		best = lv.key .. "_chime",
	}
end

-- the level to play for this difficulty right now
local function levelFor(key: string)
	if player:GetAttribute("ChimeMatch") then
		return CHIME_LEVELS[key]
	end
	for _, lv in ipairs(LEVELS) do
		if lv.key == key then
			return lv
		end
	end
	return LEVELS[1]
end

function Minesweeper.new(pages: Instance)
	local self = setmetatable({}, Minesweeper)
	self.level = LEVELS[1]
	self.best = {}
	self.flagMode = false

	local page = new("Frame", {
		Name = "Mines",
		BackgroundColor3 = COLORS.page,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	})
	self.page = page

	-- left panel
	local panel = new("Frame", {
		Name = "Panel",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.035, 0.04),
		Size = UDim2.fromScale(0.33, 0.9),
		Parent = page,
	})
	text({ Name = "Title", Size = UDim2.fromScale(0.62, 0.09), FontFace = FONT_BOLD, Text = "Minesweeper", Parent = panel })
	self.pointsLabel = text({
		Name = "Points",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.015),
		Size = UDim2.fromScale(0.36, 0.06),
		FontFace = FONT_BOLD,
		TextColor3 = Color3.fromRGB(255, 170, 80),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "⭐ 0",
		Parent = panel,
	})
	task.defer(function()
		local stats = player:WaitForChild("leaderstats", 60)
		local value = stats and stats:WaitForChild("Points", 60)
		if value then
			value.Changed:Connect(function()
				self:_refreshPanel()
			end)
			self:_refreshPanel()
		end
	end)

	-- difficulty
	local levels = new("Frame", {
		Name = "Levels",
		Position = UDim2.fromScale(0, 0.13),
		Size = UDim2.fromScale(1, 0.085),
		BackgroundColor3 = COLORS.card,
		Parent = panel,
	}, {
		corner(0.35),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.levelButtons = {}
	for i, lv in ipairs(LEVELS) do
		local b = new("TextButton", {
			Name = lv.key,
			LayoutOrder = i,
			Size = UDim2.fromScale(1 / #LEVELS, 1),
			BackgroundColor3 = COLORS.blue,
			BackgroundTransparency = 1,
			Text = lv.name,
			FontFace = FONT_BOLD,
			TextScaled = true,
			TextColor3 = COLORS.text,
			AutoButtonColor = false,
			Parent = levels,
		}, { corner(0.35), new("UIPadding", { PaddingTop = UDim.new(0.24, 0), PaddingBottom = UDim.new(0.24, 0) }) })
		b.Activated:Connect(function()
			self.level = lv
			self:newGame()
		end)
		self.levelButtons[lv.key] = b
	end

	-- face + counters card
	local card = new("Frame", {
		Name = "Info",
		Position = UDim2.fromScale(0, 0.26),
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = COLORS.card,
		Parent = panel,
	}, { corner(0.12), new("UIStroke", { Color = COLORS.line, Transparency = 0.4 }) })

	local face = new("ImageButton", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.78),
		BackgroundColor3 = Color3.fromRGB(44, 48, 64),
		AutoButtonColor = true,
		Parent = card,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }), corner(0.3) })
	self.face = face
	face.Activated:Connect(function()
		self:newGame()
	end)

	local function counter(name: string, icon: string, x: number): TextLabel
		local box = new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromScale(0.3, 0.62),
			BackgroundTransparency = 1,
			Parent = card,
		})
		local iconHolder = new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.5, 0.5),
			Parent = box,
		}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
		picture(iconHolder, icon, 1)
		return text({
			Name = "Value",
			Position = UDim2.fromScale(0, 0.55),
			Size = UDim2.fromScale(1, 0.45),
			FontFace = FONT_HEAVY,
			Text = "0",
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = box,
		})
	end
	self.minesLabel = counter("MinesLeft", "mine", 0.16)
	self.timeLabel = counter("Time", "stopwatch", 0.84)

	-- flag mode toggle (for players without a right mouse button)
	local flagButton = new("TextButton", {
		Name = "FlagMode",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.1),
		BackgroundColor3 = COLORS.card,
		Text = "",
		AutoButtonColor = true,
		Parent = panel,
	}, { corner(0.3), new("UIStroke", { Color = COLORS.line, Transparency = 0.4 }) })
	local flagIcon = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, 0.12),
		Size = UDim2.fromScale(0.2, 0.76),
		Parent = flagButton,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	picture(flagIcon, "flag", 1)
	self.flagText = text({
		Position = UDim2.fromScale(0.22, 0.25),
		Size = UDim2.fromScale(0.74, 0.5),
		FontFace = FONT_BOLD,
		Text = "Flag mode: off",
		Parent = flagButton,
	})
	self.flagButton = flagButton
	flagButton.Activated:Connect(function()
		self.flagMode = not self.flagMode
		self:_refreshPanel()
	end)

	self.statusLabel = text({
		Name = "Status",
		Position = UDim2.fromScale(0, 0.75),
		Size = UDim2.fromScale(1, 0.075),
		FontFace = FONT_BOLD,
		Text = "",
		Parent = panel,
	})
	self.bestLabel = text({
		Name = "Best",
		Position = UDim2.fromScale(0, 0.84),
		Size = UDim2.fromScale(1, 0.055),
		TextColor3 = COLORS.sub,
		Text = "",
		Parent = panel,
	})
	text({
		Name = "Hint",
		Position = UDim2.fromScale(0, 0.92),
		Size = UDim2.fromScale(1, 0.05),
		TextColor3 = COLORS.sub,
		Text = "Win: Easy +10 · Normal +20 · Hard +30 points",
		Parent = panel,
	})

	-- board
	local board = new("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromScale(0.6, 0.93),
		BackgroundColor3 = Color3.fromRGB(22, 25, 34),
		Parent = page,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(0.03),
		new("UIStroke", { Color = COLORS.line, Transparency = 0.3 }),
	})
	self.board = board

	-- the face looks worried while a tile is held down
	self.holding = false

	self.heartbeat = RunService.Heartbeat:Connect(function()
		if self.started and not self.over and page.Visible then
			self.timeLabel.Text = tostring(math.min(999, math.floor(os.clock() - self.startTime)))
		end
	end)

	-- a match starting or ending swaps the board size
	player:GetAttributeChangedSignal("ChimeMatch"):Connect(function()
		self:newGame()
	end)

	self:newGame()
	return self
end

---------------------------------------------------------------- game

function Minesweeper:_neighbors(i: number): { number }
	local n = self.level.size
	local r, c = (i - 1) // n, (i - 1) % n
	local out = {}
	for dr = -1, 1 do
		for dc = -1, 1 do
			if dr ~= 0 or dc ~= 0 then
				local rr, cc = r + dr, c + dc
				if rr >= 0 and rr < n and cc >= 0 and cc < n then
					table.insert(out, rr * n + cc + 1)
				end
			end
		end
	end
	return out
end

function Minesweeper:newGame()
	self.level = levelFor(self.level.key)
	local n = self.level.size
	self.mine = {}
	self.count = {}
	self.open = {}
	self.flag = {}
	self.flags = 0
	self.opened = 0
	self.started = false
	self.over = false
	self.won = false
	self.exploded = nil
	self.startTime = 0
	self.token = nil
	self.reward = nil
	self.round = (self.round or 0) + 1
	self.timeLabel.Text = "0"
	self:_buildCells(n)
	self:_refreshAll()
end

function Minesweeper:_placeMines(safe: number)
	local n = self.level.size
	local banned = { [safe] = true }
	for _, j in ipairs(self:_neighbors(safe)) do
		banned[j] = true
	end
	local pool = {}
	for i = 1, n * n do
		if not banned[i] then
			table.insert(pool, i)
		end
	end
	local rng = Random.new()
	for k = 1, math.min(self.level.mines, #pool) do
		local pick = rng:NextInteger(k, #pool)
		pool[k], pool[pick] = pool[pick], pool[k]
		self.mine[pool[k]] = true
	end
	for i = 1, n * n do
		local c = 0
		for _, j in ipairs(self:_neighbors(i)) do
			if self.mine[j] then
				c += 1
			end
		end
		self.count[i] = c
	end
end

function Minesweeper:_dig(i: number)
	if self.over or self.flag[i] then
		return
	end
	if not self.started then
		self.started = true
		self.startTime = os.clock()
		self:_placeMines(i)
		-- get a ticket from the server so a win can be paid out
		local round = self.round
		task.spawn(function()
			local r = minesRemote()
			local ok, token = pcall(function()
				return r and r:InvokeServer("start", self.level.key)
			end)
			if ok and self.round == round then
				self.token = token
				if self.over and self.won then
					self:_claim()
				end
			end
		end)
	end
	if self.open[i] then
		self:_chord(i)
		return
	end
	if self.mine[i] then
		self.exploded = i
		self:_finish(false)
		return
	end
	-- flood fill through empty tiles
	local stack = { i }
	while #stack > 0 do
		local k = table.remove(stack)
		if not self.open[k] and not self.flag[k] then
			self.open[k] = true
			self.opened += 1
			if self.count[k] == 0 then
				for _, j in ipairs(self:_neighbors(k)) do
					if not self.open[j] then
						table.insert(stack, j)
					end
				end
			end
		end
	end
	local n = self.level.size
	if self.opened >= n * n - self.level.mines then
		self:_finish(true)
	end
end

function Minesweeper:_chord(i: number)
	local c = self.count[i]
	if not c or c == 0 then
		return
	end
	local flags = 0
	for _, j in ipairs(self:_neighbors(i)) do
		if self.flag[j] then
			flags += 1
		end
	end
	if flags ~= c then
		return
	end
	for _, j in ipairs(self:_neighbors(i)) do
		if not self.open[j] and not self.flag[j] and not self.over then
			self:_dig(j)
		end
	end
end

function Minesweeper:_toggleFlag(i: number)
	if self.over or self.open[i] then
		return
	end
	-- no more flags than there are mines (the counter never goes below 0)
	if not self.flag[i] and self.flags >= self.level.mines then
		return
	end
	self.flag[i] = not self.flag[i] or nil
	self.flags += if self.flag[i] then 1 else -1
end

function Minesweeper:_finish(won: boolean)
	self.over = true
	self.won = won
	local seconds = math.floor(os.clock() - self.startTime)
	self.timeLabel.Text = tostring(math.min(999, seconds))
	if won then
		-- flag every mine that's left
		for i in pairs(self.mine) do
			if not self.flag[i] then
				self.flag[i] = true
				self.flags += 1
			end
		end
		local key = self.level.key
		key = self.level.best or key
		if not self.best[key] or seconds < self.best[key] then
			self.best[key] = seconds
		end
		self:_claim()
	end
	self.lastTime = seconds
end

-- ask the server to pay out this win
function Minesweeper:_claim()
	local token = self.token
	if not token then
		return -- the ticket is still on its way; claimed when it arrives
	end
	self.token = nil
	local round = self.round
	task.spawn(function()
		local r = minesRemote()
		local ok, gained = pcall(function()
			return r and r:InvokeServer("win", token)
		end)
		if self.round == round then
			self.reward = if ok and type(gained) == "number" then gained else 0
			self:_refreshPanel()
		end
	end)
end

---------------------------------------------------------------- drawing

function Minesweeper:_buildCells(n: number)
	for _, ch in ipairs(self.board:GetChildren()) do
		if ch:IsA("GuiButton") then
			ch:Destroy()
		end
	end
	self.cells = {}
	local gap = 0.12 / n -- space between tiles
	local margin = 0.02
	local step = (1 - 2 * margin) / n
	for i = 1, n * n do
		local r, c = (i - 1) // n, (i - 1) % n
		local b = new("TextButton", {
			Name = "Cell" .. i,
			Text = "",
			AutoButtonColor = true,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(margin + c * step + gap / 2, margin + r * step + gap / 2),
			Size = UDim2.fromScale(step - gap, step - gap),
			BackgroundColor3 = COLORS.covered,
		}, {
			corner(0.2),
			new("UIGradient", {
				Name = "Shade",
				Rotation = 90,
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 176, 196)),
			}),
		})
		local num = text({
			Name = "Number",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.7, 0.7),
			FontFace = FONT_HEAVY,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "",
			ZIndex = 2,
			Parent = b,
		})
		b.Parent = self.board
		self.cells[i] = { button = b, number = num, shown = "" }
		b.MouseButton1Down:Connect(function()
			if not self.over then
				self.holding = true
				self:_refreshPanel()
			end
		end)
		b.MouseLeave:Connect(function()
			if self.holding then
				self.holding = false
				self:_refreshPanel()
			end
		end)
		b.Activated:Connect(function(input)
			self.holding = false
			if self.flagMode and not self.open[i] then
				self:_toggleFlag(i)
			else
				self:_dig(i)
			end
			self:_refreshAll()
		end)
		b.MouseButton2Click:Connect(function()
			self:_toggleFlag(i)
			self:_refreshAll()
		end)
	end
end

function Minesweeper:_refreshCell(i: number)
	local cell = self.cells[i]
	local b = cell.button
	local shade = b:FindFirstChild("Shade") :: UIGradient
	local want: string? = nil
	local isOpen = self.open[i] or (self.over and self.mine[i] and not self.flag[i])
	if self.over and not self.won and self.flag[i] and not self.mine[i] then
		want = "wrong"
		isOpen = true
	elseif self.flag[i] then
		want = "flag"
	elseif self.over and self.mine[i] then
		want = if self.exploded == i then "boom" else "mine"
	end
	b.BackgroundColor3 = if self.exploded == i then COLORS.boom elseif isOpen then COLORS.open else COLORS.covered
	shade.Enabled = not isOpen
	b.AutoButtonColor = not self.over and (not isOpen or (self.count[i] or 0) > 0)
	local c = self.count[i] or 0
	if self.open[i] and not self.mine[i] and c > 0 then
		cell.number.Text = tostring(c)
		cell.number.TextColor3 = NUMBER_COLORS[c]
	else
		cell.number.Text = ""
	end
	if cell.shown ~= (want or "") then
		cell.shown = want or ""
		setPicture(b, want)
	end
end

function Minesweeper:_refreshPanel()
	for key, b in pairs(self.levelButtons) do
		local on = key == self.level.key
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then COLORS.text else COLORS.sub
	end
	local faceName = if self.over then (if self.won then "cool" else "dead") elseif self.holding then "wow" else "happy"
	if not TabletArt.apply(self.face, faceName) then
		self.face.Image = ""
		local t = self.face:FindFirstChild("Fallback") or text({
			Name = "Fallback",
			Size = UDim2.fromScale(0.8, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = self.face,
		})
		t.Text = FALLBACK[faceName]
	end
	self.minesLabel.Text = tostring(math.max(0, self.level.mines - self.flags))
	self.flagText.Text = if self.flagMode then "Flag mode: ON" else "Flag mode: off"
	self.flagButton.BackgroundColor3 = if self.flagMode then Color3.fromRGB(150, 52, 58) else COLORS.card
	if self.over then
		if self.won then
			if self.reward and self.reward > 0 then
				self.statusLabel.Text = string.format("Cleared in %ds! +%d %s", self.lastTime or 0, self.reward, if player:GetAttribute("ChimeMatch") then "coins" else "points")
			else
				self.statusLabel.Text = string.format("You cleared it in %ds!", self.lastTime or 0)
			end
			self.statusLabel.TextColor3 = COLORS.win
		else
			self.statusLabel.Text = "Boom! Tap the face to retry"
			self.statusLabel.TextColor3 = COLORS.lose
		end
	else
		self.statusLabel.Text = if self.started then "Good luck…" else "Dig anywhere to start"
		self.statusLabel.TextColor3 = COLORS.sub
	end
	local have = myPoints()
	self.pointsLabel.Text = if have then ("⭐ " .. have) else ""
	local best = self.best[self.level.best or self.level.key]
	self.bestLabel.Text = if best then string.format("Best (%s): %ds", self.level.name, best) else ("Best (" .. self.level.name .. "): —")
end

function Minesweeper:_refreshAll()
	for i = 1, #self.cells do
		self:_refreshCell(i)
	end
	self:_refreshPanel()
end

return Minesweeper
