extends Node
## Autoload "Settings": the player's options (saved to user://settings.cfg)
## and the hand-off between the front end and a match. game.gd reloads its
## scene to go from the menus into a match and back; an autoload survives
## that, so the choices made on the menus reach the next scene.

const PATH := "user://settings.cfg"
const ARENAS := ["random", "forest", "beach", "haunted", "factory"]
const ARENA_NAMES := {"random": "Random", "forest": "Forest", "beach": "Beach", "haunted": "Haunted House", "factory": "Factory"}
const DIFFICULTIES := ["easy", "normal", "hard"]
const WINS := [1, 2, 3]   # rounds to win the match (ROUND_OPTIONS in index.html)

# ---- Saved options
var difficulty := "normal"
var wins := 3
var arena := "random"
var music := 7          # 0..10
var sfx := 9            # 0..10
var fighter := "ninja"  # last fighter picked on the select screen

# ---- Session hand-off (not saved)
var start_match := false    # the next scene load plays a match, not the menus
var cast: Array = []        # [your id, three bot ids], as shown on the VS screen
var first_level := ""       # the arena the VS screen announced
var open_screen := ""       # the front end opens on this screen ("select", "main")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_audio()


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	var d: String = c.get_value("match", "difficulty", difficulty)
	difficulty = d if d in DIFFICULTIES else "normal"
	var w: int = int(c.get_value("match", "wins", wins))
	wins = w if w in WINS else 3
	var a: String = c.get_value("match", "arena", arena)
	arena = a if a in ARENAS else "random"
	music = clampi(int(c.get_value("audio", "music", music)), 0, 10)
	sfx = clampi(int(c.get_value("audio", "sfx", sfx)), 0, 10)
	fighter = String(c.get_value("player", "fighter", fighter))


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("match", "difficulty", difficulty)
	c.set_value("match", "wins", wins)
	c.set_value("match", "arena", arena)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("player", "fighter", fighter)
	c.save(PATH)


## Music and SFX buses, created on first use, at the saved levels.
func apply_audio() -> void:
	_set_bus("Music", music)
	_set_bus("SFX", sfx)


static func ensure_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


func _set_bus(bus_name: String, level: int) -> void:
	var i := ensure_bus(bus_name)
	AudioServer.set_bus_mute(i, level <= 0)
	# A gentle curve: each step sounds about as big as the last.
	AudioServer.set_bus_volume_db(i, linear_to_db(pow(maxf(level, 1) / 10.0, 1.6)))


func arena_name(id: String) -> String:
	return ARENA_NAMES.get(id, id.capitalize())
