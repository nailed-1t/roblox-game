-- Chess challenges and games, between players or against the computer. The
-- server is in charge: every move is checked with ChessRules, so nobody can
-- cheat, and the clocks run here.
--
-- Modes (like chess.com): a time control and a variant.
--   time:    "bullet" 1|0, "blitz" 3|2, "rapid" 10|0, "none" (no clock)
--   variant: "standard", "chess960", "koth" (King of the Hill), "threecheck"
-- Games against the computer have no clock.
--
-- The winner gets 50 points. A win by resignation, timeout or the other
-- player leaving only pays once 10 moves have been played (so two friends
-- can't farm points by resigning straight away).
--
-- Anyone else can watch a game that is going on (spectate).
--
-- Messages to clients (action, data):
--   "invite"      someone challenged you        {from, name, seconds, mode, modeName}
--   "inviteGone"  that challenge was withdrawn   {from, reason}
--   "outgoing"    your challenge's status        {to, name, status = waiting|declined|expired|busy|cancelled, mode, modeName}
--   "state"       the game you are in or watching  game snapshot (see snapshot())
--   "noGame"      you are not in or watching a game
--   "games"       live games you could watch     { {id, white, black, modeName, moves, bot} }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChessRules = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ChessRules"))

local INVITE_SECONDS = 30
local FIRST_MOVE_SECONDS = 30 -- timed games are called off if a first move takes longer
local REWARD = 50
local MIN_MOVES_FOR_EASY_WIN = 10 -- half-moves before resign/timeout/leaving wins pay

local TIMES = {
	bullet = { seconds = 60, increment = 0, name = "Bullet 1|0" },
	blitz = { seconds = 180, increment = 2, name = "Blitz 3|2" },
	rapid = { seconds = 600, increment = 0, name = "Rapid 10|0" },
	none = { name = "No clock" },
}
local VARIANTS = { standard = true, chess960 = true, koth = true, threecheck = true }
local LEVELS = { easy = "Easy", medium = "Medium", hard = "Hard" }

local Manager = {}
Manager.__index = Manager
Manager.TIMES = TIMES
Manager.REWARD = REWARD

export type SendFn = (player: any, action: string, data: any) -> ()
export type FindFn = (userId: number) -> any

-- options:
--   reward(player, amount)        pays the winner (returns nothing)
--   listPlayers() -> {player}     everyone, for the live games list
--   think(game, fn)               runs the computer's move-finding (the server
--                                 runs it in its own thread); defaults to
--                                 calling fn right away
--   chooseMove(state, level, pause) -> Move?   the computer (ChessBot.choose)
function Manager.new(send: SendFn, findPlayer: FindFn, options: { [string]: any }?)
	local self = setmetatable({}, Manager)
	options = options or {}
	self.send = send
	self.findPlayer = findPlayer
	self.reward = options.reward or function() end
	self.listPlayers = options.listPlayers or function()
		return {}
	end
	self.think = options.think or function(_, fn)
		fn()
	end
	self.chooseMove = options.chooseMove
	self.invites = {} -- [challengerId] = { from = player, to = player, expires = number, mode = mode }
	self.playerGame = {} -- [userId] = game
	self.watching = {} -- [userId] = game being watched
	self.games = {} -- [id] = game
	self.nextId = 0
	self.now = os.clock
	return self
end

local function nameOf(player): string
	return player.DisplayName or player.Name
end

local function isPlaying(self, userId: number): boolean
	local g = self.playerGame[userId]
	return g ~= nil and not g.over
end

-- a valid mode from whatever the client sent
function Manager.mode(raw: any): { time: string, variant: string }
	raw = if type(raw) == "table" then raw else {}
	local time = if type(raw.time) == "string" and TIMES[raw.time] then raw.time else "rapid"
	local variant = if type(raw.variant) == "string" and VARIANTS[raw.variant] then raw.variant else "standard"
	return { time = time, variant = variant }
end

function Manager.modeName(mode): string
	local t = TIMES[mode.time].name
	if mode.variant == "standard" then
		return t
	end
	return t .. " · " .. ChessRules.VARIANT_NAMES[mode.variant]
end

---------------------------------------------------------------- clocks

local function clockRunning(g): boolean
	-- each side's clock starts after their first move
	return g.clock ~= nil and not g.over and #g.moves >= 2
end

-- seconds left for each side right now
function Manager:clocks(g): { w: number, b: number }?
	if not g.clock then
		return nil
	end
	local w, b = g.clock.w, g.clock.b
	if clockRunning(g) then
		local used = self.now() - g.turnStart
		if g.state.turn == "w" then
			w -= used
		else
			b -= used
		end
	end
	return { w = math.max(0, w), b = math.max(0, b) }
end

local function onlyKing(board, color: string): boolean
	for r = 1, 8 do
		for c = 1, 8 do
			local p = board[r][c]
			if p ~= "" and string.sub(p, 1, 1) == color and p ~= color .. "K" then
				return false
			end
		end
	end
	return true
end

---------------------------------------------------------------- snapshots

function Manager:snapshot(g)
	local s = g.state
	local clocks = self:clocks(g)
	local spectators = 0
	for _, watched in pairs(self.watching) do
		if watched == g then
			spectators += 1
		end
	end
	return {
		id = g.id,
		white = { id = g.white.UserId, name = nameOf(g.white), bot = g.white.isBot == true },
		black = { id = g.black.UserId, name = nameOf(g.black), bot = g.black.isBot == true },
		board = s.board,
		turn = s.turn,
		castling = s.castling,
		ep = s.ep,
		halfmove = s.halfmove,
		fullmove = s.fullmove,
		variant = s.variant,
		kingFile = s.kingFile,
		rookFiles = s.rookFiles,
		checks = s.checks,
		mode = g.mode,
		modeName = g.modeName,
		clock = if clocks then { w = clocks.w, b = clocks.b, running = if clockRunning(g) then s.turn else nil } else nil,
		moves = g.moves,
		last = g.last,
		over = g.over,
		result = g.result, -- "white", "black", "draw" or nil
		reason = g.reason, -- "checkmate", "resign", "left", "stalemate", "fifty", "material",
		-- "hill", "threecheck", "timeout", "timeoutdraw", "agreement", "aborted"
		inCheck = ChessRules.inCheck(s, s.turn),
		drawOffer = g.drawOffer, -- "w"/"b": that side offered a draw
		spectators = spectators,
		rewards = g.rewards, -- [tostring(userId)] = points won
	}
end

function Manager:broadcast(g)
	local snap = self:snapshot(g)
	for _, p in ipairs({ g.white, g.black }) do
		if not p.isBot and self.playerGame[p.UserId] == g then
			self.send(p, "state", snap)
		end
	end
	for userId, watched in pairs(self.watching) do
		if watched == g then
			local p = self.findPlayer(userId)
			if p then
				self.send(p, "state", snap)
			end
		end
	end
end

function Manager:gamesList()
	local list = {}
	for _, g in pairs(self.games) do
		if not g.over then
			table.insert(list, {
				id = g.id,
				white = nameOf(g.white),
				black = nameOf(g.black),
				modeName = g.modeName,
				moves = #g.moves,
				bot = g.white.isBot == true or g.black.isBot == true,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

function Manager:sendGames(to)
	local list = self:gamesList()
	if to then
		self.send(to, "games", list)
		return
	end
	for _, p in ipairs(self.listPlayers()) do
		self.send(p, "games", list)
	end
end

---------------------------------------------------------------- challenges

-- Withdraws every challenge sent by or to this player.
function Manager:clearInvites(player, reason: string)
	for fromId, inv in pairs(self.invites) do
		if inv.from == player then
			self.invites[fromId] = nil
			self.send(inv.to, "inviteGone", { from = fromId, reason = reason })
		elseif inv.to == player then
			self.invites[fromId] = nil
			self.send(inv.from, "outgoing", { to = inv.to.UserId, name = nameOf(inv.to), status = reason })
		end
	end
end

function Manager:stopWatching(player)
	if self.watching[player.UserId] then
		local g = self.watching[player.UserId]
		self.watching[player.UserId] = nil
		if not g.over then
			self:broadcast(g) -- spectator count changed
		end
	end
end

---------------------------------------------------------------- games

function Manager:startGame(a, b, mode, whiteFirst: boolean?)
	self:clearInvites(a, "busy")
	if not b.isBot then
		self:clearInvites(b, "busy")
	end
	self:stopWatching(a)
	if not b.isBot then
		self:stopWatching(b)
	end
	self.nextId += 1
	if whiteFirst == nil then
		whiteFirst = math.random() < 0.5
	end
	local time = TIMES[mode.time]
	local g = {
		id = self.nextId,
		white = if whiteFirst then a else b,
		black = if whiteFirst then b else a,
		state = ChessRules.newGame(mode.variant, math.random(1, 2 ^ 30)),
		mode = mode,
		modeName = Manager.modeName(mode),
		clock = if time.seconds then { w = time.seconds, b = time.seconds } else nil,
		increment = time.increment or 0,
		turnStart = self.now(),
		moves = {},
		last = nil,
		over = false,
		rewards = {},
	}
	self.games[g.id] = g
	self.playerGame[a.UserId] = g
	if not b.isBot then
		self.playerGame[b.UserId] = g
	end
	self:broadcast(g)
	self:sendGames()
	self:botTurn(g)
	return g
end

function Manager:finish(g, result: string, reason: string)
	if g.over then
		return
	end
	-- stop the clock where it was
	if g.clock then
		local left = self:clocks(g)
		if left then
			g.clock.w, g.clock.b = left.w, left.b
		end
	end
	g.over = true
	g.result = result
	g.reason = reason
	g.drawOffer = nil
	if result == "white" or result == "black" then
		local winner = if result == "white" then g.white else g.black
		local decisive = ChessRules.WINS[reason] == true
		if not winner.isBot and (decisive or #g.moves >= MIN_MOVES_FOR_EASY_WIN) then
			g.rewards[tostring(winner.UserId)] = REWARD
			self.reward(winner, REWARD)
		end
	end
	self:broadcast(g)
	self:sendGames()
end

-- plays a legal move for `color` and moves the game on
function Manager:play(g, color: string, move)
	local t = self.now()
	if clockRunning(g) then
		local left = g.clock[color] - (t - g.turnStart)
		if left <= 0 then
			self:flag(g, color)
			return
		end
		g.clock[color] = left + g.increment
	end
	g.turnStart = t
	local before = g.state
	g.state = ChessRules.apply(before, move)
	table.insert(g.moves, ChessRules.notation(before, move, g.state))
	g.last = { fr = move.fr, fc = move.fc, tr = move.tr, tc = move.tc }
	if g.drawOffer and g.drawOffer ~= color then
		g.drawOffer = nil -- moving instead of answering declines the offer
	end
	local status = ChessRules.status(g.state)
	if ChessRules.WINS[status] then
		self:finish(g, if color == "w" then "white" else "black", status)
	elseif status ~= "playing" then
		self:finish(g, "draw", status)
	else
		self:broadcast(g)
		self:botTurn(g)
	end
end

-- `color` ran out of time
function Manager:flag(g, color: string)
	local winnerColor = ChessRules.other(color)
	if onlyKing(g.state.board, winnerColor) then
		self:finish(g, "draw", "timeoutdraw") -- the other side can't win anyway
	else
		self:finish(g, if winnerColor == "w" then "white" else "black", "timeout")
	end
end

-- if it's the computer's move, let it think
function Manager:botTurn(g)
	local bot = if g.state.turn == "w" then g.white else g.black
	if g.over or not bot.isBot or not self.chooseMove then
		return
	end
	local stateNow = g.state
	self.think(g, function(pause)
		if g.over or g.state ~= stateNow then
			return
		end
		local move = self.chooseMove(stateNow, bot.level, pause)
		if move and not g.over and g.state == stateNow then
			self:play(g, stateNow.turn, move)
		end
	end)
end

local function int(v)
	return if type(v) == "number" and v == math.floor(v) then v else nil
end

function Manager:handle(player, action: string, data: any)
	if type(action) ~= "string" then
		return
	end
	data = if type(data) == "table" then data else {}

	if action == "challenge" then
		local target = if type(data.target) == "number" then self.findPlayer(data.target) else nil
		if not target or target == player then
			return
		end
		if isPlaying(self, player.UserId) then
			return
		end
		local mode = Manager.mode(data.mode)
		if isPlaying(self, target.UserId) then
			self.send(player, "outgoing", { to = target.UserId, name = nameOf(target), status = "busy" })
			return
		end
		-- they already challenged you? then this is an accept (with their mode)
		local theirs = self.invites[target.UserId]
		if theirs and theirs.to == player then
			self:startGame(target, player, theirs.mode)
			return
		end
		-- one outgoing challenge at a time
		local old = self.invites[player.UserId]
		if old then
			self.send(old.to, "inviteGone", { from = player.UserId, reason = "cancelled" })
		end
		self.invites[player.UserId] = { from = player, to = target, expires = self.now() + INVITE_SECONDS, mode = mode }
		local modeName = Manager.modeName(mode)
		self.send(target, "invite", { from = player.UserId, name = nameOf(player), seconds = INVITE_SECONDS, mode = mode, modeName = modeName })
		self.send(player, "outgoing", { to = target.UserId, name = nameOf(target), status = "waiting", seconds = INVITE_SECONDS, mode = mode, modeName = modeName })
	elseif action == "cancel" then
		local inv = self.invites[player.UserId]
		if inv then
			self.invites[player.UserId] = nil
			self.send(inv.to, "inviteGone", { from = player.UserId, reason = "cancelled" })
			self.send(player, "outgoing", { to = inv.to.UserId, name = nameOf(inv.to), status = "cancelled" })
		end
	elseif action == "respond" then
		local inv = if type(data.from) == "number" then self.invites[data.from] else nil
		if not inv or inv.to ~= player then
			return
		end
		self.invites[data.from] = nil
		if data.accept == true then
			if isPlaying(self, player.UserId) or isPlaying(self, inv.from.UserId) then
				self.send(inv.from, "outgoing", { to = player.UserId, name = nameOf(player), status = "busy" })
				return
			end
			self:startGame(inv.from, player, inv.mode)
		else
			self.send(inv.from, "outgoing", { to = player.UserId, name = nameOf(player), status = "declined" })
		end
	elseif action == "computer" then
		if isPlaying(self, player.UserId) then
			return
		end
		local level = if type(data.level) == "string" and LEVELS[data.level] then data.level else "medium"
		local mode = Manager.mode(data.mode)
		mode.time = "none" -- the computer plays without a clock
		self.nextId += 1
		local bot = {
			UserId = -self.nextId, -- never a real player's id
			Name = "Computer",
			DisplayName = "Computer (" .. LEVELS[level] .. ")",
			isBot = true,
			level = level,
		}
		self:startGame(player, bot, mode)
	elseif action == "move" then
		local g = self.playerGame[player.UserId]
		if not g or g.over then
			return
		end
		local color = if g.white == player then "w" elseif g.black == player then "b" else nil
		if color ~= g.state.turn then
			return
		end
		local fr, fc, tr, tc = int(data.fr), int(data.fc), int(data.tr), int(data.tc)
		if not (fr and fc and tr and tc) then
			return
		end
		if fr < 1 or fr > 8 or fc < 1 or fc > 8 or tr < 1 or tr > 8 or tc < 1 or tc > 8 then
			return
		end
		local promo = if type(data.promo) == "string" then data.promo else nil
		local move = ChessRules.findMove(g.state, fr, fc, tr, tc, promo)
		if not move then
			self.send(player, "state", self:snapshot(g)) -- resync
			return
		end
		self:play(g, color, move)
	elseif action == "resign" then
		local g = self.playerGame[player.UserId]
		if g and not g.over then
			if g.clock and #g.moves < 2 then
				self:finish(g, "draw", "aborted") -- leaving before the game really began
			else
				self:finish(g, if g.white == player then "black" else "white", "resign")
			end
		end
	elseif action == "draw" then
		-- offer a draw, or accept the one on the table
		local g = self.playerGame[player.UserId]
		if not g or g.over then
			return
		end
		local color = if g.white == player then "w" else "b"
		local other = if color == "w" then g.black else g.white
		if g.drawOffer and g.drawOffer ~= color then
			self:finish(g, "draw", "agreement")
		elseif not g.drawOffer and not other.isBot then
			g.drawOffer = color
			self:broadcast(g)
		end
	elseif action == "watch" then
		if isPlaying(self, player.UserId) then
			return
		end
		local g = if int(data.game) then self.games[data.game] else nil
		if not g or g.over or g.white == player or g.black == player then
			self:sendGames(player)
			return
		end
		self.playerGame[player.UserId] = nil -- close any finished game first
		self.watching[player.UserId] = g
		self:broadcast(g)
	elseif action == "leave" then
		-- close a finished game, or stop watching
		local watched = self.watching[player.UserId]
		if watched then
			self:stopWatching(player)
			self.send(player, "noGame", {})
			self:sendGames(player)
			return
		end
		local g = self.playerGame[player.UserId]
		if g and g.over then
			self.playerGame[player.UserId] = nil
			self.send(player, "noGame", {})
			self:sendGames(player)
		end
	elseif action == "sync" then
		local g = self.playerGame[player.UserId] or self.watching[player.UserId]
		if g then
			self.send(player, "state", self:snapshot(g))
		else
			self.send(player, "noGame", {})
		end
		self:sendGames(player)
		for fromId, inv in pairs(self.invites) do
			if inv.to == player then
				self.send(player, "invite", { from = fromId, name = nameOf(inv.from), seconds = math.max(0, inv.expires - self.now()), mode = inv.mode, modeName = Manager.modeName(inv.mode) })
			elseif inv.from == player then
				self.send(player, "outgoing", { to = inv.to.UserId, name = nameOf(inv.to), status = "waiting", seconds = math.max(0, inv.expires - self.now()), mode = inv.mode, modeName = Manager.modeName(inv.mode) })
			end
		end
	end
end

function Manager:playerLeft(player)
	self:clearInvites(player, "left")
	self:stopWatching(player)
	local g = self.playerGame[player.UserId]
	if g then
		if not g.over then
			if g.clock and #g.moves < 2 then
				self:finish(g, "draw", "aborted")
			else
				self:finish(g, if g.white == player then "black" else "white", "left")
			end
		end
		self.playerGame[player.UserId] = nil
	end
end

function Manager:tick()
	local t = self.now()
	for fromId, inv in pairs(self.invites) do
		if t >= inv.expires then
			self.invites[fromId] = nil
			self.send(inv.to, "inviteGone", { from = fromId, reason = "expired" })
			self.send(inv.from, "outgoing", { to = inv.to.UserId, name = nameOf(inv.to), status = "expired" })
		end
	end
	for id, g in pairs(self.games) do
		if g.over then
			-- forget finished games once nobody has them open
			local open = false
			for _, og in pairs(self.playerGame) do
				if og == g then
					open = true
				end
			end
			for _, wg in pairs(self.watching) do
				if wg == g then
					open = true
				end
			end
			if not open then
				self.games[id] = nil
			end
		elseif g.clock then
			if #g.moves < 2 then
				if t - g.turnStart > FIRST_MOVE_SECONDS then
					self:finish(g, "draw", "aborted")
				end
			else
				local left = self:clocks(g)
				if left and left[g.state.turn] <= 0 then
					self:flag(g, g.state.turn)
				end
			end
		end
	end
end

return Manager
