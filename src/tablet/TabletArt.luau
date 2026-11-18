-- Pictures for the tablet (app icons, Minesweeper mines/flags/faces), all on
-- one sprite sheet: assets/tablet-art.png in the repo, 1024x256, 128x128
-- cells. Set the "SheetImage" attribute on this ModuleScript to the uploaded
-- image id. Without it, callers fall back to simple text/emoji.

local TabletArt = {}

local CELL = 128
local COLUMNS = 8
local INDEX = {
	mine = 0,
	flag = 1,
	wrong = 2,
	boom = 3,
	happy = 4,
	dead = 5,
	cool = 6,
	wow = 7,
	appMines = 8,
	appChess = 9,
	appShop = 10,
	stopwatch = 11,
}

function TabletArt.sheet(): string?
	local id = script:GetAttribute("SheetImage")
	if typeof(id) == "number" then
		id = tostring(id)
	end
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	if not string.find(id, "://") then
		id = "rbxassetid://" .. id
	end
	return id
end

-- Points an ImageLabel/ImageButton at one picture. Returns false if the
-- sheet isn't set up (or the name is unknown).
function TabletArt.apply(target: ImageLabel | ImageButton, name: string): boolean
	local sheet = TabletArt.sheet()
	local i = INDEX[name]
	if not sheet or not i then
		return false
	end
	target.Image = sheet
	target.ImageRectOffset = Vector2.new((i % COLUMNS) * CELL, math.floor(i / COLUMNS) * CELL)
	target.ImageRectSize = Vector2.new(CELL, CELL)
	target.ScaleType = Enum.ScaleType.Fit
	return true
end

-- A transparent ImageLabel showing one picture, or nil without the sheet.
function TabletArt.image(name: string): ImageLabel?
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	if not TabletArt.apply(img, name) then
		img:Destroy()
		return nil
	end
	return img
end

return TabletArt
