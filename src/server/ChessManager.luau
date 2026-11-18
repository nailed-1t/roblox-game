-- Chess challenges and games between players. The server is in charge:
-- every move is checked with ChessRules, so nobody can cheat.
--
-- Messages to clients (action, data):
--   "invite"      someone challenged you        {from, name}
--   "inviteGone"  that challenge was withdrawn   {from, reason}
--   "outgoing"    your challenge's status        {to, name, status = waiting|declined|expired|busy|cancelled}
--   "state"       the game you are in            game snapshot (see snapshot())
--   "noGame"      you are not in a game

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChessRules = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ChessRules"))

local INVITE_SECONDS = 30

local Manager = {}
Manager.__index = Manager

export type SendFn = (player: any, action: string, data: any) -> ()
export type FindFn = (userId: number) -> any

function Manager.new(send: SendFn, findPlayer: FindFn)
	local self = setmetatable({}, Manager)
	self.send = send
	self.findPlayer = findPlayer
	self.invites = {} -- [challengerId] = { from = player, to = player, expires = number }
	self.playerGame = {} -- [userId] = game
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

function Manager:snapshot(g)
	local s = g.state
	return {
		id = g.id,
		white = { id = g.white.UserId, name = nameOf(g.white) },
		black = { id = g.black.UserId, name = nameOf(g.black) },
		board = s.board,
		turn = s.turn,
		castling = s.castling,
		ep = s.ep,
		halfmove = s.halfmove,
		fullmove = s.fullmove,
		moves = g.moves,
		last = g.last,
		over = g.over,
		result = g.result, -- "white", "black", "draw" or nil
		reason = g.reason, -- "checkmate", "resign", "left", "stalemate", "fifty", "material"
		inCheck = ChessRules.inCheck(s, s.turn),
	}
end

function Manager:broadcast(g)
	local snap = self:snapshot(g)
	for _, p in ipairs({ g.white, g.black }) do
		if self.playerGame[p.UserId] == g then
			self.send(p, "state", snap)
		end
	end
end

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

function Manager:startGame(a, b)
	self:clearInvites(a, "busy")
	self:clearInvites(b, "busy")
	self.nextId += 1
	local whiteFirst = math.random() < 0.5
	local g = {
		id = self.nextId,
		white = if whiteFirst then a else b,
		black = if whiteFirst then b else a,
		state = ChessRules.newGame(),
		moves = {},
		last = nil,
		over = false,
	}
	self.playerGame[a.UserId] = g
	self.playerGame[b.UserId] = g
	self:broadcast(g)
	return g
end

function Manager:finish(g, result: string, reason: string)
	g.over = true
	g.result = result
	g.reason = reason
	self:broadcast(g)
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
		if isPlaying(self, target.UserId) then
			self.send(player, "outgoing", { to = target.UserId, name = nameOf(target), status = "busy" })
			return
		end
		-- they already challenged you? then this is an accept
		local theirs = self.invites[target.UserId]
		if theirs and theirs.to == player then
			self:startGame(target, player)
			return
		end
		-- one outgoing challenge at a time
		local old = self.invites[player.UserId]
		if old then
			self.send(old.to, "inviteGone", { from = player.UserId, reason = "cancelled" })
		end
		self.invites[player.UserId] = { from = player, to = target, expires = self.now() + INVITE_SECONDS }
		self.send(target, "invite", { from = player.UserId, name = nameOf(player), seconds = INVITE_SECONDS })
		self.send(player, "outgoing", { to = target.UserId, name = nameOf(target), status = "waiting", seconds = INVITE_SECONDS })
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
			self:startGame(inv.from, player)
		else
			self.send(inv.from, "outgoing", { to = player.UserId, name = nameOf(player), status = "declined" })
		end
	elseif action == "move" then
		local g = self.playerGame[player.UserId]
		if not g or g.over then
			return
		end
		local color = if g.white == player then "w" elseif g.black == player then "b" else nil
		if color ~= g.state.turn then
			return
		end
		local function int(v)
			return if type(v) == "number" and v == math.floor(v) then v else nil
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
		local before = g.state
		g.state = ChessRules.apply(before, move)
		table.insert(g.moves, ChessRules.notation(before, move, g.state))
		g.last = { fr = move.fr, fc = move.fc, tr = move.tr, tc = move.tc }
		local status = ChessRules.status(g.state)
		if status == "checkmate" then
			self:finish(g, if color == "w" then "white" else "black", "checkmate")
		elseif status ~= "playing" then
			self:finish(g, "draw", status)
		else
			self:broadcast(g)
		end
	elseif action == "resign" then
		local g = self.playerGame[player.UserId]
		if g and not g.over then
			self:finish(g, if g.white == player then "black" else "white", "resign")
		end
	elseif action == "leave" then
		-- close a finished game so you can play again
		local g = self.playerGame[player.UserId]
		if g and g.over then
			self.playerGame[player.UserId] = nil
			self.send(player, "noGame", {})
		end
	elseif action == "sync" then
		local g = self.playerGame[player.UserId]
		if g then
			self.send(player, "state", self:snapshot(g))
		else
			self.send(player, "noGame", {})
		end
		for fromId, inv in pairs(self.invites) do
			if inv.to == player then
				self.send(player, "invite", { from = fromId, name = nameOf(inv.from), seconds = math.max(0, inv.expires - self.now()) })
			elseif inv.from == player then
				self.send(player, "outgoing", { to = inv.to.UserId, name = nameOf(inv.to), status = "waiting", seconds = math.max(0, inv.expires - self.now()) })
			end
		end
	end
end

function Manager:playerLeft(player)
	self:clearInvites(player, "left")
	local g = self.playerGame[player.UserId]
	if g then
		if not g.over then
			self:finish(g, if g.white == player then "black" else "white", "left")
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
end

return Manager
