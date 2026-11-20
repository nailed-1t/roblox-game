-- The Deepwoken Tablet's screen. When the tablet is taken out (M) a local copy
-- of the tablet model swings up in front of the camera until it fills ~90% of
-- the screen, and the UI is shown on that model's screen. The mouse is
-- freed so you can click on it. Putting it away swings it back down.
-- Runs the Chess app (challenges + games against other players or the
-- computer, enforced by the server; chess.com-style time controls and
-- variants; watching other games; premoves; settings) and the Shop app,
-- which flies the camera to the shop stall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local shared = ReplicatedStorage:WaitForChild("TabletShared")
local TabletView = require(shared:WaitForChild("TabletView"))
local ChessRules = require(shared:WaitForChild("ChessRules"))
local chessEvent = ReplicatedStorage:WaitForChild("TabletRemotes"):WaitForChild("ChessEvent") :: RemoteEvent

local TOOL_NAME = "Deepwoken Tablet"
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- screen

-- on-screen layer: holds the tablet's UI (kept lined up exactly over the 3D
-- tablet's screen every frame, so clicks always land), frees the mouse while
-- the tablet is out, and holds the shop overlay
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

local CANVAS = Vector2.new(800, 496) -- the UI is laid out at this size, then scaled
local holder = Instance.new("Frame")
holder.Name = "TabletHolder"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
holder.BackgroundTransparency = 1
holder.ZIndex = 1
holder.Visible = false
holder.Parent = gui
local holderScale = Instance.new("UIScale")
holderScale.Parent = holder

local view = TabletView.new(holder, { fullscreen = true })

-- small pop-up used when the tablet is put away
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "TabletToast"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = 21
toastGui.Parent = playerGui
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, -140)
toast.Visible = false -- only shown while a message is up
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
	toast.Visible = true
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()
	task.delay(seconds or 5, function()
		if toastToken == token then
			local away = TweenService:Create(toast, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -140) })
			away.Completed:Connect(function()
				if toastToken == token then
					toast.Visible = false
				end
			end)
			away:Play()
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
local liveGames = {} -- games you could watch (from the server)
local chessMode = { time = "rapid", variant = "standard" } -- picked in the lobby
local premove = nil -- {fr, fc, tr, tc} queued for when it's your turn
local clockBase = nil -- {w, b, running, at}: clocks as last sent, and when
local settingsOpen = false
local settings = {
	theme = "wood",
	legalMoves = true,
	lastMove = true,
	coordinates = true,
	premoves = true,
	autoQueen = false,
	confirmResign = true,
	flip = false,
}

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
		variant = snap.variant,
		kingFile = snap.kingFile,
		rookFiles = snap.rookFiles,
		checks = snap.checks,
	}
end

-- are we watching rather than playing?
local function spectating(): boolean
	return game_ ~= nil and game_.white.id ~= player.UserId and game_.black.id ~= player.UserId
end

local REASONS = {
	checkmate = "checkmate",
	resign = "resignation",
	left = "player left",
	stalemate = "stalemate",
	fifty = "50-move rule",
	material = "not enough pieces",
	hill = "king reached the hill",
	threecheck = "three checks",
	timeout = "time ran out",
	timeoutdraw = "time ran out, but no mating material",
	agreement = "agreed",
	aborted = "game aborted",
}

local GOOD = Color3.fromRGB(120, 230, 150)
local BAD = Color3.fromRGB(255, 120, 110)
local NEUTRAL = Color3.fromRGB(200, 200, 210)

local function statusFor(snap): (string, Color3)
	if snap.over then
		local why = REASONS[snap.reason] or ""
		if snap.result == "draw" then
			return (if snap.reason == "aborted" then "Aborted" else "Draw") .. " — " .. why, NEUTRAL
		end
		if spectating() then
			local winner = if snap.result == "white" then snap.white.name else snap.black.name
			return winner .. " wins (" .. why .. ")", NEUTRAL
		end
		local iWon = (snap.result == "white") == (myColor == "w")
		if iWon then
			local gained = snap.rewards and snap.rewards[tostring(player.UserId)]
			return "You win! " .. (if gained then "+" .. gained .. " points" else "(" .. why .. ")"), GOOD
		end
		return "You lost (" .. why .. ")", BAD
	end
	if spectating() then
		local who = if snap.turn == "w" then snap.white.name else snap.black.name
		return "Watching · " .. who .. " to move" .. (if snap.inCheck then " — Check!" else ""), NEUTRAL
	end
	if snap.drawOffer and snap.drawOffer ~= myColor then
		return "Your opponent offers a draw", Color3.fromRGB(255, 210, 110)
	end
	if snap.turn == myColor then
		return if snap.inCheck then "Your move — Check!" else "Your move", if snap.inCheck then Color3.fromRGB(255, 140, 120) else GOOD
	end
	if premove then
		return "Premove set — right-click to cancel", Color3.fromRGB(255, 160, 150)
	end
	return "Waiting for opponent…", NEUTRAL
end

-- the clocks right now, counting down from what the server last sent
local function currentClocks()
	if not clockBase then
		return nil
	end
	local w, b = clockBase.w, clockBase.b
	if clockBase.running and game_ and not game_.over then
		local used = now() - clockBase.at
		if clockBase.running == "w" then
			w -= used
		else
			b -= used
		end
	end
	return { w = w, b = b, running = if game_ and not game_.over then clockBase.running else nil }
end

-- which side is drawn at the bottom of the board
local function bottomColor(): string
	local base = if spectating() then "w" else myColor
	if settings.flip then
		return if base == "w" then "b" else "w"
	end
	return base
end

local function outgoingText(): string
	if not outgoing then
		return ""
	end
	local n = outgoing.name
	if outgoing.status == "waiting" then
		return string.format("Waiting for %s to answer (%s)… %ds", n, outgoing.modeName or "", math.max(0, math.ceil(outgoing.expires - now())))
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
	view:showChessSettings(settingsOpen, settings)
	if game_ then
		view:showChessScreen("game")
		local text, color = statusFor(game_)
		local drawText = "Offer draw"
		if game_.drawOffer == myColor then
			drawText = "Draw offered…"
		elseif game_.drawOffer then
			drawText = "Accept draw"
		end
		view:renderGame(game_, {
			bottom = bottomColor(),
			me = if spectating() then nil else myColor,
			selected = selected,
			targets = targets,
			premove = premove,
			status = text,
			statusColor = color,
			settings = settings,
			resignText = if resignArmed then "Tap again" elseif game_.clock and #game_.moves < 2 then "Abort" else "Resign",
			drawText = drawText,
		})
		view:updateClocks(currentClocks(), bottomColor())
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
			table.insert(inv, { from = from, name = info.name, seconds = info.expires - now(), modeName = info.modeName })
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
		view:renderLobby(list, inv, outgoingText(), thumbs, liveGames, chessMode)
	end
end

---------------------------------------------------------------- open / close

---------------------------------------------------------------- the tablet in front of you

local camera = workspace.CurrentCamera
local SCREEN_FILL = 0.9 -- how much of the screen the tablet covers
local OPEN_TIME = 0.45
local CLOSE_TIME = 0.3

local localTablet: Model? = nil -- copy of the tablet that only you see
local localDisplay: BasePart? = nil
local offsets = {} -- [part] = CFrame relative to the display
local tabletCenter = CFrame.new() -- tablet's middle, relative to the display
local tabletSize = Vector2.new(2, 1.25) -- width/height of the whole tablet (studs)
local shown = 0 -- 0 = down out of view, 1 = up in front of you
local showGoal = 0
local showFrom, showStart, showTime = 0, 0, OPEN_TIME

local function heldTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChild(TOOL_NAME) :: Tool?
end

-- the held tablet: hidden for you while the big copy is up (others still see it)
local function setHeldHidden(hidden: boolean)
	local tool = heldTool()
	if tool then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

local function buildLocalTablet(tool: Tool): boolean
	if localTablet then
		localTablet:Destroy()
	end
	local display = tool:FindFirstChild("Display") :: BasePart?
	if not display then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "TabletLocal"
	offsets = {}
	local minP, maxP = Vector3.new(math.huge, math.huge, math.huge), -Vector3.new(math.huge, math.huge, math.huge)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			local copy = d:Clone()
			copy:ClearAllChildren()
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanTouch = false
			copy.CanQuery = d == display
			copy.CastShadow = false
			copy.LocalTransparencyModifier = 0
			copy.Parent = model
			local rel = display.CFrame:ToObjectSpace(d.CFrame)
			offsets[copy] = rel
			if d == display then
				localDisplay = copy
			else
				-- bounds of the tablet in the display's frame (X = across, Y = up)
				local half = d.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local pt = rel * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
							minP = minP:Min(pt)
							maxP = maxP:Max(pt)
						end
					end
				end
			end
		end
	end
	if maxP.X > minP.X then
		local mid = (minP + maxP) / 2
		tabletCenter = CFrame.new(mid.X, mid.Y, 0)
		tabletSize = Vector2.new(maxP.X - minP.X, maxP.Y - minP.Y)
	end
	model.Parent = camera -- parts under the camera are only drawn for you
	localTablet = model
	return true
end

local function destroyLocalTablet()
	if localTablet then
		localTablet:Destroy()
	end
	localTablet, localDisplay = nil, nil
	offsets = {}
end

local function animateTo(goal: number)
	if showGoal == goal then
		return
	end
	showGoal = goal
	showFrom = shown
	showStart = os.clock()
	showTime = if goal > shown then OPEN_TIME else CLOSE_TIME
end

-- where the display goes so the whole tablet fills SCREEN_FILL of the view,
-- facing you; t slides it from below the screen (0) to the middle (1)
local function placeLocalTablet(t: number)
	if not localTablet then
		return
	end
	local camCF = camera.CFrame
	local vp = camera.ViewportSize
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = vp.X / math.max(vp.Y, 1)
	local distH = tabletSize.Y / (SCREEN_FILL * 2 * tanHalf)
	local distW = tabletSize.X / (SCREEN_FILL * 2 * tanHalf * aspect)
	local dist = math.max(distH, distW, 0.6)
	local viewHeight = 2 * dist * tanHalf
	local e = TweenService:GetValue(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local drop = (1 - e) * viewHeight * 1.1
	local tilt = (1 - e) * math.rad(55)
	local spin = (1 - e) * math.rad(-12)
	-- display front faces the camera, display up = camera up, display right = camera left
	local faceCam = CFrame.fromMatrix(Vector3.zero, -camCF.RightVector, camCF.UpVector)
	local centerCF = CFrame.new(camCF.Position + camCF.LookVector * dist - camCF.UpVector * drop)
		* faceCam
		* CFrame.Angles(-tilt, 0, spin)
	local displayCF = centerCF * tabletCenter:Inverse()
	for part, rel in pairs(offsets) do
		part.CFrame = displayCF * rel
	end
	-- line the UI up over the model's screen
	if localDisplay then
		local half = localDisplay.Size / 2
		local mid = camera:WorldToViewportPoint(localDisplay.CFrame:PointToWorldSpace(Vector3.new(0, 0, -half.Z)))
		local a = camera:WorldToViewportPoint(localDisplay.CFrame:PointToWorldSpace(Vector3.new(half.X, 0, -half.Z)))
		local b = camera:WorldToViewportPoint(localDisplay.CFrame:PointToWorldSpace(Vector3.new(-half.X, 0, -half.Z)))
		holder.Position = UDim2.fromOffset(mid.X, mid.Y)
		holderScale.Scale = math.max(math.abs(b.X - a.X), 1) / CANVAS.X
		holder.Rotation = math.deg(spin)
	end
end

---------------------------------------------------------------- shop (camera)

local inShop = false
local shopTween: Tween? = nil

local overlay = Instance.new("Frame")
overlay.Name = "ShopOverlay"
overlay.AnchorPoint = Vector2.new(1, 0.5)
overlay.Position = UDim2.new(1, -24, 0.5, 0)
overlay.Size = UDim2.new(0.28, 0, 0.82, 0) -- right side, leaves the stall in view
local overlaySize = Instance.new("UISizeConstraint")
overlaySize.MinSize = Vector2.new(220, 0)
overlaySize.MaxSize = Vector2.new(380, math.huge)
overlaySize.Parent = overlay
overlay.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
overlay.BackgroundTransparency = 0.12
overlay.Visible = false
overlay.ZIndex = 5
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
overlayText("Shop", 24, 14, 0.9, 30, 26, true)

local backButton = Instance.new("TextButton")
backButton.Name = "Back"
backButton.AnchorPoint = Vector2.new(0.5, 1)
backButton.Position = UDim2.new(0.5, 0, 1, -18)
backButton.Size = UDim2.new(1, -40, 0, 44)
backButton.BackgroundColor3 = Color3.fromRGB(64, 132, 255)
backButton.Text = "‹  Back to tablet"
backButton.TextSize = 17
backButton.TextColor3 = Color3.new(1, 1, 1)
backButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
backButton.Parent = overlay
Instance.new("UICorner", backButton).CornerRadius = UDim.new(0, 12)

-- item list, points and clicking the shelf models (see ShopPanel)
local ShopPanel = require(shared:WaitForChild("ShopPanel"))
local shopPanel = ShopPanel.new(overlay)

-- the ShopCamera part may not be streamed in, so the server also publishes
-- its CFrame as a workspace attribute (ShopCameraSync)
local function shopSpot(): CFrame?
	local cf = workspace:GetAttribute("ShopCameraCFrame")
	if typeof(cf) == "CFrame" then
		return cf
	end
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
	animateTo(0)
	-- the stall is far away; ask for it to be loaded while the camera flies
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, target.Position + target.LookVector * 450, 5)
	end)
	camera.CameraType = Enum.CameraType.Scriptable
	if shopTween then
		shopTween:Cancel()
	end
	shopTween = TweenService:Create(camera, TweenInfo.new(1.4, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = target })
	shopTween:Play()
	overlay.Visible = true
	shopPanel:setActive(true)
end

local function exitShop(instant: boolean?)
	if not inShop then
		return
	end
	inShop = false
	overlay.Visible = false
	shopPanel:setActive(false)
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
	animateTo(1)
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
	local tool = heldTool()
	if not tool or not buildLocalTablet(tool) then
		return
	end
	isOpen = true
	player:SetAttribute("TabletOpen", true)
	shown, showGoal = 0, 0
	placeLocalTablet(0)
	animateTo(1)
	holder.Visible = true
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
	settingsOpen = false
	view:showChessSettings(false)
	animateTo(0) -- swings down, then the copy is removed (see the render step)
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
	chessEvent:FireServer("challenge", { target = userId, mode = chessMode })
end)

view:on("pickTime", function(key)
	chessMode.time = key
	renderChess()
end)
view:on("pickVariant", function(key)
	chessMode.variant = key
	renderChess()
end)
view:on("computer", function(level)
	chessEvent:FireServer("computer", { level = level, mode = chessMode })
end)
view:on("watch", function(id)
	chessEvent:FireServer("watch", { game = id })
end)
view:on("settings", function()
	settingsOpen = true
	renderChess()
end)
view:on("closeSettings", function()
	settingsOpen = false
	renderChess()
end)
view:on("setting", function(key, value)
	if value == nil then
		settings[key] = not settings[key]
	else
		settings[key] = value
	end
	if key == "premoves" and not settings.premoves then
		premove = nil
	end
	renderChess()
end)
view:on("cancelPremove", function()
	if premove or selected then
		premove = nil
		if game_ and game_.turn ~= myColor then
			selected, targets = nil, {}
		end
		renderChess()
	end
end)
view:on("draw", function()
	if game_ and not game_.over and game_.drawOffer ~= myColor then
		chessEvent:FireServer("draw")
	end
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

-- the moves your piece could make next turn, for a premove (the position
-- will have changed by then, so it's checked again before it's played)
local function premoveTargets(r: number, c: number)
	local st = stateOf(game_)
	st.turn = myColor
	st.ep = nil
	return ChessRules.legalMovesFrom(st, r, c)
end

local function sendMove(m, promo: string?)
	chessEvent:FireServer("move", { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc, promo = promo })
end

view:on("square", function(row: number, col: number)
	if not game_ or game_.over or spectating() or pendingPromotion then
		return
	end
	local flip = bottomColor() == "b"
	local r = if flip then row else 9 - row
	local c = if flip then 9 - col else col
	local myTurn = game_.turn == myColor
	if not myTurn and not settings.premoves then
		return
	end
	if selected then
		for _, m in ipairs(targets) do
			if m.tr == r and m.tc == c then
				if not myTurn then
					-- queue it; promotions in a premove always make a queen
					premove = { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc }
					selected, targets = nil, {}
					renderChess()
					return
				end
				if m.promo then
					if settings.autoQueen then
						sendMove(m, "Q")
						selected, targets = nil, {}
						renderChess()
						return
					end
					pendingPromotion = { fr = m.fr, fc = m.fc, tr = m.tr, tc = m.tc }
					view:showPromotion(myColor)
					return
				end
				sendMove(m)
				selected, targets = nil, {}
				renderChess()
				return
			end
		end
	end
	premove = nil -- clicking elsewhere replaces any queued premove
	local piece = game_.board[r][c]
	if piece ~= "" and string.sub(piece, 1, 1) == myColor and not (selected and selected[1] == r and selected[2] == c) then
		selected = { r, c }
		targets = if myTurn then ChessRules.legalMovesFrom(stateOf(game_), r, c) else premoveTargets(r, c)
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
	if resignArmed or not settings.confirmResign then
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
		invites[data.from] = { name = data.name, expires = now() + (data.seconds or 30), modeName = data.modeName }
		local what = "chess" .. (if data.modeName then " (" .. data.modeName .. ")" else "")
		if isOpen then
			bannerFrom = data.from
			view:showBanner(data.name, "challenged you to " .. what, true)
		else
			showToast("♟  " .. data.name .. " challenged you to " .. what .. " — press M to answer", 6)
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
			outgoing = { to = data.to, name = data.name, status = data.status, expires = now() + (data.seconds or 0), modeName = data.modeName }
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
		local before = game_
		game_ = data
		myColor = if data.white.id == player.UserId then "w" else "b"
		clockBase = if data.clock then { w = data.clock.w, b = data.clock.b, running = data.clock.running, at = now() } else nil
		if isNew then
			selected, targets, pendingPromotion, premove = nil, {}, nil, nil
			outgoing = nil
			if spectating() then
				if isOpen then
					view:showPage("chess")
				end
			else
				local opponent = if myColor == "w" then data.black.name else data.white.name
				if isOpen then
					view:showPage("chess")
					view:hideBanner()
				else
					showToast("♟  Your chess game with " .. opponent .. " started — press M", 6)
				end
			end
		end
		local justMoved = before and not isNew and #(before.moves or {}) ~= #(data.moves or {})
		-- your turn now: play the premove if it's still legal
		if premove and not data.over and data.turn == myColor and not spectating() then
			local pm = premove
			premove = nil
			local m = ChessRules.findMove(stateOf(data), pm.fr, pm.fc, pm.tr, pm.tc, "Q")
			if m then
				sendMove(m, if m.promo then "Q" else nil)
			end
		end
		-- a move can make a selection stale
		if selected and (justMoved or game_.board[selected[1]][selected[2]] == "") then
			local sr, sc = selected[1], selected[2]
			if game_.board[sr][sc] ~= "" and string.sub(game_.board[sr][sc], 1, 1) == myColor and not game_.over then
				targets = if game_.turn == myColor then ChessRules.legalMovesFrom(stateOf(game_), sr, sc) else premoveTargets(sr, sc)
			else
				selected, targets = nil, {}
			end
		end
		if data.over then
			resignArmed = false
			premove = nil
			if isOpen and not spectating() and data.rewards and data.rewards[tostring(player.UserId)] and before and not before.over then
				showToast("♟  You won! +" .. data.rewards[tostring(player.UserId)] .. " points", 5)
			end
		end
	elseif action == "noGame" then
		game_ = nil
		clockBase = nil
		selected, targets, pendingPromotion, premove = nil, {}, nil, nil
	elseif action == "games" then
		liveGames = {}
		for _, g in ipairs(data) do
			if not (game_ and game_.id == g.id) then
				table.insert(liveGames, g)
			end
		end
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

-- move the tablet copy right after the camera updates so it never lags
RunService:BindToRenderStep("TabletLocal", Enum.RenderPriority.Camera.Value + 1, function()
	if not localTablet then
		return
	end
	if shown ~= showGoal then
		local a = math.clamp((os.clock() - showStart) / showTime, 0, 1)
		shown = showFrom + (showGoal - showFrom) * a
		if a >= 1 then
			shown = showGoal
		end
	end
	if not isOpen and shown <= 0 then
		holder.Visible = false
		gui.Enabled = false
		destroyLocalTablet()
		setHeldHidden(false)
		return
	end
	setHeldHidden(true)
	placeLocalTablet(shown)
	if isOpen then
		-- first person locks the mouse to the middle every frame; free it so
		-- the tablet's buttons (and the shop panel) can be clicked
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

local lastTick = 0
RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	if game_ and clockBase and view.currentPage == "chess" then
		view:updateClocks(currentClocks(), bottomColor())
	end
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
