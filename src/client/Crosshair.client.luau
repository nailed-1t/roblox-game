-- Replaces the mouse cursor with a small dot in the middle of the screen.
-- (In first person the mouse is locked to the center, so the dot is
-- exactly where the cursor would be.) While the tablet (or the Chime of
-- Conflict cameras) is up, the mouse is free and shown as a plain circle
-- that follows it, instead of Roblox's "you can press this" cursor.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DOT_SIZE = 6 -- pixels
local CURSOR_SIZE = 14 -- the circle cursor on the tablet
local DOT_COLOR = Color3.fromRGB(255, 255, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.IgnoreGuiInset = true -- center on the real screen, not below the top bar
gui.ResetOnSpawn = false
gui.DisplayOrder = 100 -- above the tablet, so the cursor is drawn on top

local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
dot.BackgroundColor3 = DOT_COLOR
dot.BackgroundTransparency = 0.1
dot.BorderSizePixel = 0
dot.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0) -- perfectly round
corner.Parent = dot

-- thin dark outline so it stays visible on bright surfaces
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Color = Color3.new(0, 0, 0)
stroke.Parent = dot

gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Hide the normal cursor (Roblox's camera scripts can turn it back on, so
-- keep it hidden every frame). While the tablet is open the dot becomes a
-- circle that follows the mouse instead (the mouse itself is free then).
local player = Players.LocalPlayer
local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
RunService.RenderStepped:Connect(function()
	local tabletOpen = player:GetAttribute("TabletOpen") == true or player:GetAttribute("ChimeCams") == true
	UserInputService.MouseIconEnabled = false
	if tabletOpen then
		local at = UserInputService:GetMouseLocation() -- screen pixels, same as this gui (IgnoreGuiInset)
		dot.Position = UDim2.fromOffset(at.X, at.Y)
		dot.Size = UDim2.fromOffset(CURSOR_SIZE, CURSOR_SIZE)
		dot.Visible = not touch
	else
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.Visible = true
	end
end)
