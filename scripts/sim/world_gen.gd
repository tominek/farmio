class_name WorldGen
## Procedural map: noise tree clusters, boundary forest, farm origin (Storage Barn + Garage
## on a short road), Dealer at a random spot and a winding dirt road between them.

const FARM_CLEAR_RADIUS := 18
const DEALER_CLEAR_RADIUS := 7


static func generate(size: int, seed_value: int) -> World:
	var world := World.new(size, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_plant_trees(world, rng)

	# farm origin somewhere around the middle, on the even road lattice
	var spread := size / 5
	var origin := Vector2i(size / 2 + rng.randi_range(-spread, spread), size / 2 + rng.randi_range(-spread, spread))
	origin = Vector2i(origin.x & ~1, origin.y & ~1)
	var road_y := origin.y
	var road_x0 := origin.x - 8
	_clear_disc(world, origin, FARM_CLEAR_RADIUS)

	# starting buildings face the road from the north (rotation 2 = front towards +y)
	world.add_building(&"storage_barn", Vector2i(road_x0 + 2, road_y - 3), 2)
	var garage := world.add_building(&"garage", Vector2i(road_x0 + 8, road_y - 4), 2)
	var farm_blocks: Array[Vector2i] = []
	for i in 8:
		farm_blocks.append(Vector2i(road_x0 + i * Defs.ROAD_BLOCK, road_y))

	# Dealer 60-100 tiles away, facing roughly towards the farm
	var dealer := _place_dealer(world, rng, origin)
	var dealer_block := Vector2i(dealer.access.x & ~1, dealer.access.y & ~1)
	_clear_disc(world, dealer.access, DEALER_CLEAR_RADIUS)

	var start := farm_blocks[0] if Vector2(farm_blocks[0]).distance_to(dealer_block) < Vector2(farm_blocks[-1]).distance_to(dealer_block) else farm_blocks[-1]
	var blocks: Array[Vector2i] = farm_blocks.duplicate()
	blocks.append_array(_road_path(world, start, dealer_block))
	for b in blocks:
		if world.road_blocks.has(b):
			continue
		for y in Defs.ROAD_BLOCK:
			for x in Defs.ROAD_BLOCK:
				var c := b + Vector2i(x, y)
				if world.has_tree(c):
					world.remove_tree(c)
		world.add_road_block(b, &"dirt")

	world.add_vehicle(garage)

	var looks := [Worker.Look.MALE, Worker.Look.FEMALE, Worker.Look.MALE_VAR, Worker.Look.FEMALE_VAR]
	for i in Defs.START_WORKERS:
		world.add_worker(Vector2i(road_x0 + 3 + i * 2, road_y + 1), looks[i % looks.size()])
	return world


static func _plant_trees(world: World, rng: RandomNumberGenerator) -> void:
	var density := FastNoiseLite.new()
	density.seed = world.seed_value
	density.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	density.frequency = 0.025
	density.fractal_octaves = 3
	var kind := FastNoiseLite.new()
	kind.seed = world.seed_value + 17
	kind.frequency = 0.02
	for y in world.size:
		for x in world.size:
			var c := Vector2i(x, y)
			var conifer := kind.get_noise_2d(x, y) + rng.randf_range(-0.35, 0.35) > 0.0
			var k := Defs.TreeKind.CONIFER if conifer else Defs.TreeKind.DECIDUOUS
			if world.is_locked(c):
				world.set_tree(c, k, Defs.TreeStage.FULL)
				continue
			var d := smoothstep(-0.05, 0.45, density.get_noise_2d(x, y))
			if rng.randf() < d * 0.92 + 0.015:
				var r := rng.randf()
				var stage := Defs.TreeStage.FULL if r < 0.82 else (Defs.TreeStage.SMALL if r < 0.95 else Defs.TreeStage.SAPLING)
				world.set_tree(c, k, stage)


static func _clear_disc(world: World, center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			# ragged edge so the clearing doesn't look like a perfect circle
			var r := radius + (hash(c) % 5) - 2
			if world.in_bounds(c) and not world.is_locked(c) and Vector2(c).distance_to(center) <= r and world.has_tree(c):
				world.remove_tree(c)


static func _place_dealer(world: World, rng: RandomNumberGenerator, origin: Vector2i) -> Building:
	var margin := Defs.BORDER + 12
	for attempt in 200:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(60.0, 100.0)
		var p := Vector2i(Vector2(origin) + Vector2(cos(ang), sin(ang)) * dist)
		if p.x < margin or p.y < margin or p.x > world.size - margin or p.y > world.size - margin:
			continue
		# front towards the farm: pick the rotation whose direction best matches
		var to_farm := Vector2(origin - p).normalized()
		var rot := 0
		var best := -2.0
		for r in 4:
			var dot := to_farm.dot(Vector2(Defs.DIRS[r]))
			if dot > best:
				best = dot
				rot = r
		# shift by one tile if the road block at the access would overlap the footprint
		for shift in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var anchor: Vector2i = p + shift
			var fs := Defs.footprint(&"dealer", rot)
			var a := Defs.access_cell(&"dealer", anchor, rot)
			var block := Rect2i(Vector2i(a.x & ~1, a.y & ~1), Vector2i(2, 2))
			if not block.intersects(Rect2i(anchor, fs)):
				var r := Rect2i(anchor, fs)
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						if world.has_tree(Vector2i(x, y)):
							world.remove_tree(Vector2i(x, y))
				return world.add_building(&"dealer", anchor, rot)
	push_error("Dealer could not be placed")
	return world.add_building(&"dealer", origin + Vector2i(40, 0), 3)


## Road blocks (2x2) from start to goal on the even lattice; avoids dense forest so it winds.
static func _road_path(world: World, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var n := world.size / Defs.ROAD_BLOCK
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, n, n)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	# keep the road out of the farmyard behind and between the buildings
	var reserved := {}
	for b: Building in world.buildings.values():
		if b.def_id == &"dealer":
			continue
		var r := b.rect().grow(2)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				reserved[Vector2i(x, y) / Defs.ROAD_BLOCK] = true
	for by in n:
		for bx in n:
			var b := Vector2i(bx, by) * Defs.ROAD_BLOCK
			var trees := 0
			var blocked := false
			for y in Defs.ROAD_BLOCK:
				for x in Defs.ROAD_BLOCK:
					var c := b + Vector2i(x, y)
					if world.is_locked(c) or world.occupant[world.idx(c)] != 0:
						blocked = true
					if world.has_tree(c):
						trees += 1
			var p := Vector2i(bx, by)
			grid.set_point_solid(p, blocked or reserved.has(p))
			# forest is expensive and a little noise adds natural bends
			grid.set_point_weight_scale(p, 1.0 + trees * 2.5 + float(hash(p) % 100) / 60.0)
	var from := start / Defs.ROAD_BLOCK
	var to := goal / Defs.ROAD_BLOCK
	grid.set_point_solid(from, false)
	grid.set_point_solid(to, false)
	var out: Array[Vector2i] = []
	for p in grid.get_id_path(from, to):
		out.append(p * Defs.ROAD_BLOCK)
	return out
