-- Ability bar for shop items you own (bottom of the screen). Press the key
-- shown (or click the button) to use one. Also handles being ragdolled by
-- someone's Ardor Scream, and shows short ability messages.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ShopItems = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ShopItems"))
local remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local useRemote = remotes:WaitForChild("UseAbility") :: RemoteEvent
local fxRemote = remotes:WaitForChild("AbilityFx") :: RemoteEvent

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local BLINK_RANGE = 60
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local gui = Instance.new("ScreenGui")
gui.Name = "AbilityBar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -18)
bar.Size = UDim2.fromOffset(0, 64)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local message = Instance.new("TextLabel")
message.Name = "Message"
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position = UDim2.new(0.5, 0, 1, -92)
message.Size = UDim2.fromOffset(520, 28)
message.BackgroundTransparency = 1
message.TextColor3 = Color3.fromRGB(255, 236, 200)
message.TextStrokeTransparency = 0.4
message.TextSize = 20
message.FontFace = FONT
message.Text = ""
message.TextTransparency = 1
message.TextStrokeTransparency = 1
message.Parent = gui

local messageToken = 0
local function say(text: string)
	messageToken += 1
	local token = messageToken
	message.Text = text
	message.TextTransparency = 0
	message.TextStrokeTransparency = 0.4
	task.delay(3, function()
		if token == messageToken then
			TweenService:Create(message, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local buttons = {} -- [id] = { button, shade, timer }
local readyAt = {} -- [id] = os.clock()

-- what the cursor (or the middle of the screen in first person) points at
local function aim(range: number): (BasePart?, Vector3?)
	local camera = workspace.CurrentCamera
	local inset = GuiService:GetGuiInset()
	local mouse = UserInputService:GetMouseLocation() - Vector2.new(0, inset.Y)
	local view = camera.ViewportSize
	-- first person (mouse locked) or a cursor off the window: use the screen middle
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or mouse.X < 0 or mouse.Y < 0 or mouse.X > view.X or mouse.Y > view.Y then
		mouse = view / 2
	end
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	-- reach a bit past the range measured from the camera, then check from the body
	local result = workspace:Raycast(ray.Origin, ray.Direction * (range + 30), params)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not result or not root or (result.Position - root.Position).Magnitude > range then
		return nil, nil
	end
	if result.Instance:IsA("Terrain") then
		return nil, nil -- the sea (or sea floor) isn't somewhere to stand
	end
	return result.Instance, result.Instance.CFrame:PointToObjectSpace(result.Position)
end

local itemsById = {}
for _, item in ipairs(ShopItems) do
	itemsById[item.id] = item
end

local function use(id: string)
	if (readyAt[id] or 0) > os.clock() then
		return
	end
	local item = itemsById[id]
	if item and item.targeted then
		local part, offset = aim(BLINK_RANGE)
		if not part then
			say("Point at a spot within " .. BLINK_RANGE .. " studs.")
			return
		end
		useRemote:FireServer(id, part, offset)
		return
	end
	useRemote:FireServer(id)
end

local function makeButton(item, order: number)
	local b = Instance.new("TextButton")
	b.Name = item.id
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(64, 64)
	b.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
	b.BackgroundTransparency = 0.15
	b.Text = ""
	b.AutoButtonColor = true
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 170, 90)
	stroke.Transparency = 0.3
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromScale(0.15, 0.08)
	icon.Size = UDim2.fromScale(0.7, 0.6)
	icon.TextScaled = true
	icon.Text = item.icon
	icon.Parent = b
	local key = Instance.new("TextLabel")
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromScale(0, 0.68)
	key.Size = UDim2.fromScale(1, 0.28)
	key.TextScaled = true
	key.FontFace = FONT
	key.TextColor3 = Color3.fromRGB(245, 246, 250)
	key.Text = item.key
	key.Parent = b
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.ZIndex = 2
	shade.Parent = b
	Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 14)
	local timer = Instance.new("TextLabel")
	timer.BackgroundTransparency = 1
	timer.Size = UDim2.fromScale(1, 1)
	timer.TextScaled = false
	timer.TextSize = 22
	timer.FontFace = FONT
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.Text = ""
	timer.ZIndex = 3
	timer.Parent = b
	b.Activated:Connect(function()
		use(item.id)
	end)
	buttons[item.id] = { button = b, shade = shade, timer = timer, cooldown = item.cooldown }

	local keyCode = Enum.KeyCode[item.key]
	ContextActionService:BindAction("Ability_" .. item.id, function(_, state)
		if state == Enum.UserInputState.Begin then
			use(item.id)
		end
		return Enum.ContextActionResult.Pass
	end, false, keyCode)
end

local function refresh()
	for i, item in ipairs(ShopItems) do
		if player:GetAttribute("Owned_" .. item.id) and not buttons[item.id] then
			makeButton(item, i)
		end
	end
end
refresh()
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 6) == "Owned_" then
		refresh()
	end
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for id, b in pairs(buttons) do
		local left = (readyAt[id] or 0) - now
		if left > 0 then
			b.shade.Size = UDim2.fromScale(1, math.clamp(left / b.cooldown, 0, 1))
			b.timer.Text = tostring(math.ceil(left))
		else
			b.shade.Size = UDim2.fromScale(1, 0)
			b.timer.Text = ""
		end
	end
end)

---------------------------------------------------------------- effects

fxRemote.OnClientEvent:Connect(function(kind: string, a, b)
	if kind == "cooldown" then
		readyAt[a] = os.clock() + b
	elseif kind == "message" then
		say(a)
	elseif kind == "ragdoll" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end
		if a then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			if typeof(b) == "Vector3" then
				root.AssemblyLinearVelocity += b
			end
			say("You got blasted by an Ardor Scream!")
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end)
