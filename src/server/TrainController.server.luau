-- Spins the train around the circular track and lets players ride it.
-- The train cars are welded to an invisible Root part at the track's center,
-- which a motorized HingeConstraint turns. Because it's real physics,
-- seated players are carried smoothly with the train.

local train = workspace:WaitForChild("Train")
local root: BasePart = train:WaitForChild("Root")
local motor: HingeConstraint = root:WaitForChild("Motor")
local seats = train:WaitForChild("Seats")
local pad: BasePart = workspace:WaitForChild("BoardTrainPad")
local prompt: ProximityPrompt = pad:WaitForChild("BoardPrompt")

local TRACK_RADIUS = 105 -- studs from the center to the cars
local DIRECTION = 1 -- flip to -1 to reverse

-- The server simulates the train so every player sees the same thing.
root:SetNetworkOwner(nil)

local function applySpeed()
	local speed = train:GetAttribute("Speed") or 20 -- studs per second
	motor.AngularVelocity = DIRECTION * speed / TRACK_RADIUS
end
applySpeed()
train:GetAttributeChangedSignal("Speed"):Connect(applySpeed)

-- Boarding: use the prompt on the orange pad to get a free seat.
local function findFreeSeat(): Seat?
	for _, seat in ipairs(seats:GetChildren()) do
		if seat:IsA("Seat") and seat.Occupant == nil then
			return seat
		end
	end
	return nil
end

prompt.Triggered:Connect(function(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then
		return
	end
	local seat = findFreeSeat()
	if seat then
		seat:Sit(humanoid)
	end
end)

-- Leaving: when a rider jumps out, put them back on the boarding pad
-- instead of dropping them on the track.
for _, seat in ipairs(seats:GetChildren()) do
	if seat:IsA("Seat") then
		local lastOccupant: Humanoid? = nil
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			if occupant then
				lastOccupant = occupant
				return
			end
			local humanoid = lastOccupant
			lastOccupant = nil
			if humanoid and humanoid.Parent and humanoid.Health > 0 then
				local hrp = humanoid.Parent:FindFirstChild("HumanoidRootPart")
				if hrp then
					task.defer(function()
						hrp.AssemblyLinearVelocity = Vector3.zero
						humanoid.Parent:PivotTo(pad.CFrame + Vector3.new(0, 4, 0))
					end)
				end
			end
		end)
	end
end
