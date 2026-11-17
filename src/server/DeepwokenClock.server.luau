-- Shows how long it has been since Deepwoken last updated, on the
-- "clock screen" model, counting up every second.
--
-- The time of the last update is read from Roblox (the same "Updated" date
-- shown on Deepwoken's game page) and re-checked every few minutes, so the
-- counter resets by itself when Deepwoken updates.
-- Needs Game Settings > Security > Allow HTTP Requests turned on.
--
-- To use your own date instead (for example the last big content update
-- rather than the last hotfix), set the "LastUpdateOverride" attribute on the
-- clock screen to an ISO date such as 2026-11-01T18:00:00Z.

local HttpService = game:GetService("HttpService")

local DEEPWOKEN_PLACE_ID = 4111023553
local REFRESH_SECONDS = 300
-- Roblox's own web APIs can't be called from game servers directly, so this
-- goes through roproxy.com, a public mirror of them.
local UNIVERSE_URL = "https://apis.roproxy.com/universes/v1/places/%d/universe"
local GAMES_URL = "https://games.roproxy.com/v1/games?universeIds=%d"

local screen = workspace:WaitForChild("Scenery"):WaitForChild("clock screen") :: BasePart
local gui = screen:WaitForChild("UpdateDisplay") :: SurfaceGui
local timerLabel = gui:WaitForChild("Timer") :: TextLabel
local subLabel = gui:WaitForChild("Since") :: TextLabel

local lastUpdate: number? = nil -- unix seconds
local status = "Checking Roblox..."

local function fetchJson(url: string)
	local ok, body = pcall(HttpService.GetAsync, HttpService, url)
	if not ok then
		warn("[DeepwokenClock] request failed:", body)
		return nil
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	return if decoded then data else nil
end

local universeId: number? = nil
local function refresh()
	local override = screen:GetAttribute("LastUpdateOverride")
	if typeof(override) == "string" and override ~= "" then
		local ok, dt = pcall(DateTime.fromIsoDate, override)
		if ok and dt then
			lastUpdate = dt.UnixTimestamp
			status = "since " .. dt:FormatUniversalTime("LL", "en-us")
			return
		end
	end

	if not universeId then
		local data = fetchJson(string.format(UNIVERSE_URL, DEEPWOKEN_PLACE_ID))
		universeId = data and data.universeId
		if not universeId then
			status = "Can't reach Roblox right now"
			return
		end
	end

	local data = fetchJson(string.format(GAMES_URL, universeId))
	local info = data and data.data and data.data[1]
	local updated = info and info.updated
	if typeof(updated) == "string" then
		local ok, dt = pcall(DateTime.fromIsoDate, updated)
		if ok and dt then
			lastUpdate = dt.UnixTimestamp
			status = "since " .. dt:FormatUniversalTime("LL", "en-us")
			screen:SetAttribute("LastUpdateFromRoblox", updated)
			return
		end
	end
	status = "Can't reach Roblox right now"
end

local function format(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	return string.format("%dd %02dh %02dm %02ds", days, hours, minutes, secs)
end

task.spawn(function()
	while true do
		refresh()
		task.wait(REFRESH_SECONDS)
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
