extends Node

## Global utility functions.


static func format_time(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % seconds
	elif seconds < 3600:
		var m: int = seconds / 60
		var s: int = seconds % 60
		if s == 0:
			return "%dm" % m
		return "%dm %ds" % [m, s]
	else:
		var h: int = seconds / 3600
		var m: int = (seconds % 3600) / 60
		if m == 0:
			return "%dh" % h
		return "%dh %dm" % [h, m]


static func format_weight(kg: int) -> String:
	if kg < 1000:
		return "%d kg" % kg
	else:
		var tonnes: float = kg / 1000.0
		return "%.1f t" % tonnes
