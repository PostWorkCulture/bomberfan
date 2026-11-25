extends RefCounted
## Bot AI — a simplified port of the browser build's AI module (Normal tier,
## "scrapper" persona). Same principles: a danger map of when each tile burns,
## never lay a bomb without a timed escape, difficulty comes from aggression,
## never from cutting the safety margin.

const Cfg := preload("res://scripts/config.gd")
const Levels := preload("res://scripts/levels.gd")

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SAFE := 999.0
const TRAVEL_FACTOR := 1.45      # grid turns cost time; budget for it

# Normal tier from TIERS in index.html
const THINK := 0.14
const BLUNDER := 0.06
const HUNT := 0.48
const ESCAPE_SLACK := 0.52
const BOMB_GAP := 0.60
const GREED := 0.34
const GREED_RANGE := 4
const SAFE_OPENING_BOMBS := 1
const OPENING_EXTRA_SLACK := 0.35
const GOAL_REFRESH := 1.6

var game = null
var me = null
var rng := RandomNumberGenerator.new()
var timer := 0.0
var path: Array = []
var goal := Vector2i(-1, -1)
var goal_age := 0.0
var bomb_cool := 0.0
var bombs_laid := 0
var _pending_bomb := false


func setup(g, f, seed_value: int) -> void:
	game = g
	me = f
	rng.seed = seed_value


func reset() -> void:
	timer = rng.randf() * 0.1
	path.clear()
	goal = Vector2i(-1, -1)
	goal_age = 0.0
	bomb_cool = 0.4
	bombs_laid = 0
	_pending_bomb = false


## Stepped on a pad: the plan was made on the other side of the board.
func on_teleport() -> void:
	path.clear()
	goal = Vector2i(-1, -1)
	timer = 0.0


func _is_pad(t: Vector2i) -> bool:
	return game.pad_target(t.x, t.y).x >= 0


## Where one step from `cur` in direction d really leaves you: on a pad, its
## twin. Returns [landing, pad tile or null], or [] if the step is blocked.
func _step(cur: Vector2i, d: Vector2i, start: Vector2i) -> Array:
	var n: Vector2i = cur + d
	if not _passable(n, start):
		return []
	if me.pad_cool < 0.25:
		var twin: Vector2i = game.pad_target(n.x, n.y)
		if twin.x >= 0 and _passable(twin, start):
			return [twin, n]
	return [n, null]


## Seconds to cross one tile from `cur` heading d: belts help or hinder.
func _tile_time(cur: Vector2i, d: Vector2i) -> float:
	var belt: Vector2i = game.belt_at(cur.x, cur.y)
	var along: float = float(belt.x * d.x + belt.y * d.y)
	return TRAVEL_FACTOR / maxf(0.6, me.speed + along * Levels.BELT_SPEED)


func update(dt: float) -> Dictionary:
	timer -= dt
	bomb_cool -= dt
	goal_age += dt
	if timer <= 0.0:
		timer = THINK
		_think()
	var bomb := _pending_bomb
	_pending_bomb = false
	return _steer(bomb)


func _slack() -> float:
	return ESCAPE_SLACK + (OPENING_EXTRA_SLACK if bombs_laid < SAFE_OPENING_BOMBS else 0.0)


func _think() -> void:
	var here: Vector2i = me.tile()
	var danger: PackedFloat32Array = game.compute_danger({})
	var hi: int = game.idx(here.x, here.y)

	# 1. Standing somewhere that will burn: run.
	if danger[hi] < SAFE:
		var esc := _escape_path(here, danger, _slack())
		if esc.is_empty():
			esc = _escape_path(here, danger, 0.0)
		path = esc
		goal = esc.back() if not esc.is_empty() else here
		goal_age = 0.0
		return

	if not path.is_empty() and not _path_ok(danger):
		path.clear()
		goal = Vector2i(-1, -1)

	# 2. Worth a bomb here, and a timed escape exists once it is down?
	if bomb_cool <= 0.0 and me.active_bombs < me.max_bombs and _worth_bombing(here) \
			and rng.randf() >= BLUNDER:
		var extra := {"x": here.x, "y": here.y, "fire": me.fire, "fuse": Cfg.BOMB_FUSE}
		var d2: PackedFloat32Array = game.compute_danger(extra)
		var esc2 := _escape_path(here, d2, _slack())
		if not esc2.is_empty():
			_pending_bomb = true
			bomb_cool = BOMB_GAP
			bombs_laid += 1
			path = esc2
			goal = esc2.back()
			goal_age = 0.0
			return

	# 3. Otherwise pick (or keep) somewhere to go.
	if path.is_empty() or goal_age > GOAL_REFRESH or here == goal:
		_choose_goal(here, danger)


func _passable(t: Vector2i, start: Vector2i) -> bool:
	if game.cell_at(t.x, t.y) != 0:
		return false
	var k: int = game.idx(t.x, t.y)
	if t != start and game.bomb_at.has(k):
		return false
	if game.flames.has(k):
		return false
	return true


func _path_ok(danger: PackedFloat32Array) -> bool:
	var here: Vector2i = me.tile()
	for i in mini(2, path.size()):
		var t: Vector2i = path[i]
		if not _passable(t, here) or danger[game.idx(t.x, t.y)] < SAFE:
			return false
	return true


## Shortest route to a tile that never burns, leaving every burning tile
## at least `slack` seconds before it goes off.
func _escape_path(start: Vector2i, danger: PackedFloat32Array, slack: float) -> Array:
	var q: Array = [start]
	var when := {start: 0.0}
	var prev := {}
	var via := {}
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var cur_d: float = danger[game.idx(cur.x, cur.y)]
		if cur_d >= SAFE and (cur == start or not _is_pad(cur)):
			return _rebuild(prev, start, cur, via)
		for d in DIRS:
			var arrive: float = when[cur] + _tile_time(cur, d)
			if arrive + slack > cur_d:
				continue   # cannot get off this tile in time
			var st := _step(cur, d, start)
			if st.is_empty() or when.has(st[0]):
				continue
			when[st[0]] = arrive
			prev[st[0]] = cur
			if st[1] != null:
				via[st[0]] = st[1]
			q.append(st[0])
	return []


func _rebuild(prev: Dictionary, start: Vector2i, end: Vector2i, via := {}) -> Array:
	var out: Array = []
	var c := end
	while c != start:
		out.push_front(c)
		if via.has(c):
			out.push_front(via[c])   # walk onto the pad; it does the rest
		c = prev[c]
	return out


func _worth_bombing(here: Vector2i) -> bool:
	var crate := false
	for c in game.blast_cells(here.x, here.y, me.fire):
		if game.cell_at(c.x, c.y) == 2:
			crate = true
		for f in game.fighters:
			if f != me and f.alive and f.tile() == c and rng.randf() < 0.7:
				return true
	return crate


func _wants(id: String) -> bool:
	match id:
		"bomb":
			return me.max_bombs < Cfg.MAX_BOMBS
		"fire":
			return me.fire < Cfg.MAX_FIRE
		"speed":
			return me.speed_t <= 0.0 or me.speed < Cfg.MAX_SPEED
	return true


func _choose_goal(here: Vector2i, danger: PackedFloat32Array) -> void:
	goal_age = 0.0
	# Everywhere reachable without touching a tile that will burn
	var q: Array = [here]
	var dist := {here: 0}
	var prev := {}
	var via := {}
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for d in DIRS:
			var st := _step(cur, d, here)
			if st.is_empty() or dist.has(st[0]):
				continue
			var n: Vector2i = st[0]
			if danger[game.idx(n.x, n.y)] < SAFE:
				continue
			if st[1] != null and danger[game.idx(st[1].x, st[1].y)] < SAFE:
				continue
			dist[n] = dist[cur] + 1
			prev[n] = cur
			if st[1] != null:
				via[n] = st[1]
			q.append(n)
	# Never settle on a pad: it would send you straight back.
	for t in dist.keys():
		if t != here and _is_pad(t):
			dist.erase(t)

	var target := Vector2i(-1, -1)

	# a) a pick-up worth the detour
	if rng.randf() < GREED:
		var best := 99
		for k in game.pickups.keys():
			var t := Vector2i(k % Cfg.COLS, k / Cfg.COLS)
			if dist.has(t) and dist[t] <= GREED_RANGE and dist[t] < best \
					and _wants(game.pickups[k]["id"]):
				best = dist[t]
				target = t

	# b) come looking for someone
	if target.x < 0 and rng.randf() < HUNT:
		var best_score := 1e9
		for t in dist.keys():
			for f in game.fighters:
				if f == me or not f.alive:
					continue
				var ft: Vector2i = f.tile()
				var md: int = absi(t.x - ft.x) + absi(t.y - ft.y)
				var in_line: bool = (t.x == ft.x or t.y == ft.y) and md <= me.fire
				var score: float = md * 2.0 + dist[t] * 0.5 - (3.0 if in_line else 0.0)
				if score < best_score:
					best_score = score
					target = t

	# c) the nearest spot where a bomb would open crates
	if target.x < 0:
		var best_c := 1e9
		for t in dist.keys():
			if dist[t] == 0 or dist[t] >= best_c:
				continue
			var n := 0
			for c in game.blast_cells(t.x, t.y, me.fire):
				if game.cell_at(c.x, c.y) == 2:
					n += 1
			if n > 0:
				var s: float = dist[t] - n * 0.35
				if s < best_c:
					best_c = s
					target = t

	# d) nothing to do: wander
	if target.x < 0 and dist.size() > 1:
		var keys: Array = dist.keys()
		target = keys[rng.randi_range(1, keys.size() - 1)]

	if target.x < 0 or target == here:
		goal = here
		path = []
	else:
		goal = target
		path = _rebuild(prev, here, target, via)


func _steer(bomb: bool) -> Dictionary:
	var dir := Vector2i.ZERO
	var reach: float = maxf(0.12, me.speed * Cfg.FIXED_DT * 0.6)
	while not path.is_empty():
		var nxt: Vector2i = path[0]
		if absf(me.gx - nxt.x) < reach and absf(me.gy - nxt.y) < reach:
			path.pop_front()
		else:
			break
	var tx: float
	var ty: float
	if path.is_empty():
		var h: Vector2i = me.tile()
		tx = h.x
		ty = h.y
	else:
		var p: Vector2i = path[0]
		tx = p.x
		ty = p.y
	var dx: float = tx - me.gx
	var dy: float = ty - me.gy
	var eps: float = me.speed * Cfg.FIXED_DT * 0.6 + 0.02
	if absf(dx) < eps and absf(dy) < eps:
		return {"dir": dir, "alt": Vector2i.ZERO, "bomb": bomb}
	if absf(dx) >= absf(dy):
		dir = Vector2i(1 if dx > 0.0 else -1, 0)
	else:
		dir = Vector2i(0, 1 if dy > 0.0 else -1)
	return {"dir": dir, "alt": Vector2i.ZERO, "bomb": bomb}
