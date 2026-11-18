-- The shop while the camera looks at the stall: the item list in the side
-- panel, your points, and clicking the item models on the shelf
-- (workspace.ShopDisplay.<id>) to buy them. Used by TabletUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local shared = ReplicatedStorage:WaitForChild("TabletShared")
local ShopItems = require(shared:WaitForChild("ShopItems"))

local ShopPanel = {}
ShopPanel.__index = ShopPanel

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local TEXT = Color3.fromRGB(245, 246, 250)
local SUB = Color3.fromRGB(170, 176, 192)
local CARD = Color3.fromRGB(28, 31, 42)
local ORANGE = Color3.fromRGB(255, 150, 60)
local GREEN = Color3.fromRGB(52, 199, 89)
local BLUE = Color3.fromRGB(64, 132, 255)

local player = Players.LocalPlayer

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
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
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p)
end

local function owns(id: string): boolean
	return player:GetAttribute("Owned_" .. id) == true
end

local function points(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Points")
	return if value then value.Value else 0
end

function ShopPanel.new(overlay: Frame)
	local self = setmetatable({}, ShopPanel)
	self.overlay = overlay
	self.active = false
	self.cards = {}
	self.busy = false

	overlay.Active = true -- clicks on the panel don't reach the shelf

	self.pointsLabel = text({
		Name = "Points",
		Position = UDim2.new(0, 24, 0, 46),
		Size = UDim2.new(1, -48, 0, 20),
		TextSize = 16,
		FontFace = FONT_BOLD,
		TextColor3 = ORANGE,
		Text = "⭐ 0 points",
		Parent = overlay,
	})
	text({
		Name = "Hint",
		Position = UDim2.new(0, 24, 0, 68),
		Size = UDim2.new(1, -48, 0, 34),
		TextSize = 13,
		TextColor3 = SUB,
		Text = "Click an item on the shelf to buy it. Win Minesweeper to earn points.",
		Parent = overlay,
	})

	local list = new("ScrollingFrame", {
		Name = "Items",
		Position = UDim2.new(0, 16, 0, 108),
		Size = UDim2.new(1, -32, 1, -250),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = overlay,
	})
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	for i, item in ipairs(ShopItems) do
		local card = new("Frame", {
			Name = item.id,
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 112),
			BackgroundColor3 = CARD,
			Parent = list,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 14), Parent = card })
		local stroke = new("UIStroke", { Color = Color3.fromRGB(60, 66, 84), Transparency = 0.3, Parent = card })
		text({ Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(40, 40), TextScaled = true, Text = item.icon, Parent = card })
		text({
			Position = UDim2.fromOffset(60, 10),
			Size = UDim2.new(1, -70, 0, 20),
			TextSize = 17,
			FontFace = FONT_BOLD,
			Text = item.name,
			Parent = card,
		})
		text({
			Position = UDim2.fromOffset(60, 32),
			Size = UDim2.new(1, -70, 0, 34),
			TextSize = 12,
			TextColor3 = SUB,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = item.description,
			Parent = card,
		})
		local buy = new("TextButton", {
			Name = "Buy",
			Position = UDim2.new(0, 12, 1, -40),
			Size = UDim2.new(1, -24, 0, 30),
			BackgroundColor3 = ORANGE,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			FontFace = FONT_BOLD,
			Text = "",
			Parent = card,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 9), Parent = buy })
		buy.Activated:Connect(function()
			if not owns(item.id) then
				self:ask(item)
			end
		end)
		self.cards[item.id] = { card = card, buy = buy, stroke = stroke }
	end

	-- "are you sure?" box
	local confirm = new("Frame", {
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -72),
		Size = UDim2.new(1, -32, 0, 128),
		BackgroundColor3 = Color3.fromRGB(36, 40, 56),
		Visible = false,
		ZIndex = 10,
		Parent = overlay,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 14), Parent = confirm })
	new("UIStroke", { Color = ORANGE, Transparency = 0.2, Parent = confirm })
	self.confirm = confirm
	self.confirmText = text({
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 60),
		TextSize = 15,
		FontFace = FONT_BOLD,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
		Text = "",
		Parent = confirm,
	})
	local yes = new("TextButton", {
		Name = "Yes",
		Position = UDim2.new(0, 14, 1, -46),
		Size = UDim2.new(0.5, -20, 0, 34),
		BackgroundColor3 = GREEN,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		FontFace = FONT_BOLD,
		Text = "Buy",
		ZIndex = 11,
		Parent = confirm,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 9), Parent = yes })
	local no = new("TextButton", {
		Name = "No",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 1, -46),
		Size = UDim2.new(0.5, -20, 0, 34),
		BackgroundColor3 = Color3.fromRGB(72, 76, 92),
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		FontFace = FONT_BOLD,
		Text = "Cancel",
		ZIndex = 11,
		Parent = confirm,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 9), Parent = no })
	self.yes, self.no = yes, no
	yes.Activated:Connect(function()
		self:buy()
	end)
	no.Activated:Connect(function()
		self:closeConfirm()
	end)

	-- keep everything up to date
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 6) == "Owned_" then
			self:refresh()
		end
	end)
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 60)
		local value = stats and stats:WaitForChild("Points", 60)
		if value then
			value.Changed:Connect(function()
				self:refresh()
			end)
		end
		self:refresh()
	end)
	self:refresh()
	return self
end

function ShopPanel:refresh()
	self.pointsLabel.Text = string.format("⭐ %d points", points())
	for _, item in ipairs(ShopItems) do
		local c = self.cards[item.id]
		if owns(item.id) then
			c.buy.Text = "Owned  ·  press " .. item.key
			c.buy.BackgroundColor3 = Color3.fromRGB(44, 120, 70)
			c.buy.AutoButtonColor = false
		else
			c.buy.Text = string.format("Buy  ·  %d points", item.price)
			c.buy.BackgroundColor3 = if points() >= item.price then ORANGE else Color3.fromRGB(110, 84, 64)
			c.buy.AutoButtonColor = true
		end
		-- the shelf model's label
		local model = self:model(item.id)
		local label = model and model:FindFirstChild("Label", true)
		local price = label and label:FindFirstChild("Price", true)
		if price and price:IsA("TextLabel") then
			price.Text = if owns(item.id) then "OWNED ✓" else (tostring(item.price) .. " points")
		end
	end
end

function ShopPanel:model(id: string): Model?
	local display = workspace:FindFirstChild("ShopDisplay")
	return display and display:FindFirstChild(id) :: Model?
end

function ShopPanel:ask(item)
	if self.busy then
		return
	end
	self.pending = item
	local have = points()
	if have >= item.price then
		self.confirmText.Text = string.format("Buy %s %s for %d points?\nYou have %d.", item.icon, item.name, item.price, have)
		self.yes.Visible = true
	else
		self.confirmText.Text = string.format("%s %s costs %d points. You have %d — win some Minesweeper games first!", item.icon, item.name, item.price, have)
		self.yes.Visible = false
	end
	self.no.Text = if self.yes.Visible then "Cancel" else "OK"
	self.confirm.Visible = true
end

function ShopPanel:closeConfirm()
	self.confirm.Visible = false
	self.pending = nil
end

function ShopPanel:buy()
	local item = self.pending
	if not item or self.busy then
		return
	end
	self.busy = true
	self.yes.Visible = false
	self.confirmText.Text = "Buying…"
	local buyRemote = ReplicatedStorage:WaitForChild("ShopRemotes"):WaitForChild("Buy") :: RemoteFunction
	local ok, ok2, msg = pcall(function()
		return buyRemote:InvokeServer(item.id)
	end)
	self.busy = false
	self.confirmText.Text = if ok then (msg or (if ok2 then "Bought!" else "Couldn't buy that.")) else "Couldn't reach the shop, try again."
	self.no.Text = "OK"
	self:refresh()
end

---------------------------------------------------------------- the shelf

function ShopPanel:_hit(): Model?
	local display = workspace:FindFirstChild("ShopDisplay")
	if not display then
		return nil
	end
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y - inset.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { display }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not result then
		return nil
	end
	local inst = result.Instance
	while inst and inst.Parent ~= display do
		inst = inst.Parent
	end
	return inst :: Model?
end

local function itemFor(id: string)
	for _, item in ipairs(ShopItems) do
		if item.id == id then
			return item
		end
	end
	return nil
end

function ShopPanel:setActive(on: boolean)
	if self.active == on then
		return
	end
	self.active = on
	if not on then
		self:closeConfirm()
		for _, c in ipairs(self.connections or {}) do
			c:Disconnect()
		end
		self.connections = nil
		if self.highlight then
			self.highlight:Destroy()
			self.highlight = nil
		end
		-- put the spinning models back
		for model, pivot in pairs(self.pivots or {}) do
			if model.Parent then
				model:PivotTo(pivot)
			end
		end
		self.pivots = nil
		return
	end
	self:refresh()
	self.pivots = {}
	local display = workspace:FindFirstChild("ShopDisplay")
	for _, model in ipairs(display and display:GetChildren() or {}) do
		if model:IsA("Model") then
			self.pivots[model] = model:GetPivot()
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.75
	highlight.FillColor = ORANGE
	highlight.OutlineColor = Color3.fromRGB(255, 220, 150)
	highlight.Enabled = false
	highlight.Parent = workspace.CurrentCamera
	self.highlight = highlight
	local started = os.clock()
	self.connections = {
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local model = self:_hit()
				local item = model and itemFor(model.Name)
				if item then
					if owns(item.id) then
						self.pending = nil
						self.confirmText.Text = string.format("You already own %s. Press %s to use it!", item.name, item.key)
						self.yes.Visible = false
						self.no.Text = "OK"
						self.confirm.Visible = true
					else
						self:ask(item)
					end
				end
			end
		end),
		RunService.RenderStepped:Connect(function()
			-- slow spin + bob on the shelf models (only on this screen)
			local t = os.clock() - started
			for model, pivot in pairs(self.pivots) do
				if model.Parent then
					model:PivotTo(pivot * CFrame.new(0, math.sin(t * 1.6) * 1.2, 0) * CFrame.Angles(0, math.sin(t * 0.8) * 0.5, 0))
				end
			end
			local hovered = self:_hit()
			highlight.Adornee = hovered
			highlight.Enabled = hovered ~= nil
		end),
	}
end

return ShopPanel
