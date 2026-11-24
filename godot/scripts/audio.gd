extends Node
## Sound: one-shot effects from a small voice pool, the round's forest bass
## pulse and a wind bed. The WAVs are rendered by ../tools/render_sfx.py from
## the browser build's own synth recipes, so the two builds sound the same.

const SFX := [
	"place_bomb", "explode_1", "explode_2", "explode_3", "break_block_1", "break_block_2",
	"pickup", "death", "countdown_lo", "countdown_hi", "go", "round_win", "match_win",
]
const VARIANTS := {"explode": 3, "break_block": 2}
const POOL_SIZE := 16

var enabled := true
var _streams := {}
var _pool: Array = []
var _last := {}
var _bass: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _bass_on := false


func _ready() -> void:
	for n in SFX + ["bass_forest", "ambience_forest"]:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
		else:
			push_warning("Missing sound %s" % path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_bass = AudioStreamPlayer.new()
	_bass.stream = _streams.get("bass_forest")
	_bass.volume_db = -2.0
	_bass.finished.connect(_on_bass_finished)
	add_child(_bass)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _streams.get("ambience_forest")
	_ambience.volume_db = -6.0
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


## name may be a family ("explode") that picks one of its rendered variants.
func play(name: String, volume_db := 0.0, pitch_var := 0.0, min_gap := 0.03) -> void:
	if not enabled:
		return
	var key := name
	if VARIANTS.has(name):
		key = "%s_%d" % [name, randi_range(1, VARIANTS[name])]
	var stream = _streams.get(key)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -10.0)) < min_gap:
		return
	_last[name] = now
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


func bass(on: bool) -> void:
	_bass_on = on and enabled
	if _bass_on and not _bass.playing and _bass.stream:
		_bass.play()
	elif not _bass_on and _bass.playing:
		_bass.stop()


func _on_bass_finished() -> void:
	if _bass_on:
		_bass.play()
