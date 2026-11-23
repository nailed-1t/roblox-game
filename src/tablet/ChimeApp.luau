-- The tablet's "Chime of Conflict" app.
--   Before a match: challenge another player (or answer a challenge).
--   During a match: your coins and energy, summon robots against your
--   opponent, buy items, open the security cameras, or give up.
-- It talks to the ChimeServer script itself (ChimeRemotes.Chime) and reads
-- the player's Chime* attributes, which the server keeps up to date.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChimeShared = require(script.Parent:WaitForChild("ChimeShared"))

local ChimeApp = {}
ChimeApp.__index = ChimeApp

local player = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_MED = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local C = {
	bg = Color3.fromRGB(14, 10, 16),
	text = Color3.fromRGB(245, 246, 250),
	sub = Color3.fromRGB(176, 168, 186),
	card = Color3.fromRGB(32, 24, 36),
	cardLine = Color3.fromRGB(84, 56, 80),
	accent = Color3.fromRGB(230, 80, 110),
	green = Color3.fromRGB(52, 199, 89),
	gray = Color3.fromRGB(72, 66, 84),
	gold = Color3.fromRGB(255, 205, 90),
	energy = Color3.fromRGB(120, 220, 255),
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

local function label(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = C.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p)
end

local function button(props: { [string]: any }, bg: Color3): TextButton
	local b = new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
		FontFace = FONT_BOLD,
		TextColor3 = C.text,
		TextScaled = true,
	}, {
		corner(0.3),
		new("UIPadding", {
			PaddingTop = UDim.new(0.22, 0),
			PaddingBottom = UDim.new(0.22, 0),
			PaddingLeft = UDim.new(0.06, 0),
			PaddingRight = UDim.new(0.06, 0),
		}),
	})
	for k, v in pairs(props) do
		(b :: any)[k] = v
	end
	return b
end

local function card(parent: Instance, props: { [string]: any }): Frame
	local f = new("Frame", { BackgroundColor3 = C.card, Parent = parent }, { corner(0.08), new("UIStroke", { Color = C.cardLine, Transparency = 0.3 }) })
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	return f
end

local function clear(frame: Instance)
	for _, ch in ipairs(frame:GetChildren()) do
		if not (ch:IsA("UIListLayout") or ch:IsA("UIGridLayout") or ch:IsA("UIPadding")) then
			ch:Destroy()
		end
	end
end

local function remote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("ChimeRemotes")
	return folder and folder:FindFirstChild("Chime") :: RemoteEvent?
end

local function fire(action: string, data: any?)
	local r = remote()
	if r then
		r:FireServer(action, data or {})
	end
end

function ChimeApp.new(pages: Instance)
	local self = setmetatable({}, ChimeApp)
	self.invites = {} -- [fromId] = { name, expires }
	self.outgoing = nil -- { name, status, expires }
	self.busy = false

	local page = new("Frame", {
		Name = "Chime",
		BackgroundColor3 = C.bg,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(40, 16, 30), Color3.fromRGB(10, 8, 14)),
		}),
	})
	self.page = page

	label({ Position = UDim2.fromScale(0.04, 0.03), Size = UDim2.fromScale(0.6, 0.075), FontFace = FONT_BOLD, Text = "🔔 Chime of Conflict", Parent = page })
	self.subtitle = label({ Position = UDim2.fromScale(0.04, 0.105), Size = UDim2.fromScale(0.92, 0.045), TextColor3 = C.sub, Text = "", Parent = page })

	self:_buildLobby(page)
	self:_buildMatch(page)

	-- server messages
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("ChimeRemotes", 60)
		local r = folder and folder:WaitForChild("Chime", 60) :: RemoteEvent?
		if not r then
			return
		end
		r.OnClientEvent:Connect(function(action, data)
			self:_onServer(action, data or {})
		end)
	end)
	for _, name in ipairs({ "ChimeMatch", "ChimeCoins", "ChimeEnergy", "ChimeTokens", "ChimeOpponent" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			self:refresh()
		end)
	end
	Players.PlayerAdded:Connect(function()
		self:refresh()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:refresh()
		end)
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			fire("sync")
			self:refresh()
		end
	end)
	-- countdowns
	task.spawn(function()
		while true do
			task.wait(1)
			if page.Visible and not player:GetAttribute("ChimeMatch") then
				self:refresh()
			end
		end
	end)
	self:refresh()
	return self
end

---------------------------------------------------------------- lobby

function ChimeApp:_buildLobby(page: Frame)
	local lobby = new("Frame", { Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = page })
	self.lobby = lobby

	local players = card(lobby, { Name = "Players", Position = UDim2.fromScale(0.04, 0.18), Size = UDim2.fromScale(0.45, 0.78) })
	label({ Position = UDim2.fromScale(0.05, 0.03), Size = UDim2.fromScale(0.9, 0.08), FontFace = FONT_BOLD, Text = "Challenge someone", Parent = players })
	self.playerList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.14),
		Size = UDim2.fromScale(0.92, 0.84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = players,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local invites = card(lobby, { Name = "Invites", Position = UDim2.fromScale(0.52, 0.18), Size = UDim2.fromScale(0.44, 0.32) })
	label({ Position = UDim2.fromScale(0.05, 0.05), Size = UDim2.fromScale(0.9, 0.17), FontFace = FONT_BOLD, Text = "Challenges", Parent = invites })
	self.inviteList = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.27),
		Size = UDim2.fromScale(0.92, 0.48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = invites,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self.outgoingLabel = label({ Position = UDim2.fromScale(0.05, 0.78), Size = UDim2.fromScale(0.9, 0.17), TextColor3 = C.sub, Text = "", Parent = invites })

	local rules = card(lobby, { Name = "Rules", Position = UDim2.fromScale(0.52, 0.53), Size = UDim2.fromScale(0.44, 0.43) })
	label({ Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.12), FontFace = FONT_BOLD, Text = "How it works", Parent = rules })
	local lines = {
		"You're locked in rooms at opposite ends of the Looping Rooms.",
		"Play Snake & Minesweeper for coins (they vanish after the match).",
		"Spend coins on robots that hunt your opponent, or on items.",
		"🟡 Glare: flashlight (F)   🔴 Brute: shut your door (E)   🟣 Hollow: mask (Q)",
		"Door & flashlight use energy. Caught without a Death Token = you lose.",
	}
	for i, t in ipairs(lines) do
		label({
			Position = UDim2.fromScale(0.05, 0.18 + (i - 1) * 0.16),
			Size = UDim2.fromScale(0.9, 0.13),
			TextColor3 = C.sub,
			TextWrapped = true,
			Text = t,
			Parent = rules,
		})
	end
end

function ChimeApp:_renderLobby()
	self.subtitle.Text = if self.busy then "A match is being played right now — wait for it to finish." else "A two-player horror duel. Earn coins, send robots, survive."
	clear(self.playerList)
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	if #others == 0 then
		label({
			Size = UDim2.new(1, 0, 0, 34),
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Nobody else is here yet",
			Parent = self.playerList,
		})
	end
	for i, p in ipairs(others) do
		local row = new("Frame", {
			Name = "P" .. p.UserId,
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 42),
			BackgroundColor3 = Color3.fromRGB(46, 34, 50),
			Parent = self.playerList,
		}, { corner(0.25) })
		label({ Position = UDim2.fromScale(0.05, 0.25), Size = UDim2.fromScale(0.55, 0.5), FontFace = FONT_MED, Text = p.DisplayName, Parent = row })
		local inMatch = p:GetAttribute("ChimeMatch") ~= nil
		local b = button({
			Name = "Challenge",
			Text = if inMatch then "Playing" else "Challenge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.34, 0.72),
			Active = not inMatch,
		}, if inMatch then C.gray else C.accent)
		b.Parent = row
		b.Activated:Connect(function()
			if not inMatch then
				fire("challenge", { target = p.UserId })
			end
		end)
	end

	clear(self.inviteList)
	local now = os.clock()
	local any = false
	for from, inv in pairs(self.invites) do
		if inv.expires <= now then
			self.invites[from] = nil
		else
			any = true
			local row = new("Frame", {
				Name = "I" .. from,
				Size = UDim2.new(1, -6, 0, 40),
				BackgroundColor3 = Color3.fromRGB(46, 34, 50),
				Parent = self.inviteList,
			}, { corner(0.25) })
			label({ Position = UDim2.fromScale(0.04, 0.12), Size = UDim2.fromScale(0.5, 0.42), FontFace = FONT_MED, Text = inv.name, Parent = row })
			label({ Position = UDim2.fromScale(0.04, 0.56), Size = UDim2.fromScale(0.5, 0.32), TextColor3 = C.sub, Text = string.format("wants to duel · %ds", math.ceil(inv.expires - now)), Parent = row })
			local yes = button({ Text = "Accept", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.74, 0.5), Size = UDim2.fromScale(0.21, 0.74) }, C.green)
			yes.Parent = row
			local no = button({ Text = "No", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.5), Size = UDim2.fromScale(0.2, 0.74) }, C.gray)
			no.Parent = row
			yes.Activated:Connect(function()
				fire("respond", { from = from, accept = true })
				self.invites[from] = nil
				self:refresh()
			end)
			no.Activated:Connect(function()
				fire("respond", { from = from, accept = false })
				self.invites[from] = nil
				self:refresh()
			end)
		end
	end
	if not any then
		label({
			Size = UDim2.new(1, 0, 0, 26),
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "No challenges",
			Parent = self.inviteList,
		})
	end
	local o = self.outgoing
	local text = ""
	if o then
		if o.status == "waiting" then
			local left = math.ceil(o.expires - now)
			text = if left > 0 then string.format("Waiting for %s… %ds", o.name, left) else ""
		elseif o.status == "declined" then
			text = (o.name or "They") .. " said no."
		elseif o.status == "expired" then
			text = (o.name or "They") .. " didn't answer."
		elseif o.status == "busy" then
			text = "The rooms are in use — try after the current match."
		elseif o.status == "left" then
			text = (o.name or "They") .. " left."
		end
	end
	self.outgoingLabel.Text = text
end

---------------------------------------------------------------- match

function ChimeApp:_buildMatch(page: Frame)
	local m = new("Frame", { Name = "Match", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = page })
	self.matchFrame = m

	-- stats bar
	local stats = card(m, { Name = "Stats", Position = UDim2.fromScale(0.04, 0.17), Size = UDim2.fromScale(0.92, 0.12) })
	self.coinsLabel = label({ Position = UDim2.fromScale(0.03, 0.2), Size = UDim2.fromScale(0.2, 0.6), FontFace = FONT_BOLD, TextColor3 = C.gold, Text = "", Parent = stats })
	self.tokensLabel = label({ Position = UDim2.fromScale(0.24, 0.2), Size = UDim2.fromScale(0.16, 0.6), FontFace = FONT_BOLD, Text = "", Parent = stats })
	label({ Position = UDim2.fromScale(0.42, 0.25), Size = UDim2.fromScale(0.1, 0.5), TextColor3 = C.energy, FontFace = FONT_BOLD, Text = "⚡ Energy", Parent = stats })
	local barBack = new("Frame", {
		Position = UDim2.fromScale(0.53, 0.3),
		Size = UDim2.fromScale(0.3, 0.4),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		Parent = stats,
	}, { corner(0.5) })
	self.energyBar = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.energy, Parent = barBack }, { corner(0.5) })
	self.energyLabel = label({ Position = UDim2.fromScale(0.85, 0.2), Size = UDim2.fromScale(0.13, 0.6), FontFace = FONT_BOLD, Text = "", Parent = stats })

	-- robots
	label({ Position = UDim2.fromScale(0.04, 0.31), Size = UDim2.fromScale(0.6, 0.05), FontFace = FONT_BOLD, Text = "Send a robot after your opponent", Parent = m })
	for i, r in ipairs(ChimeShared.ROBOTS) do
		local c = card(m, { Name = r.id, Position = UDim2.fromScale(0.04 + (i - 1) * 0.31, 0.375), Size = UDim2.fromScale(0.29, 0.33) })
		new("Frame", { Position = UDim2.fromScale(0.05, 0.07), Size = UDim2.fromScale(0.14, 0.2), BackgroundColor3 = r.color, Parent = c }, {
			corner(0.3),
			new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		})
		label({ Position = UDim2.fromScale(0.24, 0.07), Size = UDim2.fromScale(0.72, 0.15), FontFace = FONT_BOLD, Text = r.name, Parent = c })
		label({
			Position = UDim2.fromScale(0.05, 0.3),
			Size = UDim2.fromScale(0.9, 0.36),
			TextColor3 = C.sub,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = r.counter,
			Parent = c,
		})
		local b = button({ Name = "Summon", Text = string.format("Summon · %d 💰", r.price), Position = UDim2.fromScale(0.06, 0.72), Size = UDim2.fromScale(0.88, 0.22) }, C.accent)
		b.Parent = c
		b.Activated:Connect(function()
			fire("buy", { id = r.id })
		end)
	end

	-- items
	label({ Position = UDim2.fromScale(0.04, 0.72), Size = UDim2.fromScale(0.3, 0.05), FontFace = FONT_BOLD, Text = "Items", Parent = m })
	for i, it in ipairs(ChimeShared.ITEMS) do
		local c = card(m, { Name = it.id, Position = UDim2.fromScale(0.04 + (i - 1) * 0.31, 0.78), Size = UDim2.fromScale(0.29, 0.17) })
		label({ Position = UDim2.fromScale(0.05, 0.1), Size = UDim2.fromScale(0.6, 0.34), FontFace = FONT_BOLD, Text = it.icon .. " " .. it.name, Parent = c })
		label({ Position = UDim2.fromScale(0.05, 0.52), Size = UDim2.fromScale(0.55, 0.34), TextColor3 = C.sub, TextWrapped = true, Text = it.description, Parent = c })
		local b = button({ Name = "Buy", Text = string.format("%d 💰", it.price), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.95, 0.5), Size = UDim2.fromScale(0.32, 0.6) }, C.green)
		b.Parent = c
		b.Activated:Connect(function()
			fire("buy", { id = it.id })
		end)
	end

	local cams = button({ Name = "Cameras", Text = "📷 Cameras", Position = UDim2.fromScale(0.66, 0.78), Size = UDim2.fromScale(0.3, 0.08) }, Color3.fromRGB(60, 90, 160))
	cams.Parent = m
	cams.Activated:Connect(function()
		ChimeShared.signal("openCameras"):Fire()
	end)
	self.forfeitButton = button({ Name = "Forfeit", Text = "Give up", Position = UDim2.fromScale(0.66, 0.875), Size = UDim2.fromScale(0.3, 0.075) }, C.gray)
	self.forfeitButton.Parent = m
	self.forfeitArmed = false
	self.forfeitButton.Activated:Connect(function()
		if self.forfeitArmed then
			fire("forfeit")
			self.forfeitArmed = false
		else
			self.forfeitArmed = true
			self.forfeitButton.Text = "Tap again to give up"
			task.delay(3, function()
				self.forfeitArmed = false
				self.forfeitButton.Text = "Give up"
			end)
		end
	end)
end

function ChimeApp:_renderMatch()
	local coins = player:GetAttribute("ChimeCoins") or 0
	local energy = player:GetAttribute("ChimeEnergy") or 0
	self.subtitle.Text = "vs " .. tostring(player:GetAttribute("ChimeOpponent") or "?") .. " — play Snake & Minesweeper for coins"
	self.coinsLabel.Text = string.format("💰 %d coins", coins)
	self.tokensLabel.Text = string.format("💀 × %d", player:GetAttribute("ChimeTokens") or 0)
	self.energyBar.Size = UDim2.fromScale(math.clamp(energy / ChimeShared.START_ENERGY, 0, 1), 1)
	self.energyBar.BackgroundColor3 = if energy < 20 then Color3.fromRGB(255, 90, 80) else C.energy
	self.energyLabel.Text = string.format("%d", math.floor(energy + 0.5))
end

function ChimeApp:refresh()
	local inMatch = player:GetAttribute("ChimeMatch") ~= nil
	self.lobby.Visible = not inMatch
	self.matchFrame.Visible = inMatch
	if inMatch then
		self:_renderMatch()
	else
		self:_renderLobby()
	end
end

function ChimeApp:_onServer(action: string, data)
	if action == "invite" then
		self.invites[data.from] = { name = data.name, expires = os.clock() + (data.seconds or 30) }
	elseif action == "inviteGone" then
		self.invites[data.from] = nil
	elseif action == "outgoing" then
		if data.status == "cancelled" then
			self.outgoing = nil
		else
			self.outgoing = { name = data.name, status = data.status, expires = os.clock() + (data.seconds or 0) }
		end
	elseif action == "busy" then
		self.busy = data.busy == true
	elseif action == "match" then
		self.invites = {}
		self.outgoing = nil
	elseif action == "ended" then
		self.busy = false
	end
	self:refresh()
end

return ChimeApp
