-- Draws chess pieces out of simple UI shapes (Roblox fonts don't include
-- the chess symbols). Each piece fills a square Frame; put it inside a board
-- square and it scales with it.

local PieceArt = {}

local FILL = {
	w = Color3.fromRGB(248, 246, 240),
	b = Color3.fromRGB(38, 38, 44),
}
local OUTLINE = {
	w = Color3.fromRGB(40, 36, 32),
	b = Color3.fromRGB(215, 210, 200),
}

local function shape(parent: Instance, color: string, x0: number, y0: number, x1: number, y1: number, round: number?, rotation: number?)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = FILL[color]
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromScale(x1 - x0, y1 - y0)
	f.Rotation = rotation or 0
	if round and round > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE[color]
	s.Thickness = 1.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	f.Parent = parent
	return f
end

local function circle(parent: Instance, color: string, cx: number, cy: number, d: number)
	return shape(parent, color, cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2, 0.5)
end

-- every piece stands on the same base
local function base(p: Instance, color: string)
	shape(p, color, 0.2, 0.8, 0.8, 0.92, 0.35)
	shape(p, color, 0.3, 0.72, 0.7, 0.82, 0.3)
end

local BUILDERS = {
	P = function(p, c)
		base(p, c)
		shape(p, c, 0.37, 0.5, 0.63, 0.74, 0.3)
		circle(p, c, 0.5, 0.4, 0.28)
	end,
	R = function(p, c)
		base(p, c)
		shape(p, c, 0.33, 0.36, 0.67, 0.74, 0.08)
		shape(p, c, 0.27, 0.24, 0.73, 0.38, 0.12)
		shape(p, c, 0.27, 0.14, 0.38, 0.26, 0.15)
		shape(p, c, 0.445, 0.14, 0.555, 0.26, 0.15)
		shape(p, c, 0.62, 0.14, 0.73, 0.26, 0.15)
	end,
	N = function(p, c)
		base(p, c)
		shape(p, c, 0.36, 0.42, 0.66, 0.76, 0.2, -8) -- chest
		shape(p, c, 0.4, 0.18, 0.64, 0.56, 0.3, 18) -- neck
		shape(p, c, 0.2, 0.22, 0.56, 0.38, 0.4, -24) -- muzzle
		shape(p, c, 0.5, 0.09, 0.6, 0.24, 0.4, 20) -- ear
		local eye = circle(p, c, 0.45, 0.27, 0.07)
		eye.BackgroundColor3 = OUTLINE[c]
	end,
	B = function(p, c)
		base(p, c)
		shape(p, c, 0.39, 0.46, 0.61, 0.74, 0.25)
		shape(p, c, 0.33, 0.18, 0.67, 0.56, 0.5) -- mitre
		circle(p, c, 0.5, 0.11, 0.11)
		local slit = shape(p, c, 0.47, 0.24, 0.53, 0.42, 0.5, 35)
		slit.BackgroundColor3 = OUTLINE[c]
	end,
	Q = function(p, c)
		base(p, c)
		shape(p, c, 0.34, 0.4, 0.66, 0.74, 0.15)
		shape(p, c, 0.25, 0.28, 0.75, 0.42, 0.25)
		for i, x in ipairs({ 0.27, 0.385, 0.5, 0.615, 0.73 }) do
			circle(p, c, x, if i == 3 then 0.15 else 0.22, 0.11)
		end
	end,
	K = function(p, c)
		base(p, c)
		shape(p, c, 0.34, 0.4, 0.66, 0.74, 0.15)
		shape(p, c, 0.27, 0.27, 0.73, 0.42, 0.3)
		shape(p, c, 0.455, 0.04, 0.545, 0.29, 0.2) -- cross upright
		shape(p, c, 0.37, 0.1, 0.63, 0.18, 0.3) -- cross bar
	end,
}

-- Returns a Frame (size 1x1 of its parent) showing the piece, e.g. make("wK").
function PieceArt.make(code: string): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Piece"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	local color = string.sub(code, 1, 1)
	local kind = string.sub(code, 2, 2)
	local build = BUILDERS[kind]
	if build then
		build(holder, color)
	end
	return holder
end

return PieceArt
