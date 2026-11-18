-- Hangs the pictures on the train's canvases (Train.Canvases) as a slow
-- slideshow, so all of them get shown. Small (landscape) canvases show one
-- picture, the tall ones show two stacked. The pictures are packed on three
-- uploaded sheets (assets/canvas-*.png in the repo).

local TweenService = game:GetService("TweenService")

local SECONDS_PER_PICTURE = 15
local FADE = 0.8
local PIXELS_PER_STUD = 60
local MAT = Color3.fromRGB(18, 18, 22)

local SHEETS = {
	"rbxassetid://90872052882140",
	"rbxassetid://113275912370174",
	"rbxassetid://109839438885175",
}

local PICTURES = {
	{ sheet = 1, x = 0, y = 0, w = 508, h = 473 }, -- deepwoken mindset
	{ sheet = 1, x = 512, y = 0, w = 508, h = 324 }, -- ships
	{ sheet = 1, x = 0, y = 477, w = 508, h = 329 }, -- permafreshie
	{ sheet = 1, x = 512, y = 477, w = 508, h = 424 }, -- fallen
	{ sheet = 2, x = 0, y = 0, w = 500, h = 500 }, -- flames
	{ sheet = 2, x = 504, y = 0, w = 508, h = 324 }, -- teal's alliance
	{ sheet = 2, x = 0, y = 504, w = 508, h = 254 }, -- chests
	{ sheet = 2, x = 512, y = 504, w = 508, h = 338 }, -- game theory
	{ sheet = 3, x = 0, y = 0, w = 508, h = 287 }, -- lantern room
	{ sheet = 3, x = 512, y = 0, w = 500, h = 500 }, -- envy sero
	{ sheet = 3, x = 0, y = 504, w = 508, h = 275 }, -- titus
}

local train = workspace:WaitForChild("Train")
local canvases = train:WaitForChild("Canvases")
local pivot = workspace:WaitForChild("TrainPivot") :: BasePart
local TRACK_RADIUS = 425.9

local slots = {} -- ImageLabels, in order

local function show(img: ImageLabel, index: number)
	local p = PICTURES[(index - 1) % #PICTURES + 1]
	img.Image = SHEETS[p.sheet]
	img.ImageRectOffset = Vector2.new(p.x, p.y)
	img.ImageRectSize = Vector2.new(p.w, p.h)
end

local function setup(canvas: BasePart)
	local old = canvas:FindFirstChild("Picture")
	if old then
		old:Destroy()
	end
	-- the canvas faces along its X axis; use the side that looks into the wagon
	local flat = Vector3.new(canvas.Position.X - pivot.Position.X, 0, canvas.Position.Z - pivot.Position.Z)
	local inward = if flat.Magnitude > TRACK_RADIUS then -flat.Unit else flat.Unit
	local face = if canvas.CFrame.RightVector:Dot(inward) > 0 then Enum.NormalId.Right else Enum.NormalId.Left

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Picture"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0.3
	gui.Brightness = 1
	gui.ClipsDescendants = true

	-- the surface's own "up" runs sideways on these meshes, so turn the
	-- picture holder to stand upright: world up is the part's look axis
	local up = Vector3.yAxis
	local width = canvas.Size.Y * PIXELS_PER_STUD -- across the wall
	local height = canvas.Size.Z * PIXELS_PER_STUD -- up the wall
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundColor3 = MAT
	holder.BorderSizePixel = 0
	local lookUp = canvas.CFrame.LookVector:Dot(up)
	local sideSign = if face == Enum.NormalId.Right then 1 else -1
	holder.Rotation = if lookUp * sideSign > 0 then 90 else -90
	holder.Parent = gui

	local tall = height > width * 1.2
	local count = if tall then 2 else 1
	for i = 1, count do
		local img = Instance.new("ImageLabel")
		img.Name = "Slot" .. i
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		if tall then
			img.Position = UDim2.fromScale(0.5, if i == 1 then 0.27 else 0.73)
			img.Size = UDim2.fromScale(0.94, 0.44)
		else
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(0.96, 0.94)
		end
		img.Parent = holder
		table.insert(slots, img)
	end
	gui.Parent = canvas
end

for _, model in ipairs(canvases:GetChildren()) do
	local canvas = model:FindFirstChild("Canvas")
	if canvas and canvas:IsA("BasePart") then
		setup(canvas)
	end
end

-- every slot starts on a different picture, then they all move along together
local step = 0
for i, img in ipairs(slots) do
	show(img, i)
end
while true do
	task.wait(SECONDS_PER_PICTURE)
	step += 1
	for i, img in ipairs(slots) do
		local out = TweenService:Create(img, TweenInfo.new(FADE / 2), { ImageTransparency = 1 })
		out.Completed:Connect(function()
			show(img, i + step * #slots)
			TweenService:Create(img, TweenInfo.new(FADE / 2), { ImageTransparency = 0 }):Play()
		end)
		out:Play()
	end
end
