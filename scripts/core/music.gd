extends Node
## Background music (autoload "Music", bus Music). The menu theme loops; in the game the tracks play
## shuffled without repeats with silence between them. Changing mode crossfades. Tracks are rendered
## from ABC notes by `art/audio/music/render.sh`.

const MENU_THEME := "res://assets/audio/music/menu_theme.ogg"
## Game tracks, added as they are composed.
const GAME_TRACKS: Array[String] = [
	"res://assets/audio/music/morning_rows.ogg",
	"res://assets/audio/music/duck_pond_waltz.ogg",
	"res://assets/audio/music/long_furrow.ogg",
	"res://assets/audio/music/market_day.ogg",
	"res://assets/audio/music/evening_barn.ogg",
]
const FADE := 2.5                    # seconds of a crossfade
const GAP := Vector2(60.0, 180.0)    # seconds of silence between game tracks
const SILENT_DB := -60.0

var _players: Array[AudioStreamPlayer] = []
var _current := 0                     # index of the player that plays now
var _mode := ""
var _queue: Array[String] = []
var _last := ""
var _gap := 0.0                        # seconds left of silence before the next game track
var _tweens: Array[Tween] = [null, null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		p.finished.connect(_on_finished)
		add_child(p)
		_players.append(p)


## The main menu: its theme, looped.
func play_menu() -> void:
	if _mode == "menu":
		return
	_mode = "menu"
	_crossfade(MENU_THEME, true)


## In the game: the shuffled tracks, starting after a short pause.
func play_game() -> void:
	if _mode == "game":
		return
	_mode = "game"
	_crossfade("", false)
	_gap = 8.0


func _process(delta: float) -> void:
	if _mode != "game" or _gap <= 0.0:
		return
	_gap -= delta
	if _gap <= 0.0:
		var path := _next_track()
		if path != "":
			_crossfade(path, false)


func _next_track() -> String:
	if GAME_TRACKS.is_empty():
		return ""
	if _queue.is_empty():
		_queue = GAME_TRACKS.duplicate()
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _last:
			_queue.reverse()
	_last = _queue.pop_front()
	return _last


## Fades the playing track out and `path` in ("" = only fade out).
func _crossfade(path: String, loop: bool) -> void:
	var old := _players[_current]
	if old.playing:
		_fade(_current, SILENT_DB).tween_callback(old.stop)
	if path == "" or not ResourceLoader.exists(path):
		return
	_current = 1 - _current
	var p := _players[_current]
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_fade(_current, 0.0)


func _fade(i: int, db: float) -> Tween:
	if _tweens[i]:
		_tweens[i].kill()
	_tweens[i] = create_tween()
	_tweens[i].tween_property(_players[i], "volume_db", db, FADE).set_trans(Tween.TRANS_SINE)
	return _tweens[i]


func _on_finished() -> void:
	if _mode == "game" and not _players[_current].playing:
		_gap = randf_range(GAP.x, GAP.y)
