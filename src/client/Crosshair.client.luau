-- Replaces the mouse cursor with a small dot in the middle of the screen.
-- (In first person the mouse is locked to the center, so the dot is
-- exactly where the cursor would be.)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DOT_SIZE = 6 -- pixels
local DOT_COLOR = Color3.fromRGB(255, 255, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.IgnoreGuiInset = true -- center on the real screen, not below the top bar
gui.ResetOnSpawn = false
gui.DisplayOrder = 10

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

-- Hide the normal arrow cursor (Roblox's camera scripts can turn it back on,
-- so keep it hidden every frame). While the tablet is open, show the normal
-- cursor instead so you can tap its buttons.
local player = Players.LocalPlayer
RunService.RenderStepped:Connect(function()
	local tabletOpen = player:GetAttribute("TabletOpen") == true
	UserInputService.MouseIconEnabled = tabletOpen
	dot.Visible = not tabletOpen
end)
