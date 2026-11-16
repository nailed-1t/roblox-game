-- Keeps players steady while riding the moving train:
-- no jumping, and the train's motion can't knock them over or ragdoll them.
local humanoid = script.Parent:WaitForChild("Humanoid")

humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
