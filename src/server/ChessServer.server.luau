-- Connects the tablet's Chess app to the ChessManager.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Manager = require(script.Parent:WaitForChild("ChessManager"))
local ChessBot = require(script.Parent:WaitForChild("ChessBot"))
local event = ReplicatedStorage:WaitForChild("TabletRemotes"):WaitForChild("ChessEvent") :: RemoteEvent

local manager = Manager.new(function(player, action, data)
	if player and typeof(player) == "Instance" and player.Parent then
		event:FireClient(player, action, data)
	end
end, function(userId)
	return Players:GetPlayerByUserId(userId)
end, {
	-- the winner's points (leaderstats are saved by the Economy script)
	reward = function(player, amount)
		local stats = player:FindFirstChild("leaderstats")
		local points = stats and stats:FindFirstChild("Points")
		if points then
			points.Value += amount
		end
	end,
	listPlayers = function()
		return Players:GetPlayers()
	end,
	-- the computer thinks in its own thread, a few milliseconds per frame
	think = function(_, fn)
		task.spawn(function()
			task.wait(0.4) -- a short pause so its moves don't feel instant
			local ok, err = pcall(fn, function()
				task.wait()
			end)
			if not ok then
				warn("[Chess] computer error:", err)
			end
		end)
	end,
	chooseMove = ChessBot.choose,
})

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

-- clocks and challenge timeouts
task.spawn(function()
	while true do
		task.wait(0.2)
		manager:tick()
	end
end)
