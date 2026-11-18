-- Hangs the pictures on the train's canvases (Train.Canvases): one picture
-- per canvas. A canvas model's "Picture" attribute picks which one (index in
-- PICTURES below); canvases without it get the pictures nobody has picked.
-- If there are ever more pictures than canvases, the canvases slowly cycle
-- so every picture still gets shown. The pictures are packed on three
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

local function show(img: ImageLabel, index: number)
	local p = PICTURES[(index - 1) % #PICTURES + 1]
	img.Image = SHEETS[p.sheet]
	img.ImageRectOffset = Vector2.new(p.x, p.y)
	img.ImageRectSize = Vector2.new(p.w, p.h)
end

local function setup(canvas: BasePart): ImageLabel
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

	-- work out which of the part's axes runs up the wall, then turn the
	-- picture so it stands upright
	local cf = canvas.CFrame
	local yUp = math.abs(cf.UpVector.Y) > math.abs(cf.LookVector.Y)
	local width = (if yUp then canvas.Size.Z else canvas.Size.Y) * PIXELS_PER_STUD
	local height = (if yUp then canvas.Size.Y else canvas.Size.Z) * PIXELS_PER_STUD
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundColor3 = MAT
	holder.BorderSizePixel = 0
	local sideSign = if face == Enum.NormalId.Right then 1 else -1
	if yUp then
		holder.Rotation = if cf.UpVector.Y > 0 then 0 else 180
	else
		holder.Rotation = if cf.LookVector.Y * sideSign > 0 then 90 else -90
	end
	holder.Parent = gui

	local img = Instance.new("ImageLabel")
	img.Name = "Image"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(0.96, 0.94)
	img.Parent = holder
	gui.Parent = canvas
	return img
end

-- give every canvas a picture
local slots = {}
local taken = {}
local unpicked = {}
for _, model in ipairs(canvases:GetChildren()) do
	local canvas = model:FindFirstChild("Canvas")
	if canvas and canvas:IsA("BasePart") then
		local img = setup(canvas)
		local pick = model:GetAttribute("Picture")
		if typeof(pick) == "number" and PICTURES[pick] and not taken[pick] then
			taken[pick] = true
			table.insert(slots, { img = img, index = pick })
		else
			table.insert(unpicked, img)
		end
	end
end
local nextFree = 1
for _, img in ipairs(unpicked) do
	while taken[nextFree] and nextFree <= #PICTURES do
		nextFree += 1
	end
	local index = if nextFree <= #PICTURES then nextFree else (#slots % #PICTURES) + 1
	taken[index] = true
	table.insert(slots, { img = img, index = index })
end
for _, slot in ipairs(slots) do
	show(slot.img, slot.index)
end

-- more pictures than canvases: cycle slowly so all of them get a turn
if #slots > 0 and #slots < #PICTURES then
	local step = 0
	while true do
		task.wait(SECONDS_PER_PICTURE)
		step += 1
		for _, slot in ipairs(slots) do
			local out = TweenService:Create(slot.img, TweenInfo.new(FADE / 2), { ImageTransparency = 1 })
			out.Completed:Connect(function()
				show(slot.img, slot.index + step * #slots)
				TweenService:Create(slot.img, TweenInfo.new(FADE / 2), { ImageTransparency = 0 }):Play()
			end)
			out:Play()
		end
	end
end
