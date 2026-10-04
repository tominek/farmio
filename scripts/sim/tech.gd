class_name Tech
## The research tree: what can be unlocked for quacks and what each node needs first.
## A node is unlocked once (instantly) when all its prerequisites are unlocked; "later" nodes are
## content still to be made — shown in the tree, never buyable.

enum Kind { PLAN, UPGRADE, TECHNOLOGY }

const BRANCHES: Array[String] = ["Processing", "Forestry", "Roads", "Equipment", "Fields", "Animals"]
const KIND_NAMES := { Kind.PLAN: "Building plan", Kind.UPGRADE: "Building upgrade", Kind.TECHNOLOGY: "Technology" }

# id -> name, kind, branch (row), col (column in the tree), cost, needs, what it unlocks, desc, later.
# Unlocks: "buildings" (Defs.BUILDINGS ids), "levels" {building id: level}, "items" (Dealer goods).
const NODES := {
	&"hand_mill": {
		"name": "Hand Mill", "kind": Kind.PLAN, "branch": 0, "col": 0, "cost": 300, "needs": [],
		"buildings": [&"hand_mill"],
		"desc": "A small mill where a worker grinds wheat into flour by hand. Flour sells for twice the price of wheat.",
	},
	&"water_mill": {
		"name": "Water Mill", "kind": Kind.PLAN, "branch": 0, "col": 1, "cost": 1500, "needs": [&"hand_mill", &"sawmill"],
		"buildings": [&"water_mill"],
		"desc": "Grinds wheat more than three times faster than the Hand Mill. Stands on the river bank with its wheel in the water.",
	},
	&"mill_gear_2": {
		"name": "Mill gear II", "kind": Kind.UPGRADE, "branch": 0, "col": 2, "cost": 2000, "needs": [&"hand_mill"],
		"levels": {&"hand_mill": 2, &"water_mill": 2},
		"desc": "Better millstones: every mill can be upgraded to level 2 (faster grinding, more room inside).",
	},
	&"mill_gear_3": {
		"name": "Mill gear III", "kind": Kind.UPGRADE, "branch": 0, "col": 3, "cost": 5000, "needs": [&"mill_gear_2"],
		"levels": {&"hand_mill": 3, &"water_mill": 3},
		"desc": "Every mill can be upgraded to level 3.",
	},
	&"bakery": {
		"name": "Bakery", "kind": Kind.PLAN, "branch": 0, "col": 4, "cost": 0, "needs": [&"hand_mill"], "later": true,
		"desc": "Bakes bread from flour.",
	},
	&"pasta_maker": {
		"name": "Pasta Maker", "kind": Kind.PLAN, "branch": 0, "col": 5, "cost": 0, "needs": [&"bakery"], "later": true,
		"desc": "Makes pasta from flour.",
	},
	&"sugar_mill": {
		"name": "Sugar Mill", "kind": Kind.PLAN, "branch": 0, "col": 6, "cost": 0, "needs": [&"hand_mill"], "later": true,
		"desc": "Processes sugar beet into sugar.",
	},
	&"sawmill": {
		"name": "Sawmill", "kind": Kind.PLAN, "branch": 1, "col": 0, "cost": 300, "needs": [],
		"buildings": [&"sawmill"],
		"desc": "Saws logs into planks — the material for buildings. Cheaper than buying planks at the Dealer.",
	},
	&"sawmill_2": {
		"name": "Sawmill II", "kind": Kind.UPGRADE, "branch": 1, "col": 1, "cost": 1200, "needs": [&"sawmill"],
		"levels": {&"sawmill": 2},
		"desc": "Sawmills can be upgraded to level 2.",
	},
	&"sawmill_3": {
		"name": "Sawmill III", "kind": Kind.UPGRADE, "branch": 1, "col": 2, "cost": 3000, "needs": [&"sawmill_2"],
		"levels": {&"sawmill": 3},
		"desc": "Sawmills can be upgraded to level 3.",
	},
	&"tree_farm": {
		"name": "Tree Farm", "kind": Kind.PLAN, "branch": 1, "col": 3, "cost": 0, "needs": [&"sawmill"], "later": true,
		"desc": "Plant and grow trees for logs.",
	},
	&"gravel_road": {
		"name": "Gravel road", "kind": Kind.TECHNOLOGY, "branch": 2, "col": 0, "cost": 200, "needs": [],
		"buildings": [&"road_gravel"], "items": [&"gravel"],
		"desc": "Gravel roads: faster for workers and the pickup. Gravel is bought at the Dealer.",
	},
	&"cobblestone": {
		"name": "Cobblestone", "kind": Kind.TECHNOLOGY, "branch": 2, "col": 1, "cost": 0, "needs": [&"gravel_road"], "later": true,
		"desc": "Cobblestone roads.",
	},
	&"asphalt": {
		"name": "Asphalt", "kind": Kind.TECHNOLOGY, "branch": 2, "col": 2, "cost": 0, "needs": [&"cobblestone"], "later": true,
		"desc": "Asphalt roads.",
	},
	&"concrete": {
		"name": "Concrete", "kind": Kind.TECHNOLOGY, "branch": 2, "col": 3, "cost": 0, "needs": [&"asphalt"], "later": true,
		"desc": "Concrete roads.",
	},
	&"wheelbarrow": {
		"name": "Wheelbarrow", "kind": Kind.TECHNOLOGY, "branch": 3, "col": 0, "cost": 150, "needs": [],
		"items": [&"wheelbarrow"],
		"desc": "Wheelbarrows at the Dealer: a worker moves 150 kg at once instead of 50 kg.",
	},
	&"light_tractor": {
		"name": "Light tractor", "kind": Kind.TECHNOLOGY, "branch": 3, "col": 1, "cost": 0, "needs": [&"wheelbarrow"], "later": true,
		"desc": "The first tractor, for medium fields.",
	},
	&"better_seed": {
		"name": "Better seed", "kind": Kind.TECHNOLOGY, "branch": 4, "col": 0, "cost": 0, "needs": [], "later": true,
		"desc": "Seed varieties with a higher yield.",
	},
	&"new_crops": {
		"name": "New crops", "kind": Kind.TECHNOLOGY, "branch": 4, "col": 1, "cost": 0, "needs": [&"better_seed"], "later": true,
		"desc": "Barley, sunflowers, rapeseed…",
	},
	&"chicken_coop": {
		"name": "Chicken coop", "kind": Kind.PLAN, "branch": 5, "col": 0, "cost": 0, "needs": [], "later": true,
		"desc": "Hens and roosters: eggs.",
	},
	&"sheep_shed": {
		"name": "Sheep & goat shed", "kind": Kind.PLAN, "branch": 5, "col": 1, "cost": 0, "needs": [&"chicken_coop"], "later": true,
		"desc": "Sheep and goats: wool and goat milk.",
	},
	&"cowshed": {
		"name": "Cowshed", "kind": Kind.PLAN, "branch": 5, "col": 2, "cost": 0, "needs": [&"sheep_shed"], "later": true,
		"desc": "Cows: milk.",
	},
}


static func node(id: StringName) -> Dictionary:
	return NODES[id]


static func is_later(id: StringName) -> bool:
	return NODES[id].get("later", false)


## Node that unlocks a building (its plan or technology), or &"" if it is available from the start.
static func node_for_building(def_id: StringName) -> StringName:
	for id: StringName in NODES:
		if (NODES[id].get("buildings", []) as Array).has(def_id):
			return id
	return &""


## Node that unlocks a Dealer item, or &"" if it is always for sale.
static func node_for_item(res: StringName) -> StringName:
	for id: StringName in NODES:
		if (NODES[id].get("items", []) as Array).has(res):
			return id
	return &""


## Node that unlocks a level of a building (2 or 3), or &"" if there is none.
static func node_for_level(def_id: StringName, level: int) -> StringName:
	for id: StringName in NODES:
		if (NODES[id].get("levels", {}) as Dictionary).get(def_id, 0) == level:
			return id
	return &""


## Nodes that need this one.
static func leads_to(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for other: StringName in NODES:
		if (NODES[other]["needs"] as Array).has(id):
			out.append(other)
	return out
