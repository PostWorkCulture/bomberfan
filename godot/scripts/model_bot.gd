extends Node3D
## A bomber-bot made in Blender (tools/blender/bomber_bots.py, exported as
## assets/characters/<id>.glb). The models are rigid, so all the motion is
## done here: idle bob, a bouncy waddle when running, a hop-and-spin cheer and
## a topple when hit. fighter.gd drives it through animate/die/cheer/revive.

var _body: Node3D
var _t := 0.0
var _dead_t := -1.0
var _cheer_t := -1.0
var _step := 0.0


func setup(scene: PackedScene) -> void:
	_body = scene.instantiate()
	add_child(_body)


func die() -> void:
	_dead_t = 0.0
	_cheer_t = -1.0


func revive() -> void:
	_dead_t = -1.0
	_cheer_t = -1.0
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	if _body:
		_body.rotation = Vector3.ZERO
		_body.position = Vector3.ZERO
		_body.scale = Vector3.ONE


func cheer() -> void:
	_cheer_t = 0.0


func animate(delta: float, moving: bool, speed01: float) -> void:
	_t += delta
	if _body == null:
		return
	if _dead_t >= 0.0:
		# Topple backwards with a little bounce, then lie still.
		_dead_t += delta
		var k := clampf(_dead_t / 0.45, 0.0, 1.0)
		_body.rotation.x = lerpf(0.0, -PI / 2.0, k * k)
		_body.position.y = 0.12 * sin(k * PI)
		return
	if _cheer_t >= 0.0:
		_cheer_t += delta
		var hop := absf(sin(_cheer_t * 7.0))
		_body.position.y = hop * 0.22
		_body.rotation.y = _cheer_t * 6.0
		_body.scale = Vector3(1.0 + (1.0 - hop) * 0.08, 1.0 - (1.0 - hop) * 0.08, 1.0 + (1.0 - hop) * 0.08)
		return
	if moving:
		# Step rate follows speed; each step is a bounce with a side-to-side roll.
		_step += delta * (9.0 + 4.0 * maxf(0.0, speed01 - 1.0))
		var s := sin(_step)
		var bounce := absf(s)
		_body.position.y = bounce * 0.07
		_body.rotation.z = s * 0.11
		_body.rotation.x = 0.16             # lean into the run
		var squash := 1.0 - (1.0 - bounce) * 0.06
		_body.scale = Vector3(2.0 - squash, squash, 2.0 - squash)
	else:
		# Idle: a slow breathing bob, settling back from the run.
		_body.position.y = lerpf(_body.position.y, (sin(_t * 2.4) * 0.5 + 0.5) * 0.025, minf(1.0, delta * 10.0))
		_body.rotation.z = lerpf(_body.rotation.z, sin(_t * 1.3) * 0.03, minf(1.0, delta * 8.0))
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, minf(1.0, delta * 8.0))
		_body.scale = _body.scale.lerp(Vector3.ONE, minf(1.0, delta * 10.0))
