-- Shows how long it has been since Deepwoken last updated, on the
-- "clock screen" model, counting up every second.
--
-- The time of the last update is read from Roblox (the same "Updated" date
-- shown on Deepwoken's game page) and re-checked every few minutes, so the
-- counter resets by itself when Deepwoken updates.
-- Needs Game Settings > Security > Allow HTTP Requests turned on.
--
-- Roblox's web APIs can't be called from game servers directly, so this goes
-- through roproxy.com, a free public mirror shared by many games. It often
-- answers "too many requests" (HTTP 429), so the clock never depends on a
-- single request: it keeps the last date it knew (saved in a DataStore and in
-- the screen's "LastKnownUpdate" attribute) and keeps showing that while it
-- retries in the background.
--
-- To use your own date instead (for example the last big content update
-- rather than the last hotfix), set the "LastUpdateOverride" attribute on the
-- clock screen to an ISO date such as 2026-11-01T18:00:00Z.

local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local DEEPWOKEN_PLACE_ID = 4111023553
local REFRESH_SECONDS = 300 -- after a successful check
local RETRY_MIN, RETRY_MAX = 30, 600 -- after a failed check (doubles each time)
local UNIVERSE_URL = "https://apis.roproxy.com/universes/v1/places/%d/universe"
local GAMES_URL = "https://games.roproxy.com/v1/games?universeIds=%d"

local screen = workspace:WaitForChild("Scenery"):WaitForChild("clock screen") :: BasePart
local gui = screen:WaitForChild("UpdateDisplay") :: SurfaceGui
local timerLabel = gui:WaitForChild("Timer") :: TextLabel
local subLabel = gui:WaitForChild("Since") :: TextLabel

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("DeepwokenClock")
end)

local lastUpdate: number? = nil -- unix seconds
local status = "Checking Roblox..."

local function setFromIso(iso: string): boolean
	local ok, dt = pcall(DateTime.fromIsoDate, iso)
	if ok and dt then
		lastUpdate = dt.UnixTimestamp
		status = "since " .. dt:FormatUniversalTime("LL", "en-us")
		return true
	end
	return false
end

-- Start from the best date we already know, so the screen never sits empty.
local function loadKnown()
	local known = screen:GetAttribute("LastKnownUpdate")
	if store then
		local ok, saved = pcall(store.GetAsync, store, "lastUpdate")
		if ok and typeof(saved) == "string" then
			known = saved
		end
	end
	if typeof(known) == "string" and known ~= "" then
		setFromIso(known)
	end
end

local function remember(iso: string)
	if screen:GetAttribute("LastKnownUpdate") == iso then
		return
	end
	screen:SetAttribute("LastKnownUpdate", iso)
	if store then
		pcall(store.SetAsync, store, "lastUpdate", iso)
	end
end

local function fetchJson(url: string)
	local ok, body = pcall(HttpService.GetAsync, HttpService, url)
	if not ok then
		return nil, body
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	return if decoded then data else nil, "bad response"
end

local universeId: number? = screen:GetAttribute("DeepwokenUniverseId")

-- Returns true if the date was refreshed from Roblox.
local function refresh(): boolean
	local override = screen:GetAttribute("LastUpdateOverride")
	if typeof(override) == "string" and override ~= "" and setFromIso(override) then
		return true
	end

	if not universeId then
		local data, err = fetchJson(string.format(UNIVERSE_URL, DEEPWOKEN_PLACE_ID))
		universeId = data and data.universeId
		if not universeId then
			warn("[DeepwokenClock] couldn't look up Deepwoken:", err)
			return false
		end
		screen:SetAttribute("DeepwokenUniverseId", universeId)
	end

	local data, err = fetchJson(string.format(GAMES_URL, universeId))
	local info = data and data.data and data.data[1]
	local updated = info and info.updated
	if typeof(updated) == "string" and setFromIso(updated) then
		remember(updated)
		return true
	end
	warn("[DeepwokenClock] couldn't check Deepwoken's update time:", err)
	return false
end

local function format(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	return string.format("%dd %02dh %02dm %02ds", days, hours, minutes, secs)
end

loadKnown()

task.spawn(function()
	local retry = RETRY_MIN
	while true do
		if refresh() then
			retry = RETRY_MIN
			task.wait(REFRESH_SECONDS)
		else
			-- keep showing the last known date; try again later, a bit
			-- randomised so many servers don't all retry at once
			if not lastUpdate then
				status = "Can't reach Roblox right now"
			end
			task.wait(retry + math.random() * 10)
			retry = math.min(retry * 2, RETRY_MAX)
		end
	end
end)

-- Re-read straight away if someone changes the override in Studio.
screen:GetAttributeChangedSignal("LastUpdateOverride"):Connect(refresh)

while true do
	if lastUpdate then
		timerLabel.Text = format(os.time() - lastUpdate)
	else
		timerLabel.Text = "--d --h --m --s"
	end
	subLabel.Text = status
	task.wait(1)
end
