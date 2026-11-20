--!strict
-- Complete chess rules, shared by the server (which enforces them) and the
-- tablet (which uses them to show legal moves).
--
-- Board: board[rank][file], rank 1 = White's back rank, file 1 = "a".
-- Each square holds "" (empty) or a colour + piece letter, e.g. "wK", "bP".
-- Pieces: K king, Q queen, R rook, B bishop, N knight, P pawn.
--
-- Variants (as on chess.com):
--   "standard"
--   "chess960"   the back row is shuffled (bishops on opposite colours, king
--                between the rooks); castle by moving the king onto the rook
--   "koth"       King of the Hill: walk your king to d4, e4, d5 or e5 to win
--   "threecheck" give check three times to win

local ChessRules = {}

export type Move = {
	fr: number, fc: number, -- from rank / file
	tr: number, tc: number, -- to rank / file
	promo: string?, -- "Q" "R" "B" "N" when a pawn reaches the last rank
	castle: string?, -- "K" (king side) or "Q" (queen side)
	enPassant: boolean?,
}

export type State = {
	board: { { string } },
	turn: string, -- "w" or "b"
	castling: { wK: boolean, wQ: boolean, bK: boolean, bQ: boolean },
	ep: { number }?, -- en-passant target square {rank, file}
	halfmove: number, -- moves since the last capture or pawn move (50-move rule)
	fullmove: number,
	variant: string?, -- see above; nil means "standard"
	kingFile: number?, -- where the kings start (5 = e, except in Chess960)
	rookFiles: { K: number, Q: number }?, -- where the castling rooks start
	checks: { w: number, b: number }?, -- checks given so far (three-check)
}

ChessRules.VARIANTS = { "standard", "chess960", "koth", "threecheck" }
ChessRules.VARIANT_NAMES = {
	standard = "Standard",
	chess960 = "Chess960",
	koth = "King of the Hill",
	threecheck = "3-Check",
}
-- results where the side that just moved wins
ChessRules.WINS = { checkmate = true, hill = true, threecheck = true }

local FILES = "abcdefgh"
local KNIGHT = { { 1, 2 }, { 2, 1 }, { -1, 2 }, { -2, 1 }, { 1, -2 }, { 2, -1 }, { -1, -2 }, { -2, -1 } }
local KING = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local ROOK_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local BISHOP_DIRS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local PROMOTIONS = { Q = true, R = true, B = true, N = true }

local function onBoard(r: number, c: number): boolean
	return r >= 1 and r <= 8 and c >= 1 and c <= 8
end

local function other(color: string): string
	return if color == "w" then "b" else "w"
end
ChessRules.other = other

function ChessRules.squareName(r: number, c: number): string
	return string.sub(FILES, c, c) .. tostring(r)
end

-- A Chess960 back row (one of the 960 starting positions), from a seed.
function ChessRules.backRank960(seed: number?): { string }
	local rng = Random.new(seed)
	local back: { string } = {}
	-- bishops on one light and one dark square
	back[rng:NextInteger(0, 3) * 2 + 1] = "B"
	back[rng:NextInteger(0, 3) * 2 + 2] = "B"
	local function free(): { number }
		local list = {}
		for c = 1, 8 do
			if not back[c] then
				table.insert(list, c)
			end
		end
		return list
	end
	local f = free()
	back[table.remove(f, rng:NextInteger(1, #f))] = "Q"
	f = free()
	back[table.remove(f, rng:NextInteger(1, #f))] = "N"
	f = free()
	back[table.remove(f, rng:NextInteger(1, #f))] = "N"
	-- the three squares left get rook, king, rook in that order
	f = free()
	back[f[1]], back[f[2]], back[f[3]] = "R", "K", "R"
	return back
end

function ChessRules.newGame(variant: string?, seed: number?): State
	local board = {}
	for r = 1, 8 do
		board[r] = {}
		for c = 1, 8 do
			board[r][c] = ""
		end
	end
	local back = if variant == "chess960" then ChessRules.backRank960(seed) else { "R", "N", "B", "Q", "K", "B", "N", "R" }
	local kingFile, rookQ, rookK = 5, 1, 8
	for c = 1, 8 do
		if back[c] == "K" then
			kingFile = c
		end
	end
	for c = 1, 8 do
		if back[c] == "R" then
			if c < kingFile then
				rookQ = c
			else
				rookK = c
			end
		end
	end
	for c = 1, 8 do
		board[1][c] = "w" .. back[c]
		board[2][c] = "wP"
		board[7][c] = "bP"
		board[8][c] = "b" .. back[c]
	end
	return {
		board = board,
		turn = "w",
		castling = { wK = true, wQ = true, bK = true, bQ = true },
		ep = nil,
		halfmove = 0,
		fullmove = 1,
		variant = variant or "standard",
		kingFile = kingFile,
		rookFiles = { K = rookK, Q = rookQ },
		checks = { w = 0, b = 0 },
	}
end

function ChessRules.copy(state: State): State
	local board = {}
	for r = 1, 8 do
		board[r] = table.clone(state.board[r])
	end
	return {
		board = board,
		turn = state.turn,
		castling = table.clone(state.castling),
		ep = if state.ep then { state.ep[1], state.ep[2] } else nil,
		halfmove = state.halfmove,
		fullmove = state.fullmove,
		variant = state.variant,
		kingFile = state.kingFile,
		rookFiles = state.rookFiles, -- never changes, so it can be shared
		checks = if state.checks then table.clone(state.checks) else nil,
	}
end

-- Is square (r, c) attacked by any piece of colour `by`?
function ChessRules.isAttacked(board: { { string } }, r: number, c: number, by: string): boolean
	-- pawns
	local pr = if by == "w" then r - 1 else r + 1
	for _, dc in ipairs({ -1, 1 }) do
		if onBoard(pr, c + dc) and board[pr][c + dc] == by .. "P" then
			return true
		end
	end
	-- knights
	for _, o in ipairs(KNIGHT) do
		local rr, cc = r + o[1], c + o[2]
		if onBoard(rr, cc) and board[rr][cc] == by .. "N" then
			return true
		end
	end
	-- king
	for _, o in ipairs(KING) do
		local rr, cc = r + o[1], c + o[2]
		if onBoard(rr, cc) and board[rr][cc] == by .. "K" then
			return true
		end
	end
	-- sliders
	for _, d in ipairs(ROOK_DIRS) do
		local rr, cc = r + d[1], c + d[2]
		while onBoard(rr, cc) do
			local p = board[rr][cc]
			if p ~= "" then
				if p == by .. "R" or p == by .. "Q" then
					return true
				end
				break
			end
			rr += d[1]
			cc += d[2]
		end
	end
	for _, d in ipairs(BISHOP_DIRS) do
		local rr, cc = r + d[1], c + d[2]
		while onBoard(rr, cc) do
			local p = board[rr][cc]
			if p ~= "" then
				if p == by .. "B" or p == by .. "Q" then
					return true
				end
				break
			end
			rr += d[1]
			cc += d[2]
		end
	end
	return false
end

function ChessRules.findKing(board: { { string } }, color: string): (number?, number?)
	for r = 1, 8 do
		for c = 1, 8 do
			if board[r][c] == color .. "K" then
				return r, c
			end
		end
	end
	return nil, nil
end

function ChessRules.inCheck(state: State, color: string): boolean
	local kr, kc = ChessRules.findKing(state.board, color)
	if not kr or not kc then
		return false
	end
	return ChessRules.isAttacked(state.board, kr, kc, other(color))
end

-- Moves that follow each piece's movement pattern (may leave the king in check).
local function pseudoMoves(state: State, r: number, c: number): { Move }
	local board = state.board
	local piece = board[r][c]
	local moves: { Move } = {}
	if piece == "" then
		return moves
	end
	local color = string.sub(piece, 1, 1)
	local kind = string.sub(piece, 2, 2)
	local enemy = other(color)

	local function add(tr: number, tc: number, extra: { [string]: any }?)
		local m: any = { fr = r, fc = c, tr = tr, tc = tc }
		if extra then
			for k, v in pairs(extra) do
				m[k] = v
			end
		end
		table.insert(moves, m)
	end

	if kind == "P" then
		local dir = if color == "w" then 1 else -1
		local startRank = if color == "w" then 2 else 7
		local lastRank = if color == "w" then 8 else 1
		local function addPawn(tr: number, tc: number, extra: { [string]: any }?)
			if tr == lastRank then
				for _, promo in ipairs({ "Q", "R", "B", "N" }) do
					local e = if extra then table.clone(extra) else {}
					e.promo = promo
					add(tr, tc, e)
				end
			else
				add(tr, tc, extra)
			end
		end
		-- forward
		if onBoard(r + dir, c) and board[r + dir][c] == "" then
			addPawn(r + dir, c)
			if r == startRank and board[r + 2 * dir][c] == "" then
				add(r + 2 * dir, c)
			end
		end
		-- captures
		for _, dc in ipairs({ -1, 1 }) do
			local tr, tc = r + dir, c + dc
			if onBoard(tr, tc) then
				local target = board[tr][tc]
				if target ~= "" and string.sub(target, 1, 1) == enemy then
					addPawn(tr, tc)
				elseif state.ep and state.ep[1] == tr and state.ep[2] == tc then
					add(tr, tc, { enPassant = true })
				end
			end
		end
	elseif kind == "N" or kind == "K" then
		for _, o in ipairs(if kind == "N" then KNIGHT else KING) do
			local tr, tc = r + o[1], c + o[2]
			if onBoard(tr, tc) then
				local target = board[tr][tc]
				if target == "" or string.sub(target, 1, 1) == enemy then
					add(tr, tc)
				end
			end
		end
		if kind == "K" then
			local home = if color == "w" then 1 else 8
			local kf = state.kingFile or 5
			local rooks = state.rookFiles or { K = 8, Q = 1 }
			if r == home and c == kf and not ChessRules.isAttacked(board, home, kf, enemy) then
				for _, side in ipairs({ "K", "Q" }) do
					local rf = rooks[side]
					if state.castling[color .. side] and board[home][rf] == color .. "R" then
						-- king ends on g or c, the rook next to it on f or d
						local kd = if side == "K" then 7 else 3
						local rd = if side == "K" then 6 else 4
						local ok = true
						-- every square either piece crosses must be empty (apart from the two of them)
						local lo = math.min(kf, kd, rf, rd)
						local hi = math.max(kf, kd, rf, rd)
						for f = lo, hi do
							if f ~= kf and f ~= rf and board[home][f] ~= "" then
								ok = false
								break
							end
						end
						-- and the king may not pass through or land on an attacked square
						if ok then
							local step = if kd >= kf then 1 else -1
							for f = kf + step, kd, step do
								if ChessRules.isAttacked(board, home, f, enemy) then
									ok = false
									break
								end
							end
						end
						if ok then
							-- in Chess960 you castle by moving the king onto the rook
							local target = if state.variant == "chess960" then rf else kd
							add(home, target, { castle = side })
						end
					end
				end
			end
		end
	else
		local dirs = {}
		if kind == "R" or kind == "Q" then
			for _, d in ipairs(ROOK_DIRS) do
				table.insert(dirs, d)
			end
		end
		if kind == "B" or kind == "Q" then
			for _, d in ipairs(BISHOP_DIRS) do
				table.insert(dirs, d)
			end
		end
		for _, d in ipairs(dirs) do
			local tr, tc = r + d[1], c + d[2]
			while onBoard(tr, tc) do
				local target = board[tr][tc]
				if target == "" then
					add(tr, tc)
				else
					if string.sub(target, 1, 1) == enemy then
						add(tr, tc)
					end
					break
				end
				tr += d[1]
				tc += d[2]
			end
		end
	end
	return moves
end

-- Plays a move and returns the new state (the old state is not changed).
-- Assumes the move is legal.
function ChessRules.apply(state: State, move: Move): State
	local s = ChessRules.copy(state)
	local b = s.board
	local piece = b[move.fr][move.fc]
	local color = string.sub(piece, 1, 1)
	local kind = string.sub(piece, 2, 2)
	local captured = b[move.tr][move.tc]

	local rooks = state.rookFiles or { K = 8, Q = 1 }
	if move.castle then
		-- lift the king and the rook, then put them on their castled squares
		local rf = rooks[move.castle]
		captured = ""
		b[move.fr][move.fc] = ""
		b[move.fr][rf] = ""
		b[move.fr][if move.castle == "K" then 7 else 3] = color .. "K"
		b[move.fr][if move.castle == "K" then 6 else 4] = color .. "R"
	else
		b[move.fr][move.fc] = ""
		if move.enPassant then
			b[move.fr][move.tc] = "" -- the pawn that is captured sits beside us
			captured = other(color) .. "P"
		end
		if move.promo then
			b[move.tr][move.tc] = color .. move.promo
		else
			b[move.tr][move.tc] = piece
		end
	end

	-- castling rights
	if kind == "K" then
		s.castling[color .. "K"] = false
		s.castling[color .. "Q"] = false
	end
	local function rookGone(r: number, c: number)
		if r == 1 and c == rooks.Q then s.castling.wQ = false end
		if r == 1 and c == rooks.K then s.castling.wK = false end
		if r == 8 and c == rooks.Q then s.castling.bQ = false end
		if r == 8 and c == rooks.K then s.castling.bK = false end
	end
	rookGone(move.fr, move.fc)
	rookGone(move.tr, move.tc)

	-- en-passant target
	if kind == "P" and math.abs(move.tr - move.fr) == 2 then
		s.ep = { (move.fr + move.tr) // 2, move.fc }
	else
		s.ep = nil
	end

	if kind == "P" or captured ~= "" then
		s.halfmove = 0
	else
		s.halfmove += 1
	end
	if color == "b" then
		s.fullmove += 1
	end
	s.turn = other(color)
	if s.variant == "threecheck" and s.checks and ChessRules.inCheck(s, s.turn) then
		s.checks[color] += 1
	end
	return s
end

-- All legal moves for the piece on (r, c) (only if it is that colour's turn).
function ChessRules.legalMovesFrom(state: State, r: number, c: number): { Move }
	local piece = state.board[r][c]
	if piece == "" or string.sub(piece, 1, 1) ~= state.turn then
		return {}
	end
	local legal = {}
	for _, m in ipairs(pseudoMoves(state, r, c)) do
		local after = ChessRules.apply(state, m)
		if not ChessRules.inCheck(after, state.turn) then
			table.insert(legal, m)
		end
	end
	return legal
end

function ChessRules.allLegalMoves(state: State): { Move }
	local all = {}
	for r = 1, 8 do
		for c = 1, 8 do
			local p = state.board[r][c]
			if p ~= "" and string.sub(p, 1, 1) == state.turn then
				for _, m in ipairs(ChessRules.legalMovesFrom(state, r, c)) do
					table.insert(all, m)
				end
			end
		end
	end
	return all
end

-- Finds the legal move matching a request (from/to squares + optional promotion).
function ChessRules.findMove(state: State, fr: number, fc: number, tr: number, tc: number, promo: string?): Move?
	for _, m in ipairs(ChessRules.legalMovesFrom(state, fr, fc)) do
		if m.tr == tr and m.tc == tc then
			if m.promo == nil then
				return m
			end
			local want = if promo and PROMOTIONS[promo] then promo else "Q"
			if m.promo == want then
				return m
			end
		end
	end
	return nil
end

local function insufficientMaterial(board: { { string } }): boolean
	local minors = 0
	for r = 1, 8 do
		for c = 1, 8 do
			local p = board[r][c]
			if p ~= "" then
				local k = string.sub(p, 2, 2)
				if k == "P" or k == "R" or k == "Q" then
					return false
				end
				if k == "B" or k == "N" then
					minors += 1
				end
			end
		end
	end
	return minors <= 1
end

local HILL = { [44] = true, [45] = true, [54] = true, [55] = true } -- d4 e4 d5 e5

-- "playing", "checkmate", "stalemate", "fifty", "material", and for the
-- variants "hill" (a king reached the centre) and "threecheck"
-- (see ChessRules.WINS for which of these the side that just moved wins)
function ChessRules.status(state: State): string
	local mover = other(state.turn)
	if state.variant == "koth" then
		local kr, kc = ChessRules.findKing(state.board, mover)
		if kr and kc and HILL[kr * 10 + kc] then
			return "hill"
		end
	elseif state.variant == "threecheck" and state.checks and state.checks[mover] >= 3 then
		return "threecheck"
	end
	if #ChessRules.allLegalMoves(state) == 0 then
		return if ChessRules.inCheck(state, state.turn) then "checkmate" else "stalemate"
	end
	if state.halfmove >= 100 then
		return "fifty"
	end
	-- a lone king can still walk to the hill, and a knight can still give checks
	local plain = state.variant == nil or state.variant == "standard" or state.variant == "chess960"
	if plain and insufficientMaterial(state.board) then
		return "material"
	end
	return "playing"
end

-- Short move notation, e.g. "e4", "Nxf3", "O-O", "exd8=Q+", "Qh5#".
function ChessRules.notation(before: State, move: Move, after: State): string
	local text
	if move.castle == "K" then
		text = "O-O"
	elseif move.castle == "Q" then
		text = "O-O-O"
	else
		local piece = before.board[move.fr][move.fc]
		local kind = string.sub(piece, 2, 2)
		local capture = before.board[move.tr][move.tc] ~= "" or move.enPassant == true
		local dest = ChessRules.squareName(move.tr, move.tc)
		if kind == "P" then
			text = (if capture then string.sub(FILES, move.fc, move.fc) .. "x" else "") .. dest
			if move.promo then
				text ..= "=" .. move.promo
			end
		else
			text = kind .. (if capture then "x" else "") .. dest
		end
	end
	local st = ChessRules.status(after)
	if ChessRules.WINS[st] and st ~= "checkmate" and ChessRules.inCheck(after, after.turn) then
		text ..= "+"
	elseif st == "checkmate" then
		text ..= "#"
	elseif ChessRules.inCheck(after, after.turn) then
		text ..= "+"
	end
	return text
end

-- Counts positions to a given depth; used to test that the rules are right.
function ChessRules.perft(state: State, depth: number): number
	if depth == 0 then
		return 1
	end
	local n = 0
	for _, m in ipairs(ChessRules.allLegalMoves(state)) do
		n += ChessRules.perft(ChessRules.apply(state, m), depth - 1)
	end
	return n
end

return ChessRules
