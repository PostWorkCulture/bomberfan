extends Node
## Sound: one-shot effects from a small voice pool, the round's music
## (Arcade Drive, picked by Pete 2026-11-24) and a wind bed. The WAVs are rendered by ../tools/render_sfx.py from
## the browser build's own synth recipes, so the two builds sound the same.

const SFX := [
	"place_bomb", "explode_1", "explode_2", "explode_3", "break_block_1", "break_block_2",
	"pickup", "death", "countdown_lo", "countdown_hi", "go", "round_win", "match_win",
	"sd_warning", "sd_start", "wall_slam",
	"tide", "fizz", "press", "lever", "shield_pop", "ghost", "thunder", "whoosh", "build",
	"kick", "ui_move", "ui_select", "ui_back", "ui_lock", "vs_slam", "ui_start",
]
## Front end (2026-11-27): the menus and the select screen have their own loop.
const MENU_MUSIC := "music_neon_select"
## Round music and ambience bed per arena (2026-11-25). Forest keeps Pete's
## pick, Arcade Drive.
const ARENA_MUSIC := {"forest": "music_arcade_drive", "beach": "music_tide_pop",
	"haunted": "music_graveyard_swing", "factory": "music_tension_pulse"}
const ARENA_AMBIENCE := {"forest": "ambience_forest", "beach": "ambience_beach",
	"haunted": "ambience_haunted", "factory": "ambience_factory"}
const SettingsScript := preload("res://scripts/settings.gd")
const VARIANTS := {"explode": 3, "break_block": 2}
const POOL_SIZE := 16
const MUSIC := "music_arcade_drive"
const MUSIC_DB := -9.0   # the loop is mastered hot; sit it under the effects

var enabled := true
var _streams := {}
var _pool: Array = []
var _last := {}
var _music: AudioStreamPlayer
var _music_tween: Tween
var _ambience: AudioStreamPlayer
var _music_on := false
var _menu := false          # menu music locked in: rounds behind the menus keep it
var sfx_offset_db := 0.0    # the attract-mode match behind the menus plays quieter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # menu clicks still sound while paused
	SettingsScript.ensure_bus("Music")
	SettingsScript.ensure_bus("SFX")
	var music_bus := "Music"
	var sfx_bus := "SFX"
	for n in SFX + ARENA_MUSIC.values() + ARENA_AMBIENCE.values() + [MENU_MUSIC]:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
		else:
			push_warning("Missing sound %s" % path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.stream = _streams.get(MUSIC)
	_music.volume_db = MUSIC_DB
	_music.bus = music_bus
	_music.finished.connect(_on_music_finished)   # backup if the loop point is ever lost
	add_child(_music)
	var ms = _music.stream
	if ms is AudioStreamWAV and ms.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		push_warning("Round music has no loop point: falling back to restart-on-finish")
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _streams.get("ambience_forest")
	_ambience.volume_db = -11.0
	_ambience.bus = sfx_bus
	_ambience.finished.connect(_ambience.play)
	add_child(_ambience)
	# Soft ceiling on the master bus, like the browser's soft clipper: four
	# bombs going off together should get louder, not crackle.
	if ClassDB.class_exists("AudioEffectHardLimiter") and AudioServer.get_bus_effect_count(0) == 0:
		var lim = ClassDB.instantiate("AudioEffectHardLimiter")
		lim.set("ceiling_db", -0.5)
		AudioServer.add_bus_effect(0, lim)


func start_ambience() -> void:
	if enabled and _ambience.stream and not _ambience.playing:
		_ambience.play()


## sound may be a family ("explode") that picks one of its rendered variants.
func play(sound: String, volume_db := 0.0, pitch_var := 0.0, min_gap := 0.03) -> void:
	if not enabled:
		return
	var key := sound
	if VARIANTS.has(sound):
		key = "%s_%d" % [sound, randi_range(1, VARIANTS[sound])]
	var stream = _streams.get(key)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -10.0)) < min_gap:
		return
	_last[sound] = now
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db + sfx_offset_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


## Music runs through the countdown and the round, and fades out for the
## win sting.
func music(on: bool) -> void:
	if _menu:
		return
	var want := on and enabled
	if want == _music_on:
		return
	_music_on = want
	if _music_tween:
		_music_tween.kill()
	if _music_on and _music.stream:
		_music.volume_db = MUSIC_DB
		if not _music.playing:
			_music.play()
	elif _music.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", -40.0, 0.7)
		_music_tween.tween_callback(_music.stop)


## Switch music and ambience to this arena's. Takes effect from the next
## music(true); the bed crossfades straight away.
func set_arena(id: String) -> void:
	var m = _streams.get(ARENA_MUSIC.get(id, MUSIC))
	if m != null and _music.stream != m and not _menu:
		_music.stop()
		_music_on = false
		_music.stream = m
	var a = _streams.get(ARENA_AMBIENCE.get(id, "ambience_forest"))
	if a != null and _ambience.stream != a:
		var was := _ambience.playing
		_ambience.stream = a
		if was:
			_ambience.play()


func _on_music_finished() -> void:
	if _music_on:
		_music.play()


## The front end's loop, locked in until the scene changes: the attract-mode
## rounds behind the menus never swap it for an arena track.
func menu_music() -> void:
	_menu = true
	var m = _streams.get(MENU_MUSIC)
	if m == null or not enabled:
		return
	if _music_tween:
		_music_tween.kill()
	_music.stream = m
	_music.volume_db = MUSIC_DB
	_music_on = true
	_music.play()


## Interface sounds ignore the attract-mode offset.
func ui(sound: String, volume_db := 0.0) -> void:
	var off := sfx_offset_db
	sfx_offset_db = 0.0
	play(sound, volume_db, 0.0, 0.04)
	sfx_offset_db = off
