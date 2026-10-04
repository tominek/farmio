class_name WorkerNames
## First names for new workers. The player can give a custom list (settings, e.g. a streamer's
## subscribers): new workers take those first, in order and regardless of look, then the defaults.
## No two living workers get the same name while there are free ones.

const MALE: Array[String] = ["Bo", "Jonas", "Milo", "Ota", "Vik", "Emil", "Hugo", "Ivo", "Leo", "Kai", "Finn", "Tom"]
const FEMALE: Array[String] = ["Tilda", "Ida", "Ema", "Rosa", "Lena", "Alma", "Nora", "Vera", "Mia", "Liv", "Ada", "Ela"]
const MAX_LENGTH := 20

static var custom: PackedStringArray = []


## A name for a new worker with this look (Worker.Look) on the farm.
static func pick(world: World, look: int) -> String:
	var used := {}
	for w in world.workers:
		used[w.name] = true
	for n in custom:
		var name := clean(n)
		if name != "" and not used.has(name):
			return name
	var male := look == Worker.Look.MALE or look == Worker.Look.MALE_VAR
	var names: Array[String] = MALE if male else FEMALE
	var free := names.filter(func(n: String) -> bool: return not used.has(n))
	if free.is_empty():
		free = names
	# from the map seed and the farm's worker count, so a map always gets the same names
	return free[absi(hash([world.seed_value, world.workers.size()])) % free.size()]


## A name as entered by the player: trimmed and at most MAX_LENGTH characters ("" if empty).
static func clean(name: String) -> String:
	return name.strip_edges().left(MAX_LENGTH).strip_edges()
