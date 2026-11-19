-- The jumping fish. Every so often the server announces a jump (workspace
-- attributes below); every client shows it, both in the 3D fish tank and in
-- the tablet's Fish Tank app. Clicking the fish while it's in the air pays
-- 10 points, once per jump per player (ShopRemotes.CatchFish).
--   FishJumpId     counts up with every jump
--   FishJumpAt     server time (workspace:GetServerTimeNow()) it starts
--   FishJumpLength seconds it's in the air
--   FishJumpAngle  which rim of the 3D tank it leaps from, to the opposite rim (degrees)
--   FishJumpEdge   which side of the tablet screen (0 bottom, 1 left, 2 right, 3 top)
--   FishJumpPos    where along that side (0..1)
--   FishJumpFish   which of the three 3D fish jumps (1..3)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REWARD = 10
local LENGTH = 3.2 -- time to fly across the tank
local GAP = { 4, 9 } -- seconds between jumps
local LATE = 0.6 -- allowance for the click travelling to the server

local remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local catchRemote = remotes:FindFirstChild("CatchFish") or Instance.new("RemoteFunction")
catchRemote.Name = "CatchFish"
catchRemote.Parent = remotes

local rng = Random.new()
local current = { id = 0, at = 0, length = LENGTH }
local caught = {} -- [player] = id of the last jump they caught

local function jump()
	current = {
		id = current.id + 1,
		at = workspace:GetServerTimeNow() + 0.5, -- a moment for it to reach everyone
		length = LENGTH,
	}
	workspace:SetAttribute("FishJumpLength", current.length)
	workspace:SetAttribute("FishJumpAngle", rng:NextNumber(0, 360))
	workspace:SetAttribute("FishJumpEdge", rng:NextInteger(0, 3))
	workspace:SetAttribute("FishJumpPos", rng:NextNumber(0.2, 0.8))
	workspace:SetAttribute("FishJumpFish", rng:NextInteger(1, 3))
	workspace:SetAttribute("FishJumpAt", current.at)
	workspace:SetAttribute("FishJumpId", current.id) -- set last: clients watch this one
end

catchRemote.OnServerInvoke = function(player: Player, id: any)
	if id ~= current.id or caught[player] == id then
		return 0
	end
	local now = workspace:GetServerTimeNow()
	if now < current.at - 0.2 or now > current.at + current.length + LATE then
		return 0
	end
	local stats = player:FindFirstChild("leaderstats")
	local points = stats and stats:FindFirstChild("Points")
	if not points then
		return 0
	end
	caught[player] = id
	points.Value += REWARD
	return REWARD, points.Value
end

Players.PlayerRemoving:Connect(function(player)
	caught[player] = nil
end)

task.wait(3)
while true do
	jump()
	task.wait(LENGTH + rng:NextNumber(GAP[1], GAP[2]))
end
