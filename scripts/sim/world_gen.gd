class_name WorldGen
## Procedural map: noise tree clusters, boundary forest, a river from one map edge to another
## and a few ponds, farm origin (Storage Barn + Garage on a short road), Dealer at a random spot
## and a winding dirt road between them (with a bridge if the river is in the way).

const FARM_CLEAR_RADIUS := 18
const DEALER_CLEAR_RADIUS := 7
const RIVER_FARM_GAP := 28         # tiles between the farm origin and the river
const POND_FARM_GAP := 26
const RIVER_STEP := 3              # blocks the river drifts before it steps sideways
const RIVER_BEND_RADIUS := 3.0     # tiles: the axis bends on a 9 m arc, like a wide road curve over 2x2 blocks
const SHORE_CLEAR := 1             # tiles next to water without trees; one more tile is thinned out
const ROAD_TURN_COST := 6.0        # extra path cost of a bend on the generated road


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
	# water has its own random stream so the rest of the map stays as it was for a seed
	var water_rng := RandomNumberGenerator.new()
	water_rng.seed = seed_value + 7919
	_make_river(world, water_rng, origin)
	_make_ponds(world, water_rng, origin)
	_clear_shore(world, water_rng)
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
	_clear_bend_insides(world)

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


## River of 2x2 blocks on the road lattice, from one map edge to the opposite one. Its course is a
## gently meandering curve (two long sine waves plus noise) across the map; the river only steps
## sideways once the curve has drifted RIVER_STEP blocks away, so it runs in long straight stretches
## (room for bridges) joined by short sideways runs. It keeps away from the farm.
static func _make_river(world: World, rng: RandomNumberGenerator, origin: Vector2i) -> void:
	var n := world.size / Defs.ROAD_BLOCK
	var noise := FastNoiseLite.new()
	noise.seed = world.seed_value + 31
	noise.frequency = 0.05
	var vertical := rng.randf() < 0.5
	# farm in (along, across) block coordinates
	var farm := Vector2(origin) / Defs.ROAD_BLOCK
	var farm_t := farm.y if vertical else farm.x
	var farm_c := farm.x if vertical else farm.y
	var gap := float(RIVER_FARM_GAP) / Defs.ROAD_BLOCK
	var course := PackedFloat32Array()
	for attempt in 40:
		var base := rng.randf_range(n * 0.2, n * 0.8)
		var waves := []
		for k in 2:
			waves.append([rng.randf_range(4.0, 10.0) / (k + 1), TAU / rng.randf_range(50.0, 110.0) * (k + 1), rng.randf() * TAU])
		course.resize(n)
		var ok := true
		for t in n:
			var c := base + noise.get_noise_1d(t) * 3.0
			for w: Array in waves:
				c += w[0] * sin(t * w[1] + w[2])
			course[t] = clampf(c, 1.0, n - 2.0)
			if Vector2(t, course[t]).distance_to(Vector2(farm_t, farm_c)) < gap:
				ok = false
		if ok:
			break
	# along the main axis one row at a time; the held position follows the curve only in steps
	# of RIVER_STEP blocks or more, a sideways run makes each step
	var blocks: Array[Vector2i] = []
	var held := roundi(course[0])
	var prev := held
	for t in n:
		if absf(course[t] - held) >= RIVER_STEP:
			held = roundi(course[t])
		var cur := held
		var step := 1 if cur >= prev else -1
		for c in range(prev, cur + step, step):
			blocks.append(Vector2i(c, t) if vertical else Vector2i(t, c))
		prev = cur
	# axis through the block centres (in tiles), running on past both map edges
	var pts := PackedVector2Array()
	for b in blocks:
		pts.append(Vector2(b) * Defs.ROAD_BLOCK + Vector2.ONE)
	var out_dir := Vector2(0, 1) if vertical else Vector2(1, 0)
	pts.insert(0, pts[0] - out_dir * 4.0)
	pts.append(pts[pts.size() - 1] + out_dir * 4.0)
	var axis := _round_corners(_corner_points(pts), RIVER_BEND_RADIUS)
	# every tile whose centre lies within one tile of the axis is river: exactly the blocks on
	# straight stretches, a wide arc in the bends
	for i in axis.size() - 1:
		var a := axis[i]
		var b := axis[i + 1]
		var lo := Vector2i(floori(minf(a.x, b.x) - 2), floori(minf(a.y, b.y) - 2))
		var hi := Vector2i(ceili(maxf(a.x, b.x) + 2), ceili(maxf(a.y, b.y) + 2))
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				var c := Vector2i(x, y)
				if world.in_bounds(c) and Geometry2D.get_closest_point_to_segment(Vector2(c) + Vector2(0.5, 0.5), a, b).distance_to(Vector2(c) + Vector2(0.5, 0.5)) <= 1.0:
					world.set_water(c, Defs.Water.RIVER)


## Only the points where the direction changes (plus both ends).
static func _corner_points(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		if not ((pts[i] - pts[i - 1]).normalized()).is_equal_approx((pts[i + 1] - pts[i]).normalized()):
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


## Replaces each corner of a right-angled polyline by a quarter arc of `radius` (smaller where the
## neighbouring stretches are too short), sampled as short segments.
static func _round_corners(pts: PackedVector2Array, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var v := pts[i]
		var u := (v - pts[i - 1]).normalized()
		var w := (pts[i + 1] - v).normalized()
		var r := minf(radius, minf(v.distance_to(pts[i - 1]), v.distance_to(pts[i + 1])) * 0.5)
		var a := v - u * r
		var centre := a + w * r
		var start := (a - centre).angle()
		var turn := signf(u.cross(w)) * PI * 0.5
		for k in 9:
			var ang := start + turn * k / 8.0
			out.append(centre + Vector2(cos(ang), sin(ang)) * r)
	out.append(pts[pts.size() - 1])
	return out


## Two to four ponds of organic shape (sometimes one larger lake), away from the farm and the river.
static func _make_ponds(world: World, rng: RandomNumberGenerator, origin: Vector2i) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = world.seed_value + 53
	shape.frequency = 0.18
	var margin := Defs.BORDER + 4
	for k in rng.randi_range(2, 4):
		var big := k == 0 and rng.randf() < 0.4
		var r := rng.randf_range(5.0, 8.0) if big else rng.randf_range(2.0, 4.0)
		for attempt in 40:
			var c := Vector2i(rng.randi_range(margin + int(r), world.size - margin - int(r)),
				rng.randi_range(margin + int(r), world.size - margin - int(r)))
			if Vector2(c).distance_to(origin) < POND_FARM_GAP + r:
				continue
			var reach := int(r * 1.4) + 4
			var free := true
			for y in range(c.y - reach, c.y + reach + 1):
				for x in range(c.x - reach, c.x + reach + 1):
					if world.is_water(Vector2i(x, y)):
						free = false
			if not free:
				continue
			for y in range(c.y - reach, c.y + reach + 1):
				for x in range(c.x - reach, c.x + reach + 1):
					var p := Vector2i(x, y)
					var edge := r * (1.0 + 0.35 * shape.get_noise_2d(x, y))
					if world.in_bounds(p) and Vector2(p).distance_to(c) <= edge:
						world.set_water(p, Defs.Water.POND)
			break


## Trees off the block on the inside of every road bend, so the bend can be drawn as a wide curve.
static func _clear_bend_insides(world: World) -> void:
	for a: Vector2i in world.road_blocks:
		for r in 4:
			var d1: Vector2i = Defs.DIRS[r] * Defs.ROAD_BLOCK
			var d2: Vector2i = Defs.DIRS[(r + 1) % 4] * Defs.ROAD_BLOCK
			if world.road_blocks.has(a + d1) and world.road_blocks.has(a + d2):
				var inside := a + d1 + d2
				for y in Defs.ROAD_BLOCK:
					for x in Defs.ROAD_BLOCK:
						var c := inside + Vector2i(x, y)
						if world.has_tree(c) and not world.is_locked(c):
							world.remove_tree(c)


## Open banks: no trees right next to water, every other one a tile further out.
static func _clear_shore(world: World, rng: RandomNumberGenerator) -> void:
	var reach := SHORE_CLEAR + 1
	for y in world.size:
		for x in world.size:
			var c := Vector2i(x, y)
			if not world.has_tree(c):
				continue
			var near := 99
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					if world.is_water(c + Vector2i(dx, dy)):
						near = mini(near, maxi(absi(dx), absi(dy)))
			if near <= SHORE_CLEAR or (near == reach and rng.randf() < 0.5):
				world.remove_tree(c)


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
			if not block.intersects(Rect2i(anchor, fs)) and not _wet(world, Rect2i(anchor, fs).merge(block).grow(2)):
				var r := Rect2i(anchor, fs)
				for y in range(r.position.y, r.end.y):
					for x in range(r.position.x, r.end.x):
						if world.has_tree(Vector2i(x, y)):
							world.remove_tree(Vector2i(x, y))
				return world.add_building(&"dealer", anchor, rot)
	push_error("Dealer could not be placed")
	return world.add_building(&"dealer", origin + Vector2i(40, 0), 3)


static func _wet(world: World, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if world.is_water(Vector2i(x, y)):
				return true
	return false


## Road blocks (2x2) from start to goal on the even lattice; avoids dense forest so it winds.
## Water is not crossed on its own: if the river is in the way, the road goes over one bridge
## block across a straight stretch of the river (the crossing that makes the road shortest).
static func _road_path(world: World, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var grid := _road_grid(world)
	# the ends lie at the farm road and in front of the Dealer
	grid.set_point_solid(start / Defs.ROAD_BLOCK, false)
	grid.set_point_solid(goal / Defs.ROAD_BLOCK, false)
	var direct := _grid_path(grid, start, goal)
	if not direct.is_empty():
		return direct
	var candidates := []
	for anchor in _bridge_spots(world):
		candidates.append([Vector2(start).distance_to(anchor) + Vector2(anchor).distance_to(goal), anchor])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var best: Array[Vector2i] = []
	for cand in candidates.slice(0, 12):
		var bridge: Vector2i = cand[1]
		var across := Vector2i(0, Defs.ROAD_BLOCK) if world.river_axis(bridge) == 0 else Vector2i(Defs.ROAD_BLOCK, 0)
		for side in [1, -1]:
			var near: Vector2i = bridge - across * side
			var far: Vector2i = bridge + across * side
			var a := _grid_path(grid, start, near)
			var b := _grid_path(grid, far, goal)
			if a.is_empty() or b.is_empty():
				continue
			if best.is_empty() or a.size() + b.size() + 1 < best.size():
				best = a
				best.append(bridge)
				best.append_array(b)
	if best.is_empty():
		push_warning("No road to the Dealer: the river could not be crossed")
	return best


static func _bridge_spots(world: World) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(0, world.size, Defs.ROAD_BLOCK):
		for x in range(0, world.size, Defs.ROAD_BLOCK):
			var a := Vector2i(x, y)
			if world.water[world.idx(a)] == Defs.Water.RIVER and not world.is_locked(a) and world.bridge_ok(a):
				out.append(a)
	return out


static func _grid_path(grid: AStarGrid2D, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var from := start / Defs.ROAD_BLOCK
	var to := goal / Defs.ROAD_BLOCK
	var out: Array[Vector2i] = []
	if grid.is_point_solid(from) or grid.is_point_solid(to):
		return out
	for p in _turning_path(grid, from, to):
		out.append(p * Defs.ROAD_BLOCK)
	return out


## Cheapest block path where every change of direction costs ROAD_TURN_COST extra, so the road runs
## in long straight stretches (room for wide curves) instead of staircases. Search state = block +
## the direction it was entered from; weights and solid blocks come from the AStarGrid2D.
static func _turning_path(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var n := grid.region.size.x
	var best := {}                          # state -> cost
	var came := {}                          # state -> previous state
	var heap: Array = []                    # [priority, cost, state]  (state = Vector3i(x, y, dir))
	for d in 4:
		var s := Vector3i(from.x, from.y, d)
		best[s] = 0.0
		_heap_push(heap, [Vector2(from).distance_to(to), 0.0, s])
	var goal_state := Vector3i(-1, -1, -1)
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var s: Vector3i = top[2]
		var cost: float = top[1]
		if cost > best.get(s, INF):
			continue
		if s.x == to.x and s.y == to.y:
			goal_state = s
			break
		for d in 4:
			if (d + 2) % 4 == s.z and Vector2i(s.x, s.y) != from:
				continue                    # no U-turns
			var p := Vector2i(s.x, s.y) + Defs.DIRS[d]
			if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n or grid.is_point_solid(p):
				continue
			var c := cost + grid.get_point_weight_scale(p)
			if d != s.z and Vector2i(s.x, s.y) != from:
				c += ROAD_TURN_COST
			var ns := Vector3i(p.x, p.y, d)
			if c < best.get(ns, INF):
				best[ns] = c
				came[ns] = s
				_heap_push(heap, [c + Vector2(p).distance_to(to), c, ns])
	var out: Array[Vector2i] = []
	if goal_state.x < 0:
		return out
	var st := goal_state
	while true:
		out.push_front(Vector2i(st.x, st.y))
		if not came.has(st):
			break
		st = came[st]
	return out


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var tmp: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = tmp
			i = m
	return top


static func _road_grid(world: World) -> AStarGrid2D:
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
					if world.is_locked(c) or world.occupant[world.idx(c)] != 0 or world.is_water(c):
						blocked = true
					if world.has_tree(c):
						trees += 1
			var p := Vector2i(bx, by)
			grid.set_point_solid(p, blocked or reserved.has(p))
			# forest is expensive and a little noise adds natural bends
			grid.set_point_weight_scale(p, 1.0 + trees * 2.5 + float(hash(p) % 100) / 60.0)
	return grid
