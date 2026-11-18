-- Points and the shop.
--   * Points show on the player list (leaderstats) and are saved.
--   * Minesweeper wins pay out: Easy 10, Normal 20, Hard 30. The tablet asks
--     for a game ticket when the first tile is dug and hands it back on a
--     win; a ticket pays once and only after a believable amount of time.
--   * Buying an item takes its price and sets the player attribute
--     Owned_<id> (saved too).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local ShopItems = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ShopItems"))

local REWARDS = { easy = 10, medium = 20, hard = 30 }
local MIN_SECONDS = { easy = 4, medium = 10, hard = 20 } -- faster "wins" aren't real
local STORE_NAME = "Economy_v1"

local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes") or Instance.new("Folder")
remotes.Name = "ShopRemotes"
remotes.Parent = ReplicatedStorage
local function remote(class: string, name: string)
	local r = remotes:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local buyRemote = remote("RemoteFunction", "Buy") :: RemoteFunction
local minesRemote = remote("RemoteFunction", "Mines") :: RemoteFunction

local itemsById = {}
for _, item in ipairs(ShopItems) do
	itemsById[item.id] = item
end

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local loaded = {} -- [player] = true once their save has been read
local tickets = {} -- [player] = { [token] = { level, started } }
local lastCall = {} -- simple rate limit

local function pointsValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Points") :: IntValue?
end

local function save(player: Player)
	if not store or not loaded[player] then
		return
	end
	local points = pointsValue(player)
	local owned = {}
	for id in pairs(itemsById) do
		if player:GetAttribute("Owned_" .. id) then
			table.insert(owned, id)
		end
	end
	local data = { points = points and points.Value or 0, owned = owned }
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, data)
	end)
	if not ok then
		warn("[Economy] couldn't save " .. player.Name .. ": " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local points = Instance.new("IntValue")
	points.Name = "Points"
	points.Value = 0
	points.Parent = stats
	stats.Parent = player
	tickets[player] = {}

	local data = nil
	if store then
		local ok, result = pcall(function()
			return store:GetAsync("player_" .. player.UserId)
		end)
		if ok then
			data = result
		else
			warn("[Economy] couldn't load " .. player.Name .. ": " .. tostring(result))
		end
	end
	if type(data) == "table" then
		points.Value = tonumber(data.points) or 0
		for _, id in ipairs(data.owned or {}) do
			if itemsById[id] then
				player:SetAttribute("Owned_" .. id, true)
			end
		end
	end
	loaded[player] = true
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	loaded[player] = nil
	tickets[player] = nil
	lastCall[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(save, player)
	end
	task.wait(2)
end)

-- autosave every few minutes
task.spawn(function()
	while true do
		task.wait(180)
		for _, player in ipairs(Players:GetPlayers()) do
			save(player)
		end
	end
end)

local function tooFast(player: Player): boolean
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < 0.25 then
		return true
	end
	lastCall[player] = now
	return false
end

buyRemote.OnServerInvoke = function(player: Player, id: any)
	if tooFast(player) then
		return false, "Slow down a little."
	end
	local item = typeof(id) == "string" and itemsById[id]
	if not item then
		return false, "That item doesn't exist."
	end
	if player:GetAttribute("Owned_" .. item.id) then
		return false, "You already own " .. item.name .. "."
	end
	local points = pointsValue(player)
	if not points or not loaded[player] then
		return false, "Your points are still loading."
	end
	if points.Value < item.price then
		return false, string.format("You need %d more points.", item.price - points.Value)
	end
	points.Value -= item.price
	player:SetAttribute("Owned_" .. item.id, true)
	task.spawn(save, player)
	return true, string.format("You bought %s! Press %s to use it.", item.name, item.key)
end

minesRemote.OnServerInvoke = function(player: Player, action: any, data: any)
	local mine = tickets[player]
	if not mine or tooFast(player) then
		return nil
	end
	if action == "start" then
		if typeof(data) ~= "string" or not REWARDS[data] then
			return nil
		end
		-- keep only a few open tickets
		local count = 0
		for token in pairs(mine) do
			count += 1
			if count > 3 then
				mine[token] = nil
			end
		end
		local token = HttpService:GenerateGUID(false)
		mine[token] = { level = data, started = os.clock() }
		return token
	elseif action == "win" then
		local ticket = typeof(data) == "string" and mine[data]
		if not ticket then
			return 0
		end
		mine[data] = nil
		if os.clock() - ticket.started < MIN_SECONDS[ticket.level] then
			return 0
		end
		local points = pointsValue(player)
		if not points then
			return 0
		end
		local reward = REWARDS[ticket.level]
		points.Value += reward
		return reward, points.Value
	end
	return nil
end
