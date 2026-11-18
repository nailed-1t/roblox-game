-- Publishes workspace.ShopCamera's CFrame as a workspace attribute so every
-- client knows where the Shop app should fly the camera, even when the part
-- itself isn't streamed in. Move the ShopCamera part in Studio to change it.

local spot = workspace:WaitForChild("ShopCamera") :: BasePart

local function publish()
	workspace:SetAttribute("ShopCameraCFrame", spot.CFrame)
end
publish()
spot:GetPropertyChangedSignal("CFrame"):Connect(publish)
