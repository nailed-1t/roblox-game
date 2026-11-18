-- The Deepwoken Tablet's screen. The UI is drawn onto the tablet model's own
-- screen (the "Display" part inside the tool) while it's held, and the mouse
-- is freed so you can click on it. Opens with M, closes when put away.
-- Runs the Chess app (challenges + games against other players, enforced by
-- the server) and the Shop app, which flies the camera to the shop stall.

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

-- the UI itself, drawn on the tablet model's screen
local surface = Instance.new("SurfaceGui")
surface.Name = "TabletSurface"
surface.Face = Enum.NormalId.Front
surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
surface.CanvasSize = Vector2.new(800, 496)
surface.LightInfluence = 0
surface.Brightness = 1.3
surface.ResetOnSpawn = false
surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
surface.Enabled = false
surface.Parent = playerGui

local view = TabletView.new(surface, { fullscreen = true })

-- on-screen layer: frees the mouse while the tablet is out, and holds the
-- shop overlay
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

-- make sure the tablet in your hands is visible to you (first person can hide it)
local function showOwnTablet()
	local character = player.Character
	local tool = character and character:FindFirstChild(TOOL_NAME)
	if tool then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Display" then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

---------------------------------------------------------------- shop (camera)

local camera = workspace.CurrentCamera
local inShop = false
local shopTween: Tween? = nil

local overlay = Instance.new("Frame")
overlay.Name = "ShopOverlay"
overlay.AnchorPoint = Vector2.new(0.5, 1)
overlay.Position = UDim2.new(0.5, 0, 1, -20)
overlay.Size = UDim2.new(0.9, 0, 0, 230)
overlay.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
overlay.BackgroundTransparency = 0.12
overlay.Visible = false
overlay.Parent = gui
Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 18)
local overlayStroke = Instance.new("UIStroke", overlay)
overlayStroke.Color = Color3.fromRGB(90, 96, 120)
overlayStroke.Transparency = 0.4

local function overlayText(text: string, x: number, y: number, w: number, h: number, size: number, bold: boolean, color: Color3?)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, x, 0, y)
	l.Size = UDim2.new(w, 0, 0, h)
	l.Text = text
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or Color3.fromRGB(245, 246, 250)
	l.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", if bold then Enum.FontWeight.Bold else Enum.FontWeight.Regular)
	l.Parent = overlay
	return l
end
overlayText("Shop", 24, 14, 0.5, 30, 26, true)
overlayText("New items are on the way", 24, 46, 0.5, 18, 15, false, Color3.fromRGB(170, 176, 192))

local backButton = Instance.new("TextButton")
backButton.Name = "Back"
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.new(1, -20, 0, 16)
backButton.Size = UDim2.fromOffset(170, 40)
backButton.BackgroundColor3 = Color3.fromRGB(64, 132, 255)
backButton.Text = "‹  Back to tablet"
backButton.TextSize = 17
backButton.TextColor3 = Color3.new(1, 1, 1)
backButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
backButton.Parent = overlay
Instance.new("UICorner", backButton).CornerRadius = UDim.new(0, 12)

local cards = Instance.new("ScrollingFrame")
cards.Name = "Items"
cards.Position = UDim2.new(0, 20, 0, 78)
cards.Size = UDim2.new(1, -40, 0, 140)
cards.BackgroundTransparency = 1
cards.BorderSizePixel = 0
cards.ScrollBarThickness = 4
cards.ScrollingDirection = Enum.ScrollingDirection.X
cards.AutomaticCanvasSize = Enum.AutomaticSize.X
cards.CanvasSize = UDim2.new()
cards.Parent = overlay
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.Padding = UDim.new(0, 12)
cardLayout.Parent = cards

local ShopItems = require(shared:WaitForChild("ShopItems"))
local itemCount = if #ShopItems == 0 then 6 else #ShopItems
for i = 1, itemCount do
	local item = ShopItems[i]
	local card = Instance.new("Frame")
	card.Name = if item then item.id else ("Soon" .. i)
	card.LayoutOrder = i
	card.Size = UDim2.fromOffset(170, 130)
	card.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
	card.Parent = cards
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(0, 8)
	icon.Size = UDim2.new(1, 0, 0, 56)
	icon.TextScaled = true
	icon.Text = if item then (item.icon or "🎁") else "🔒"
	icon.Parent = card
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(12, 70)
	name.Size = UDim2.new(1, -24, 0, 22)
	name.TextSize = 17
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(245, 246, 250)
	name.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	name.Text = if item then item.name else "Coming soon"
	name.Parent = card
	local price = Instance.new("TextLabel")
	price.BackgroundTransparency = 1
	price.Position = UDim2.fromOffset(12, 96)
	price.Size = UDim2.new(1, -24, 0, 18)
	price.TextSize = 14
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.TextColor3 = Color3.fromRGB(170, 176, 192)
	price.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
	price.Text = if item then (tostring(item.price) .. " coins") else "Check back later"
	price.Parent = card
end

local function shopSpot(): CFrame?
	local spot = workspace:FindFirstChild("ShopCamera")
	return if spot and spot:IsA("BasePart") then spot.CFrame else nil
end

local function enterShop()
	local target = shopSpot()
	if inShop or not target then
		return
	end
	inShop = true
	view:showPage("home")
	camera.CameraType = Enum.CameraType.Scriptable
	if shopTween then
		shopTween:Cancel()
	end
	shopTween = TweenService:Create(camera, TweenInfo.new(1.4, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = target })
	shopTween:Play()
	overlay.Visible = true
end

local function exitShop(instant: boolean?)
	if not inShop then
		return
	end
	inShop = false
	overlay.Visible = false
	if shopTween then
		shopTween:Cancel()
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local function restore()
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if instant or not head then
		restore()
		return
	end
	local back = CFrame.lookAt(head.Position, head.Position + head.CFrame.LookVector)
	shopTween = TweenService:Create(camera, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = back })
	shopTween:Play()
	shopTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not inShop then
			restore()
		end
	end)
end
backButton.Activated:Connect(function()
	exitShop(false)
end)

---------------------------------------------------------------- open / close

local function open()
	if isOpen then
		return
	end
	local tool = player.Character and player.Character:FindFirstChild(TOOL_NAME)
	local display = tool and tool:FindFirstChild("Display")
	if not display then
		return
	end
	isOpen = true
	player:SetAttribute("TabletOpen", true)
	surface.Adornee = display
	surface.Enabled = true
	gui.Enabled = true
	unlock.Visible = true
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
	exitShop(true)
	unlock.Visible = false
	view:showPromotion(nil)
	pendingPromotion = nil
	surface.Enabled = false
	surface.Adornee = nil
	gui.Enabled = false
end

local function watchCharacter(character: Model)
	close()
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			child:WaitForChild("Display", 5)
			if child.Parent == character then
				open()
			end
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
	if name == "shop" then
		enterShop()
		return
	end
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
	showOwnTablet()
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
