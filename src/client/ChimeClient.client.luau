-- On-screen side of "Chime of Conflict" (the tablet app is ChimeApp):
--   * a bar at the top with energy, coins, Death Tokens, mask and light
--   * F: flashlight (sends Glare away when it's in the beam)
--   * Q: mask (Hollow leaves you alone while it's on; no tablet while worn)
--   * your door: click it to shut / open it (that part is on the server)
--   * security cameras (opened from the tablet app)
--   * the jumpscare when a robot gets you, messages, and the result

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ChimeShared = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ChimeShared"))
local event = ReplicatedStorage:WaitForChild("ChimeRemotes"):WaitForChild("Chime") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local robotColor = {}
local robotName = {}
for _, r in ipairs(ChimeShared.ROBOTS) do
	robotColor[r.id] = r.color
	robotName[r.id] = r.name
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

local function text(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		TextStrokeTransparency = 0.5,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p)
end

local gui = new("ScreenGui", {
	Name = "ChimeHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	Parent = player:WaitForChild("PlayerGui"),
})

---------------------------------------------------------------- top bar

local bar = new("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(560, 64),
	BackgroundColor3 = Color3.fromRGB(16, 10, 16),
	BackgroundTransparency = 0.25,
	Visible = false,
	Parent = gui,
}, { new("UICorner", { CornerRadius = UDim.new(0, 12) }) })
local vsLabel = text({ Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(250, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = bar })
local energyBack = new("Frame", {
	Position = UDim2.fromOffset(14, 36),
	Size = UDim2.fromOffset(200, 16),
	BackgroundColor3 = Color3.fromRGB(30, 30, 38),
	Parent = bar,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local energyFill = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 220, 255),
	Parent = energyBack,
}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local energyText = text({ Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromRGB(10, 20, 30), TextStrokeTransparency = 1, Text = "", Parent = energyBack })
local statusText = text({ Position = UDim2.fromOffset(226, 30), Size = UDim2.fromOffset(326, 26), TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = bar })
local coinsText = text({ Position = UDim2.fromOffset(270, 6), Size = UDim2.fromOffset(282, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 205, 90), Text = "", Parent = bar })
local hint = text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 126),
	Size = UDim2.fromOffset(560, 18),
	TextColor3 = Color3.fromRGB(210, 200, 215),
	FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
	Text = "F flashlight · Q mask · click your door to shut it · M tablet (Snake & Minesweeper = coins)",
	Visible = false,
	Parent = gui,
})

local function inMatch(): boolean
	return player:GetAttribute("ChimeMatch") ~= nil
end

local function refreshBar()
	local on = inMatch()
	bar.Visible = on
	hint.Visible = on
	if not on then
		return
	end
	local energy = player:GetAttribute("ChimeEnergy") or 0
	vsLabel.Text = "🔔 vs " .. tostring(player:GetAttribute("ChimeOpponent") or "?")
	energyFill.Size = UDim2.fromScale(math.clamp(energy / ChimeShared.START_ENERGY, 0, 1), 1)
	energyFill.BackgroundColor3 = if energy < 20 then Color3.fromRGB(255, 90, 80) else Color3.fromRGB(120, 220, 255)
	energyText.Text = string.format("⚡ %d", math.floor(energy + 0.5))
	coinsText.Text = string.format("🪙 %d   💀 %d", player:GetAttribute("ChimeCoins") or 0, player:GetAttribute("ChimeTokens") or 0)
	statusText.Text = string.format(
		"🎭 %s   🔦 %s   🚪 %s",
		if player:GetAttribute("ChimeMask") then "ON" else "off",
		if player:GetAttribute("ChimeFlash") then "ON" else "off",
		if player:GetAttribute("ChimeDoor") then "SHUT" else "open"
	)
end
for _, name in ipairs({ "ChimeMatch", "ChimeEnergy", "ChimeCoins", "ChimeTokens", "ChimeMask", "ChimeFlash", "ChimeDoor", "ChimeOpponent" }) do
	player:GetAttributeChangedSignal(name):Connect(refreshBar)
end
refreshBar()

---------------------------------------------------------------- messages

local toastLabel = text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(640, 30),
	BackgroundColor3 = Color3.fromRGB(20, 12, 20),
	BackgroundTransparency = 0.2,
	Text = "",
	Visible = false,
	Parent = gui,
}, nil)
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = toastLabel })
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = toastLabel })
local toastId = 0
local function toast(message: string, seconds: number?)
	toastId += 1
	local id = toastId
	toastLabel.Text = message
	toastLabel.Visible = true
	task.delay(seconds or 3.5, function()
		if toastId == id then
			toastLabel.Visible = false
		end
	end)
end

---------------------------------------------------------------- mask

local maskOverlay = new("Frame", {
	Name = "Mask",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 4, 6),
	BackgroundTransparency = 0.3,
	Visible = false,
	ZIndex = 2,
	Parent = gui,
}, {
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}),
})
text({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(420, 34),
	TextColor3 = Color3.fromRGB(230, 200, 220),
	Text = "🎭 MASK ON — press Q to take it off",
	ZIndex = 3,
	Parent = maskOverlay,
})

local function putTabletAway()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
end

player:GetAttributeChangedSignal("ChimeMask"):Connect(function()
	local on = player:GetAttribute("ChimeMask") == true
	maskOverlay.Visible = on
	if on then
		putTabletAway()
	end
end)

---------------------------------------------------------------- flashlight

local beamPart = new("Part", {
	Name = "ChimeFlashlight",
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	Transparency = 1,
	Size = Vector3.new(0.2, 0.2, 0.2),
})
local beam = new("SpotLight", {
	Brightness = 6,
	Range = 60,
	Angle = 38,
	Color = Color3.fromRGB(255, 244, 214),
	Shadows = true,
	Enabled = false,
	Parent = beamPart,
})
beamPart.Parent = camera
local clickSound = new("Sound", { SoundId = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Parent = gui })

player:GetAttributeChangedSignal("ChimeFlash"):Connect(function()
	beam.Enabled = player:GetAttribute("ChimeFlash") == true
	clickSound:Play()
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastHit = 0
local function checkBeam()
	-- tell the server when a robot hunting us is in the beam (it checks too)
	local map = ChimeShared.map()
	local folder = map and map:FindFirstChild("Match")
	if not folder then
		return
	end
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("ChimeVictim") == player.UserId then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local to = root.Position - origin
				local distance = to.Magnitude
				if distance < 70 and look:Dot(to.Unit) > math.cos(math.rad(24)) then
					rayParams.FilterDescendantsInstances = { player.Character, beamPart }
					local hit = workspace:Raycast(origin, to, rayParams)
					if not hit or hit.Instance:IsDescendantOf(model) then
						event:FireServer("flashHit", { robot = model:GetAttribute("ChimeRobotId") })
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- cameras

local camsOpen = false
local camIndex = 1
local camGui = new("Frame", {
	Name = "Cameras",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
local static = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(180, 200, 190),
	BackgroundTransparency = 0.93,
	ZIndex = 5,
	Parent = camGui,
})
local camName = text({
	Position = UDim2.fromOffset(30, 40),
	Size = UDim2.fromOffset(420, 32),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	ZIndex = 6,
	Parent = camGui,
})
local rec = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -30, 0, 40),
	Size = UDim2.fromOffset(120, 28),
	TextColor3 = Color3.fromRGB(255, 70, 70),
	Text = "● REC",
	ZIndex = 6,
	Parent = camGui,
})
local camList = new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -24),
	Size = UDim2.fromOffset(330, 230),
	BackgroundColor3 = Color3.fromRGB(10, 14, 12),
	BackgroundTransparency = 0.25,
	ZIndex = 6,
	Parent = camGui,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 10) }),
	new("UIGridLayout", { CellSize = UDim2.fromOffset(100, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10) }),
})
local camButtons = {}
local function showCam(i: number)
	camIndex = i
	local cam = ChimeShared.CAMERAS[i]
	local from = ChimeShared.at(cam.from[1], cam.from[2], cam.from[3])
	local to = ChimeShared.at(cam.to[1], cam.to[2], cam.to[3])
	camera.CFrame = CFrame.lookAt(from, to)
	camera.FieldOfView = 80
	camName.Text = cam.name
	for j, b in ipairs(camButtons) do
		b.BackgroundColor3 = if j == i then Color3.fromRGB(60, 140, 90) else Color3.fromRGB(40, 50, 44)
	end
end
for i, cam in ipairs(ChimeShared.CAMERAS) do
	local b = new("TextButton", {
		Name = "Cam" .. i,
		LayoutOrder = i,
		Text = "CAM " .. i,
		FontFace = FONT,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 50, 44),
		ZIndex = 7,
		Parent = camList,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 6) }), new("UIPadding", { PaddingTop = UDim.new(0.25, 0), PaddingBottom = UDim.new(0.25, 0) }) })
	b.Activated:Connect(function()
		showCam(i)
	end)
	camButtons[i] = b
end
local exitCams = new("TextButton", {
	Name = "Exit",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -262),
	Size = UDim2.fromOffset(330, 40),
	Text = "✕ Close cameras",
	FontFace = FONT,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(150, 50, 60),
	ZIndex = 7,
	Parent = camGui,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }), new("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }) })

local savedFov = 70
local function closeCams()
	if not camsOpen then
		return
	end
	camsOpen = false
	camGui.Visible = false
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = savedFov
end
local function openCams()
	if not inMatch() or player:GetAttribute("ChimeMask") then
		return
	end
	putTabletAway()
	if not camsOpen then
		savedFov = camera.FieldOfView
	end
	camsOpen = true
	camGui.Visible = true
	camera.CameraType = Enum.CameraType.Scriptable
	showCam(camIndex)
end
exitCams.Activated:Connect(closeCams)
ChimeShared.signal("openCameras").Event:Connect(openCams)

-- while the cameras are up the mouse is free to click the buttons
RunService:BindToRenderStep("ChimeCameras", Enum.RenderPriority.Camera.Value + 2, function()
	if camsOpen then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		static.BackgroundTransparency = 0.9 + math.random() * 0.07
		rec.Visible = (os.clock() % 1) < 0.6
	end
	-- the flashlight follows your view
	if beam.Enabled then
		beamPart.CFrame = camera.CFrame
	end
end)

---------------------------------------------------------------- keys

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not inMatch() then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		event:FireServer("flash", { on = not player:GetAttribute("ChimeFlash") })
	elseif input.KeyCode == Enum.KeyCode.Q then
		closeCams()
		event:FireServer("mask", { on = not player:GetAttribute("ChimeMask") })
	elseif input.KeyCode == Enum.KeyCode.Backspace and camsOpen then
		closeCams()
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		if inMatch() and player:GetAttribute("ChimeFlash") and not camsOpen then
			local now = os.clock()
			if now - lastHit >= 0.2 then
				lastHit = now
				checkBeam()
			end
		end
	end
end)

---------------------------------------------------------------- jumpscare & result

local scare = new("Frame", {
	Name = "Jumpscare",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})
local scareFace = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.4),
	FontFace = FONT_HEAVY,
	Text = "",
	ZIndex = 21,
	Parent = scare,
})

local function jumpscare(kind: string)
	closeCams()
	scare.Visible = true
	scare.BackgroundColor3 = robotColor[kind] or Color3.new(1, 0, 0)
	scare.BackgroundTransparency = 0
	scareFace.Text = "◉ ◉\n" .. string.upper(robotName[kind] or "?")
	scareFace.TextColor3 = Color3.new(0, 0, 0)
	local t0 = os.clock()
	while os.clock() - t0 < 1.1 do
		scareFace.Position = UDim2.new(0.5, math.random(-24, 24), 0.5, math.random(-24, 24))
		scare.BackgroundTransparency = if math.random() < 0.3 then 0.4 else 0
		task.wait(0.03)
	end
	TweenService:Create(scare, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(scareFace, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	task.wait(0.55)
	scare.Visible = false
	scareFace.TextTransparency = 0
end

local resultFrame = new("Frame", {
	Name = "Result",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 25,
	Parent = gui,
})
local resultTitle = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(700, 90),
	FontFace = FONT_HEAVY,
	Text = "",
	ZIndex = 26,
	Parent = resultFrame,
})
local resultSub = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.fromOffset(700, 30),
	Text = "",
	ZIndex = 26,
	Parent = resultFrame,
})

local REASONS = {
	caught = "caught by a robot",
	forfeit = "someone gave up",
	left = "your opponent left",
	time = "time ran out",
}

event.OnClientEvent:Connect(function(action: string, data)
	data = data or {}
	if action == "toast" then
		toast(data.text or "")
	elseif action == "invite" then
		if not player:GetAttribute("TabletOpen") then
			toast("🔔 " .. tostring(data.name) .. " challenged you to Chime of Conflict — press M to answer", 6)
		end
	elseif action == "match" then
		closeCams()
		toast("🔔 Chime of Conflict vs " .. tostring(data.opponent) .. " — open your tablet (M) and earn coins!", 6)
	elseif action == "jumpscare" then
		task.spawn(jumpscare, data.robot)
	elseif action == "ended" then
		closeCams()
		maskOverlay.Visible = false
		beam.Enabled = false
		resultFrame.Visible = true
		if data.result == "win" then
			resultTitle.Text = "YOU SURVIVED"
			resultTitle.TextColor3 = Color3.fromRGB(120, 230, 150)
		elseif data.result == "lose" then
			resultTitle.Text = "YOU WERE CAUGHT"
			resultTitle.TextColor3 = Color3.fromRGB(255, 90, 90)
		else
			resultTitle.Text = "DRAW"
			resultTitle.TextColor3 = Color3.fromRGB(220, 220, 230)
		end
		resultSub.Text = (REASONS[data.reason] or "") .. " · vs " .. tostring(data.opponent or "?") .. " · coins are gone"
		task.delay(4.5, function()
			resultFrame.Visible = false
		end)
	end
end)

-- leaving the match (respawn on the train) always resets the camera
player:GetAttributeChangedSignal("ChimeMatch"):Connect(function()
	if not inMatch() then
		closeCams()
		maskOverlay.Visible = false
		beam.Enabled = false
	end
end)
