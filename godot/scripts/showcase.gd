extends Node3D
## A fighter's model on its own, for the menus: the select screen's turntable,
## tiles and VS portraits. Loads the model the same way fighter.gd does (a
## Blender bomber-bot through model_bot.gd, or Razor's animated glTF), at the
## same uniform height, and plays idle, run or a cheer.

const ModelBot := preload("res://scripts/model_bot.gd")
const HEIGHT := 1.45

var char_id := ""
var still := false          # a one-frame portrait: no motion
var spin := 0.0             # turntable speed, radians a second
var model: Node3D = null
var robot = null
var anim: AnimationPlayer = null
var _names := {}
var _cheer_t := -1.0
var _t := 0.0


func setup(id: String, col: Color) -> void:
	char_id = id
	var glb := "res://assets/characters/%s.glb" % id
	var baked := "res://assets/characters/%s-merged.res" % id
	if ResourceLoader.exists(baked) or ResourceLoader.exists(glb):
		model = Node3D.new()
		add_child(model)
		robot = ModelBot.new()
		robot.setup(glb)
		if id == "tick":
			robot.add_hat_face(col)
		model.add_child(robot)
	else:
		var path := "res://assets/characters/%s.gltf" % id
		var ps = load(path) if ResourceLoader.exists(path) else null
		if not (ps is PackedScene):
			return
		model = ps.instantiate()
		add_child(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if players.size() > 0:
			anim = players[0] as AnimationPlayer
			for n in anim.get_animation_list():
				var full := String(n)
				_names[full.get_slice("|", full.get_slice_count("|") - 1).to_lower()] = full
			for k in ["idle", "run", "walk", "dance"]:
				if _names.has(k):
					anim.get_animation(_names[k]).loop_mode = Animation.LOOP_LINEAR
			_play("idle")
	_normalise()


func _normalise() -> void:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var a: AABB = mi.transform * mi.get_aabb()
		var p := mi.get_parent()
		while p != null and p != model:
			if p is Node3D:
				a = (p as Node3D).transform * a
			p = p.get_parent()
		box = a if first else box.merge(a)
		first = false
	if first or box.size.y <= 0.001:
		return
	var s := HEIGHT / box.size.y
	model.scale = Vector3.ONE * s
	model.position = Vector3(-(box.position.x + box.size.x * 0.5) * s, -box.position.y * s, -(box.position.z + box.size.z * 0.5) * s)


func _play(key: String) -> void:
	if anim == null:
		return
	var n: String = _names.get(key, "")
	if n != "":
		anim.play(n, 0.2)
		anim.seek(0.3, true)   # pose straight away (portraits render one frame)


## The locked-in moment on the select screen: a hop-and-spin (bots) or the
## glTF's own celebration.
func cheer() -> void:
	_cheer_t = 0.0
	if robot:
		robot.cheer()
	elif anim:
		for k in ["dance", "wave", "yes", "jump", "punch"]:
			if _names.has(k):
				_play(k)
				return


func _process(delta: float) -> void:
	if still or model == null:
		return
	_t += delta
	rotation.y += spin * delta
	if robot:
		robot.animate(delta, false, 1.0)
