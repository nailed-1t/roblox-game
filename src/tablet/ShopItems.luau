-- Items sold in the shop (bought with points from Minesweeper wins).
-- Each one is an ability: once bought it's yours for good, and you use it
-- with its key (or by clicking its button at the bottom of the screen).
--   id          used for saving and for the shelf model (ShopDisplay.<id>)
--   price       in points
--   key         keyboard key that uses it
--   cooldown    seconds between uses

return {
	{
		id = "ardor",
		name = "Ardor Scream",
		price = 30,
		icon = "😱",
		key = "Z",
		cooldown = 20,
		description = "Let out a yell that blasts everyone close to you away and knocks them over.",
	},
	{
		id = "headswap",
		name = "Head Swap",
		price = 15,
		icon = "🔄",
		key = "X",
		cooldown = 90,
		description = "Swap bodies (avatars) with the closest player for 60 seconds.",
	},
	{
		id = "blink",
		name = "Blink",
		price = 100,
		icon = "✨",
		key = "C",
		cooldown = 8,
		targeted = true, -- sends where your cursor points
		description = "Teleport from where you stand to wherever your cursor is pointing (up to 60 studs).",
	},
}
