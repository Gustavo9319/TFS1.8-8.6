-- Weekly Task delivery items from Crystal Server's Task Board list.
-- IDs are valid item IDs from this server's items.xml.

return {
	[0] = {
		-- Beginner deliveries use common food, so a new player never needs to
		-- sacrifice rare equipment merely to complete their first Weekly.
		{ itemId = 3577, amount = 25 }, -- Meat
		{ itemId = 3578, amount = 25 }, -- Fish
		{ itemId = 3582, amount = 20 }, -- Ham
		{ itemId = 3585, amount = 30 }, -- Red Apple
		{ itemId = 3587, amount = 30 }, -- Banana
		{ itemId = 3595, amount = 30 }, -- Carrot
		{ itemId = 3596, amount = 30 }, -- Tomato
		{ itemId = 3598, amount = 30 }, -- Cookie
		{ itemId = 3600, amount = 25 }, -- Bread
		{ itemId = 3607, amount = 20 }, -- Cheese
	},

	[1] = {
		{ itemId = 828, amount = 20 },  -- Lightning Headband
		{ itemId = 829, amount = 20 },  -- Glacier Mask
		{ itemId = 830, amount = 20 },  -- Terra Hood
		{ itemId = 3234, amount = 50 }, -- Cookbook
		{ itemId = 3269, amount = 20 }, -- Halberd
		{ itemId = 3275, amount = 20 }, -- Double Axe
		{ itemId = 3291, amount = 50 }, -- Knife
		{ itemId = 3292, amount = 50 }, -- Combat Knife
		{ itemId = 3301, amount = 20 }, -- Broadsword
		{ itemId = 3306, amount = 20 }, -- Golden Sickle
	},

	[2] = {
		{ itemId = 3307, amount = 20 }, -- Scimitar
		{ itemId = 3316, amount = 20 }, -- Orcish Axe
		{ itemId = 3318, amount = 20 }, -- Knight Axe
		{ itemId = 3320, amount = 20 }, -- Fire Axe
		{ itemId = 3322, amount = 20 }, -- Dragon Hammer
		{ itemId = 3330, amount = 20 }, -- Heavy Machete
		{ itemId = 3333, amount = 20 }, -- Crystal Mace
		{ itemId = 3337, amount = 50 }, -- Bone Club
		{ itemId = 3342, amount = 20 }, -- War Axe
		{ itemId = 3346, amount = 20 }, -- Ripper Lance
	},

	[3] = {
		{ itemId = 3364, amount = 10 }, -- Golden Legs
		{ itemId = 3371, amount = 20 }, -- Knight Legs
		{ itemId = 3373, amount = 20 }, -- Strange Helmet
		{ itemId = 3413, amount = 20 }, -- Battle Shield
		{ itemId = 3415, amount = 20 }, -- Guardian Shield
		{ itemId = 3421, amount = 20 }, -- Dark Shield
		{ itemId = 3429, amount = 20 }, -- Black Shield
		{ itemId = 3509, amount = 50 }, -- Inkwell
		{ itemId = 3557, amount = 20 }, -- Plate Legs
		{ itemId = 3575, amount = 20 }, -- Wood Cape
	},
}
