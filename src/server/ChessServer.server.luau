-- Connects the tablet's Chess app to the ChessManager.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Manager = require(script.Parent:WaitForChild("ChessManager"))
local event = ReplicatedStorage:WaitForChild("TabletRemotes"):WaitForChild("ChessEvent") :: RemoteEvent

local manager = Manager.new(function(player, action, data)
	if player and player.Parent then
		event:FireClient(player, action, data)
	end
end, function(userId)
	return Players:GetPlayerByUserId(userId)
end)

-- up to 10 messages per second per player is plenty for chess; ignore spam
local window: { [number]: { start: number, count: number } } = {}

event.OnServerEvent:Connect(function(player, action, data)
	local t = os.clock()
	local w = window[player.UserId]
	if not w or t - w.start >= 1 then
		w = { start = t, count = 0 }
		window[player.UserId] = w
	end
	w.count += 1
	if w.count > 10 then
		return
	end
	local ok, err = pcall(manager.handle, manager, player, action, data)
	if not ok then
		warn("[Chess] error handling", action, "from", player.Name, ":", err)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	window[player.UserId] = nil
	manager:playerLeft(player)
end)

task.spawn(function()
	while true do
		task.wait(1)
		manager:tick()
	end
end)
