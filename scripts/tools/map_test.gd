extends SceneTree
## Generates maps for a few seeds and prints them as text (one character per 2x2 block):
##   ~ river   o pond   = road   # bridge   B building   T forest   . grass
##   Godot --headless --path . --script scripts/tools/map_test.gd -- [--seeds=1,2,3] [--size=256]


func _init() -> void:
	var seeds := [1, 2, 3, 42]
	var size := 256
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = Array(arg.trim_prefix("--seeds=").split(",")).map(func(s: String) -> int: return int(s))
		elif arg.begins_with("--size="):
			size = int(arg.trim_prefix("--size="))
	for s in seeds:
		var w := WorldGen.generate(size, s)
		var river := 0
		var pond := 0
		for v in w.water:
			if v == Defs.Water.RIVER:
				river += 1
			elif v == Defs.Water.POND:
				pond += 1
		var bridges := 0
		for a: Vector2i in w.road_blocks:
			if w.is_bridge(a):
				bridges += 1
		var on_road := []
		for i in w.road.size():
			if w.road[i] != 0 and w.tree_kind[i] != Defs.TreeKind.NONE:
				on_road.append(Vector2i(i % size, i / size))
		print("seed %d: trees on road tiles: %s" % [s, on_road])
		var spots := 0
		for y in range(0, size, 2):
			for x in range(0, size, 2):
				var a := Vector2i(x, y)
				if w.water[w.idx(a)] == Defs.Water.RIVER and not w.is_locked(a) and w.bridge_ok(a):
					spots += 1
		print("seed %d: %d river blocks can take a bridge" % [s, spots])
		var dealer := w.dealer()
		var farm_to_dealer := w.road_nav.route(w.vehicles[0].garage.access, dealer.access) if dealer else PackedVector2Array()
		print("seed %d: river %d tiles, ponds %d tiles, road blocks %d, bridges %d, pickup route %d points" % [
			s, river, pond, w.road_blocks.size(), bridges, farm_to_dealer.size()])
		var lines := []
		for by in range(0, size, 2):
			var line := ""
			for bx in range(0, size, 2):
				var c := Vector2i(bx, by)
				var ch := "."
				if w.road_blocks.has(c):
					ch = "#" if w.is_bridge(c) else "="
				elif w.building_at(c) != null:
					ch = "B"
				elif w.water[w.idx(c)] == Defs.Water.RIVER:
					ch = "~"
				elif w.water[w.idx(c)] == Defs.Water.POND:
					ch = "o"
				elif w.has_tree(c):
					ch = "T"
				line += ch
			lines.append(line)
		print("\n".join(lines))
	quit()
