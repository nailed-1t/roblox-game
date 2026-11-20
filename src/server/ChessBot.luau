-- The computer opponent for the tablet's Chess app ("Play vs Computer").
-- A small alpha-beta search over ChessRules. It knows the variants: it races
-- its king to the centre in King of the Hill and hunts checks in 3-Check.
--
-- ChessBot.choose(state, level, pause) -> Move?
--   level: "easy", "medium" or "hard"
--   pause: called every so often while thinking (the server passes
--          task.wait so a long think never freezes the game)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChessRules = require(ReplicatedStorage:WaitForChild("TabletShared"):WaitForChild("ChessRules"))

local ChessBot = {}

ChessBot.LEVELS = {
	easy = { depth = 1, noise = 140, blunder = 0.25, quiet = false },
	medium = { depth = 2, noise = 25, blunder = 0, quiet = true },
	hard = { depth = 3, noise = 0, blunder = 0, quiet = true },
}
ChessBot.LEVEL_NAMES = { easy = "Easy", medium = "Medium", hard = "Hard" }

local VALUE = { P = 100, N = 320, B = 330, R = 500, Q = 900, K = 0 }
local MATE = 100000

-- small "where pieces like to stand" bonuses, from White's side (rank 1..8)
local CENTER = { 0, 1, 2, 3, 3, 2, 1, 0 }
local function placeBonus(kind: string, r: number, c: number, color: string): number
	local rank = if color == "w" then r else 9 - r -- 1 = own back rank
	local centre = CENTER[r] + CENTER[c]
	if kind == "P" then
		return (rank - 2) * 8 + (if c == 4 or c == 5 then rank * 3 else 0)
	elseif kind == "N" then
		return centre * 8 - 20
	elseif kind == "B" then
		return centre * 4
	elseif kind == "R" then
		return if rank == 7 then 20 else 0
	elseif kind == "Q" then
		return centre * 2
	end
	return 0
end

-- distance from a square to the nearest of d4 e4 d5 e5
local function hillDistance(r: number, c: number): number
	local dr = if r < 4 then 4 - r elseif r > 5 then r - 5 else 0
	local dc = if c < 4 then 4 - c elseif c > 5 then c - 5 else 0
	return math.max(dr, dc)
end

-- score from the point of view of the side to move
local function evaluate(state): number
	local score = 0
	local board = state.board
	for r = 1, 8 do
		local row = board[r]
		for c = 1, 8 do
			local p = row[c]
			if p ~= "" then
				local color = string.sub(p, 1, 1)
				local kind = string.sub(p, 2, 2)
				local v = VALUE[kind] + placeBonus(kind, r, c, color)
				if kind == "K" and state.variant == "koth" then
					v += (4 - hillDistance(r, c)) * 60
				end
				score += if color == "w" then v else -v
			end
		end
	end
	if state.variant == "threecheck" and state.checks then
		score += (state.checks.w - state.checks.b) * 180
	end
	return if state.turn == "w" then score else -score
end

-- did the side that just moved win by a variant rule?
local function variantWin(state): boolean
	if state.variant == "koth" or state.variant == "threecheck" then
		local st = ChessRules.status(state)
		return st == "hill" or st == "threecheck"
	end
	return false
end

local function moveOrder(state, moves)
	local board = state.board
	local scored = {}
	for _, m in ipairs(moves) do
		local victim = board[m.tr][m.tc]
		local s = 0
		if victim ~= "" and not m.castle then
			s = 10 * VALUE[string.sub(victim, 2, 2)] - VALUE[string.sub(board[m.fr][m.fc], 2, 2)] + 1000
		end
		if m.promo then
			s += VALUE[m.promo] + 500
		end
		table.insert(scored, { m = m, s = s })
	end
	table.sort(scored, function(a, b)
		return a.s > b.s
	end)
	local out = {}
	for i, x in ipairs(scored) do
		out[i] = x.m
	end
	return out
end

local function isCapture(state, m): boolean
	return (state.board[m.tr][m.tc] ~= "" and not m.castle) or m.enPassant == true or m.promo ~= nil
end

function ChessBot.choose(state, level: string?, pause: (() -> ())?)
	local cfg = ChessBot.LEVELS[level or "medium"] or ChessBot.LEVELS.medium
	local rng = Random.new()
	-- think for ~8 ms at a time, then let the game run a frame
	local nodes = 0
	local sliceStart = os.clock()
	local function tick()
		nodes += 1
		if pause and nodes % 20 == 0 and os.clock() - sliceStart > 0.008 then
			pause()
			sliceStart = os.clock()
		end
	end

	local function quiesce(s, alpha: number, beta: number, depth: number): number
		tick()
		local stand = evaluate(s)
		if depth <= 0 or stand >= beta then
			return stand
		end
		if stand > alpha then
			alpha = stand
		end
		for _, m in ipairs(moveOrder(s, ChessRules.allLegalMoves(s))) do
			if isCapture(s, m) then
				local child = ChessRules.apply(s, m)
				local score = if variantWin(child) then MATE else -quiesce(child, -beta, -alpha, depth - 1)
				if score >= beta then
					return score
				end
				if score > alpha then
					alpha = score
				end
			end
		end
		return alpha
	end

	local function search(s, depth: number, alpha: number, beta: number, ply: number): number
		tick()
		local moves = ChessRules.allLegalMoves(s)
		if #moves == 0 then
			return if ChessRules.inCheck(s, s.turn) then -(MATE - ply) else 0
		end
		if depth <= 0 then
			return if cfg.quiet then quiesce(s, alpha, beta, 3) else evaluate(s)
		end
		local best = -math.huge
		for _, m in ipairs(moveOrder(s, moves)) do
			local child = ChessRules.apply(s, m)
			local score
			if variantWin(child) then
				score = MATE - ply
			else
				score = -search(child, depth - 1, -beta, -alpha, ply + 1)
			end
			if score > best then
				best = score
			end
			if score > alpha then
				alpha = score
			end
			if alpha >= beta then
				break
			end
		end
		return best
	end

	local moves = ChessRules.allLegalMoves(state)
	if #moves == 0 then
		return nil
	end
	if cfg.blunder > 0 and rng:NextNumber() < cfg.blunder then
		return moves[rng:NextInteger(1, #moves)]
	end
	local bestMove, bestScore = nil, -math.huge
	for _, m in ipairs(moveOrder(state, moves)) do
		local child = ChessRules.apply(state, m)
		local score
		if variantWin(child) then
			score = MATE
		else
			score = -search(child, cfg.depth - 1, -math.huge, -bestScore + cfg.noise, 1)
		end
		if cfg.noise > 0 then
			score += rng:NextNumber(-cfg.noise, cfg.noise)
		end
		if score > bestScore then
			bestScore, bestMove = score, m
		end
	end
	return bestMove
end

return ChessBot
