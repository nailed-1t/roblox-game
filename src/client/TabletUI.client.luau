-- The Deepwoken Tablet's screen. Opens when the tablet is taken out (M) and
-- closes when it's put away. While it's open the mouse is free so you can
-- tap things. Runs the Chess app (challenges + games against other players,
-- enforced by the server) and the Shop app.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("TabletShared")
local TabletView = require(shared:WaitForChild("TabletView"))
local ChessRules = require(shared:WaitForChild("ChessRules"))
local chessEvent = ReplicatedStorage:WaitForChild("TabletRemotes"):WaitForChild("ChessEvent") :: RemoteEvent

local TOOL_NAME = "Deepwoken Tablet"
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- screen

local gui = Instance.new("ScreenGui")
gui.Name = "TabletScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

-- a Modal button frees the mouse in first person while the tablet is open
local unlock = Instance.new("TextButton")
unlock.Name = "MouseUnlock"
unlock.Modal = true
unlock.Text = ""
unlock.BackgroundTransparency = 1
unlock.Size = UDim2.fromOffset(0, 0)
unlock.Parent = gui

local view = TabletView.new(gui)
local OPEN_POS = UDim2.fromScale(0.5, 0.5)
local CLOSED_POS = UDim2.fromScale(0.5, 1.5)
view.device.Position = CLOSED_POS

-- small pop-up used when the tablet is put away
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "TabletToast"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = 21
toastGui.Parent = playerGui
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, -80)
toast.Size = UDim2.fromOffset(460, 52)
toast.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
toast.BackgroundTransparency = 0.05
toast.TextColor3 = Color3.fromRGB(245, 246, 250)
toast.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
toast.TextSize = 17
toast.TextWrapped = true
toast.Text = ""
toast.Parent = toastGui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 14)
local toastStroke = Instance.new("UIStroke", toast)
toastStroke.Color = Color3.fromRGB(90, 96, 120)
toastStroke.Transparency = 0.3
local toastToken = 0
local function showToast(text: string, seconds: number?)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()
	task.delay(seconds or 5, function()
		if toastToken == token then
			TweenService:Create(toast, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
		end
	end)
end

---------------------------------------------------------------- state

local isOpen = false
local game_ = nil -- current chess game snapshot (or nil)
local myColor = "w"
local selected = nil -- {rank, file}
local targets = {}
local pendingPromotion = nil -- move waiting for a promotion choice
local invites = {} -- [fromId] = {name, expires}
local outgoing = nil -- {to, name, status, expires}
local bannerFrom = nil -- whose challenge the banner is showing
local resignArmed = false
local thumbnails = {}

local function now()
	return os.clock()
end

local function stateOf(snap)
	return {
		board = snap.board,
		turn = snap.turn,
		castling = snap.castling,
		ep = snap.ep,
		halfmove = snap.halfmove,
		fullmove = snap.fullmove,
	}
end

local REASONS = {
	checkmate = "checkmate",
	resign = "resignation",
	left = "opponent left",
	stalemate = "stalemate",
	fifty = "50-move rule",
	material = "not enough pieces",
}

local function statusFor(snap): (string, Color3)
	if snap.over then
		if snap.result == "draw" then
			return "Draw — " .. (REASONS[snap.reason] or ""), Color3.fromRGB(200, 200, 210)
		end
		local iWon = (snap.result == "white") == (myColor == "w")
		local why = REASONS[snap.reason] or ""
		if iWon then
			return "You win! (" .. why .. ")", Color3.fromRGB(120, 230, 150)
		end
		return "You lost (" .. why .. ")", Color3.fromRGB(255, 120, 110)
	end
	if snap.turn == myColor then
		return if snap.inCheck then "Your move — Check!" else "Your move", if snap.inCheck then Color3.fromRGB(255, 140, 120) else Color3.fromRGB(120, 230, 150)
	end
	return "Waiting for opponent…", Color3.fromRGB(200, 200, 210)
end

local function outgoingText(): string
	if not outgoing then
		return ""
	end
	local n = outgoing.name
	if outgoing.status == "waiting" then
		return string.format("Waiting for %s to answer… %ds", n, math.max(0, math.ceil(outgoing.expires - now())))
	elseif outgoing.status == "declined" then
		return n .. " declined your challenge"
	elseif outgoing.status == "expired" then
		return n .. " didn't answer"
	elseif outgoing.status == "busy" then
		return n .. " is already in a game"
	elseif outgoing.status == "left" then
		return n .. " left the game"
	end
	return ""
end

local function fetchThumbnail(userId: number)
	if thumbnails[userId] ~= nil or userId <= 0 then
		return
	end
	thumbnails[userId] = false
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		if ok and img then
			thumbnails[userId] = img
		end
	end)
end

local function renderChess()
	if game_ then
		view:showChessScreen("game")
		local text, color = statusFor(game_)
		view:renderGame(game_, myColor, selected, targets, text, color)
		view.resignButton.Text = if resignArmed then "Tap again to resign" else "Resign"
	else
		view:showChessScreen("lobby")
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				fetchThumbnail(p.UserId)
				local waiting = outgoing and outgoing.to == p.UserId and outgoing.status == "waiting"
				table.insert(list, { id = p.UserId, name = p.DisplayName, state = if waiting then "waiting" else "free" })
			end
		end
		table.sort(list, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
		local inv = {}
		for from, info in pairs(invites) do
			table.insert(inv, { from = from, name = info.name, seconds = info.expires - now() })
		end
		table.sort(inv, function(a, b)
			return a.seconds > b.seconds
		end)
		local thumbs = {}
		for id, img in pairs(thumbnails) do
			if img then
				thumbs[id] = img
			end
		end
		view:renderLobby(list, inv, outgoingText(), thumbs)
	end
end

---------------------------------------------------------------- open / close

local function hideOwnTablet(hidden: boolean)
	local character = player.Character
	local tool = character and character:FindFirstChild(TOOL_NAME)
	if tool then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	player:SetAttribute("TabletOpen", true)
	gui.Enabled = true
	unlock.Visible = true
	TweenService:Create(view.device, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = OPEN_POS }):Play()
	chessEvent:FireServer("sync")
	if view.currentPage == "chess" then
		renderChess()
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	player:SetAttribute("TabletOpen", false)
	unlock.Visible = false
	view:showPromotion(nil)
	pendingPromotion = nil
	local t = TweenService:Create(view.device, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Position = CLOSED_POS })
	t:Play()
	t.Completed:Connect(function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
end

local function watchCharacter(character: Model)
	close()
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			open()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			close()
		end
	end)
	if character:FindFirstChild(TOOL_NAME) then
		open()
	end
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

---------------------------------------------------------------- view events

view:on("openApp", function(name)
	view:showPage(name)
	if name == "chess" then
		renderChess()
	end
end)

view:on("home", function()
	view:showPage("home")
end)

view:on("challenge", function(userId)
	chessEvent:FireServer("challenge", { target = userId })
end)

view:on("cancelChallenge", function()
	chessEvent:FireServer("cancel")
end)

local function respond(from: number, accept: boolean)
	invites[from] = nil
	if bannerFrom == from then
		bannerFrom = nil
		view:hideBanner()
	end
	chessEvent:FireServer("respond", { from = from, accept = accept })
	if view.currentPage == "chess" then
		renderChess()
	end
end
view:on("respond", respond)

view:on("bannerYes", function()
	if bannerFrom then
		respond(bannerFrom, true)
	end
end)
view:on("bannerNo", function()
	if bannerFrom then
		respond(bannerFrom, false)
	else
		view:hideBanner()
	end
end)

view:on("square", function(row: number, col: number)
	if not game_ or game_.over or game_.turn ~= myColor or pendingPromotion then
		return
	end
	local flip = myColor == "b"
	local r = if flip then row else 9 - row
	local c = if flip then 9 - col else col
	if selected then
		for _, m in ipairs(targets) do
			if m.tr == r and m.tc == c then
				if m.promo then
					pendingPromotion = { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc }
					view:showPromotion(myColor)
					return
				end
				chessEvent:FireServer("move", { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc })
				selected, targets = nil, {}
				renderChess()
				return
			end
		end
	end
	local piece = game_.board[r][c]
	if piece ~= "" and string.sub(piece, 1, 1) == myColor and not (selected and selected[1] == r and selected[2] == c) then
		selected = { r, c }
		targets = ChessRules.legalMovesFrom(stateOf(game_), r, c)
	else
		selected, targets = nil, {}
	end
	renderChess()
end)

view:on("promote", function(kind: string)
	local m = pendingPromotion
	pendingPromotion = nil
	view:showPromotion(nil)
	if m then
		chessEvent:FireServer("move", { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc, promo = kind })
		selected, targets = nil, {}
		renderChess()
	end
end)

view:on("resign", function()
	if resignArmed then
		resignArmed = false
		chessEvent:FireServer("resign")
	else
		resignArmed = true
		renderChess()
		task.delay(3, function()
			if resignArmed then
				resignArmed = false
				if game_ then
					renderChess()
				end
			end
		end)
	end
end)

view:on("leaveGame", function()
	chessEvent:FireServer("leave")
end)

---------------------------------------------------------------- server events

chessEvent.OnClientEvent:Connect(function(action: string, data)
	data = data or {}
	if action == "invite" then
		invites[data.from] = { name = data.name, expires = now() + (data.seconds or 30) }
		if isOpen then
			bannerFrom = data.from
			view:showBanner(data.name, "challenged you to chess", true)
		else
			showToast("♟  " .. data.name .. " challenged you to chess — press M to answer", 6)
		end
	elseif action == "inviteGone" then
		invites[data.from] = nil
		if bannerFrom == data.from then
			bannerFrom = nil
			view:hideBanner()
		end
	elseif action == "outgoing" then
		if data.status == "cancelled" then
			outgoing = nil
		else
			outgoing = { to = data.to, name = data.name, status = data.status, expires = now() + (data.seconds or 0) }
			if data.status ~= "waiting" and isOpen then
				bannerFrom = nil
				view:showBanner(data.name, outgoingText(), false)
				task.delay(3, function()
					if not bannerFrom then
						view:hideBanner()
					end
				end)
			end
		end
	elseif action == "state" then
		local isNew = not game_ or game_.id ~= data.id
		game_ = data
		myColor = if data.white.id == player.UserId then "w" else "b"
		if isNew then
			selected, targets, pendingPromotion = nil, {}, nil
			outgoing = nil
			local opponent = if myColor == "w" then data.black.name else data.white.name
			if isOpen then
				view:showPage("chess")
				view:hideBanner()
			else
				showToast("♟  Your chess game with " .. opponent .. " started — press M", 6)
			end
		end
		-- a move by the opponent can make a selection stale
		if selected and (game_.turn ~= myColor or game_.board[selected[1]][selected[2]] == "") then
			selected, targets = nil, {}
		end
		if data.over then
			resignArmed = false
		end
	elseif action == "noGame" then
		game_ = nil
		selected, targets, pendingPromotion = nil, {}, nil
	end
	if isOpen and view.currentPage == "chess" then
		renderChess()
	end
end)

Players.PlayerAdded:Connect(function()
	if isOpen and view.currentPage == "chess" and not game_ then
		renderChess()
	end
end)
Players.PlayerRemoving:Connect(function(p)
	invites[p.UserId] = nil
	if outgoing and outgoing.to == p.UserId then
		outgoing = nil
	end
	if isOpen and view.currentPage == "chess" and not game_ then
		task.defer(renderChess)
	end
end)

---------------------------------------------------------------- clock + timers

local counterLabel = nil
task.spawn(function()
	local scenery = workspace:WaitForChild("Scenery", 30)
	local screenPart = scenery and scenery:WaitForChild("clock screen", 30)
	local display = screenPart and screenPart:WaitForChild("UpdateDisplay", 30)
	counterLabel = display and display:WaitForChild("Timer", 30)
end)

local lastTick = 0
RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	hideOwnTablet(true) -- the screen is the tablet; hide the 3D one in your hands
	local t = now()
	if t - lastTick < 1 then
		return
	end
	lastTick = t
	local dt = DateTime.now()
	view:setClock(
		dt:FormatLocalTime("HH:mm", "en-us"),
		dt:FormatLocalTime("dddd, MMMM D", "en-us"),
		if counterLabel then counterLabel.Text else "--d --h --m --s"
	)
	-- expire old invites locally and refresh countdowns
	local changed = false
	for from, info in pairs(invites) do
		if info.expires <= t then
			invites[from] = nil
			changed = true
		end
	end
	if view.currentPage == "chess" and not game_ then
		if changed then
			renderChess()
		else
			local secs = {}
			for from, info in pairs(invites) do
				secs[from] = info.expires - t
			end
			view:updateCountdowns(secs, outgoingText())
		end
	end
end)
