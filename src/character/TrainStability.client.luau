-- Keeps players on their feet while riding the moving train:
-- the train's motion can't knock them over or ragdoll them.
local humanoid = script.Parent:WaitForChild("Humanoid")

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
