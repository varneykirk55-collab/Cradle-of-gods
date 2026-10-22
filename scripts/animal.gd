class_name Animal
extends Node3D
## One wild animal. Species behaviour comes from Ecosystem.SPEC. Ground
## animals wander their habitat, graze, flee from predators / people / fire,
## breed and die; wolves hunt; birds fly and perch. Articulated low-poly parts
## (legs, head, tail, wings) are animated procedurally.

enum S { WANDER, GRAZE, REST, FLEE, CHASE, EAT, FLY, PERCH, CARRIED, FLYING, STUNNED }
const STATE_NAMES := ["wandering", "grazing", "resting", "fleeing", "hunting", "feeding", "flying", "perched",
	"held by the god", "flying through the air", "dazed"]

var eco          # Ecosystem
var sim
var species := "deer"
var spec: Dictionary
var state := S.WANDER
var target := Vector3.ZERO
var timer := 0.0
var age := 0.0
var hunger := 0.2
var grow := 1.0
var dead := false
var phase := 0.0
var breed_t := 30.0
var prey = null
var threat := Vector3.ZERO
var vel := Vector3.ZERO
var alt := 10.0
var _scan_t := 0.0
var _speed_now := 0.0
var parts := {}
var rig: Node3D

func setup(p_eco, p_species: String, pos: Vector3, baby: bool) -> void:
	eco = p_eco
	sim = p_eco.sim
	species = p_species
	spec = Ecosystem.SPEC[species]
	rig = Node3D.new()
	rig.scale = Vector3.ONE * spec["scale"]
	add_child(rig)
	parts = Assets.build_parts(species, rig, spec["vis"])
	position = pos
	rotation.y = randf() * TAU
	phase = randf() * TAU
	grow = 0.55 if baby else 1.0
	age = 0.0 if baby else randf_range(0.0, spec["life"] * 0.5)
	hunger = randf_range(0.0, 0.3)
	breed_t = randf_range(0.5, 1.2) * spec["breed"]
	scale = Vector3.ONE * grow
	if species == "bird":
		state = S.FLY
		alt = randf_range(7.0, 14.0)
		position.y = _ground(position) + alt

func is_busy_with_god() -> bool:
	return state == S.CARRIED or state == S.FLYING

func is_adult() -> bool:
	return grow >= 1.0

func describe() -> String:
	return "%s%s\n%s, hunger %d%%" % [spec["name"], " (young)" if grow < 1.0 else "", STATE_NAMES[state], int(hunger * 100)]

func _ground(p: Vector3) -> float:
	return maxf(sim.terrain.height_at(p.x, p.z), Terrain.SEA)

func tick(dt: float) -> void:
	age += dt
	if grow < 1.0:
		grow = minf(1.0, grow + dt / spec["grow"])
		scale = Vector3.ONE * grow
	if state == S.CARRIED:
		_anim(dt, 6.0, true)
		return
	if state == S.FLYING:
		_tick_thrown(dt)
		return
	hunger += dt * spec["hunger"]
	if hunger >= 1.0:
		eco.kill(self, "starvation")
		return
	if age > spec["life"]:
		eco.kill(self, "old age")
		return
	if species != "bird" and sim.terrain.height_at(position.x, position.z) < Terrain.SEA - 0.5:
		eco.kill(self, "drowned")
		return
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 0.5 + randf() * 0.3
		_scan()
	breed_t -= dt
	if breed_t <= 0.0:
		breed_t = spec["breed"] * randf_range(0.8, 1.3)
		if is_adult() and hunger < (0.75 if species == "wolf" else 0.55):
			eco.try_breed(self)
	_speed_now = 0.0
	_lod = position.distance_squared_to(sim.cam_pos) > 110.0 * 110.0 or (sim.cam != null and not sim.cam.is_position_in_frustum(position))
	match state:
		S.WANDER:
			if _move(target, dt, spec["walk"]) or timer <= 0.0:
				_next_idle()
			timer -= dt
		S.GRAZE:
			timer -= dt
			hunger = maxf(0.0, hunger - dt * spec["graze"] * (1.0 + maxf(0.0, sim.terrain.fertility_at(position.x, position.z))))
			if timer <= 0.0: _wander()
		S.REST:
			timer -= dt
			if timer <= 0.0: _wander()
		S.FLEE:
			timer -= dt
			var away := Vector3(position.x - threat.x, 0, position.z - threat.z)
			if away.length() < 0.01: away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			_move(position + away.normalized() * 8.0, dt, spec["run"])
			if timer <= 0.0: _wander()
		S.CHASE:
			timer -= dt
			if prey == null or prey.dead or timer <= 0.0 or prey.is_busy_with_god():
				prey = null
				_rest(4.0)
			else:
				var d: float = Vector2(prey.position.x - position.x, prey.position.z - position.z).length()
				if d < 0.9:
					eco.predation(self, prey)
					prey = null
					state = S.EAT
					timer = 6.0
				else:
					_move(prey.position, dt, spec["run"])
		S.EAT:
			timer -= dt
			if timer <= 0.0: _rest(8.0)
		S.STUNNED:
			timer -= dt
			if timer <= 0.0: _wander()
		S.FLY:
			_tick_fly(dt)
		S.PERCH:
			timer -= dt
			hunger = maxf(0.0, hunger - dt * spec["graze"])
			if timer <= 0.0:
				state = S.FLY
				alt = randf_range(7.0, 14.0)
				_bird_target()
	_anim(dt, _speed_now, false)

# ------------------------------------------------------------------ behaviour
func _scan() -> void:
	if state in [S.STUNNED, S.EAT]: return
	if species == "bird":
		if state == S.PERCH and eco.threat_for(self, 5.0) != null:
			state = S.FLY
			alt = randf_range(8.0, 14.0)
			_bird_target()
		return
	var th = eco.threat_for(self, spec["alert"])
	if th != null:
		threat = th
		if state != S.FLEE:
			state = S.FLEE
		timer = randf_range(2.0, 3.5)
		return
	if species == "wolf" and state != S.CHASE and hunger > 0.42:
		var p = eco.find_wolf_prey(self, 26.0)
		if p != null:
			prey = p
			state = S.CHASE
			timer = 15.0

func _next_idle() -> void:
	if hunger > 0.3 and spec["graze"] > 0.0:
		state = S.GRAZE
		timer = randf_range(4.0, 9.0)
		if species == "deer": eco.browse_bush(self)
	else:
		_rest(randf_range(3.0, 8.0))

func _rest(t: float) -> void:
	state = S.REST
	timer = t

func _wander() -> void:
	target = eco.habitat_target(self)
	state = S.WANDER
	timer = 14.0

func grab() -> void:
	state = S.CARRIED
	prey = null

func throw(v: Vector3) -> void:
	state = S.FLYING
	vel = v

func _tick_thrown(dt: float) -> void:
	vel.y -= 22.0 * dt
	var np := position + vel * dt
	np.x = clampf(np.x, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
	np.z = clampf(np.z, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
	rotation.x += dt * 3.0
	_anim(dt, 6.0, true)
	if species == "bird" and vel.y < 0.0 and vel.length() < 14.0:
		rotation.x = 0.0
		state = S.FLY
		alt = maxf(5.0, np.y - _ground(np))
		position = np
		_bird_target()
		return
	var gh: float = _ground(np)
	if np.y <= gh:
		position = Vector3(np.x, gh, np.z)
		rotation.x = 0.0
		eco.on_landed(self, vel)
		return
	position = np

func _bird_target() -> void:
	var a := randf() * TAU
	target = position + Vector3(cos(a), 0, sin(a)) * randf_range(10.0, 30.0)
	var kin = eco.kin_center(self, 40.0)
	if kin != null and randf() < 0.7:
		target = kin + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 10.0)   # flock together
	target.x = clampf(target.x, -Terrain.HALF + 8, Terrain.HALF - 8)
	target.z = clampf(target.z, -Terrain.HALF + 8, Terrain.HALF - 8)
	timer = randf_range(8.0, 20.0)

func _tick_fly(dt: float) -> void:
	timer -= dt
	var gy: float = _ground(position)
	var to := Vector3(target.x - position.x, 0, target.z - position.z)
	hunger = maxf(0.0, hunger - dt * 0.0015)   # catches insects on the wing
	if to.length() < 2.0 or timer <= 0.0:
		if hunger > 0.4 or (randf() < 0.3 and hunger > 0.2):
			var spot = eco.perch_spot(self)
			if spot != null:
				target = spot
				alt = 0.0
				timer = 12.0
			else:
				_bird_target()
		else:
			_bird_target()
		to = Vector3(target.x - position.x, 0, target.z - position.z)
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	var sp: float = spec["run"]
	position += dir * sp * dt
	var want_y := gy + alt
	if alt <= 0.0:
		want_y = _ground(target) + 0.05
		if to.length() < 1.0 and absf(position.y - want_y) < 0.4:
			position.y = want_y
			state = S.PERCH
			timer = randf_range(5.0, 12.0)
			return
	position.y = lerpf(position.y, want_y, minf(1.0, dt * 1.5))
	_face(position + dir, dt)
	_speed_now = sp

## Ground steering with water / cliff / settlement avoidance. Returns arrival.
func _move(dest: Vector3, dt: float, sp: float) -> bool:
	var to := Vector3(dest.x - position.x, 0, dest.z - position.z)
	if to.length() < 0.5: return true
	var dir := to.normalized()
	var step := sp * dt * (0.6 + 0.4 * grow)
	for ang in [0.0, 0.7, -0.7, 1.4, -1.4, 2.2, -2.2, 3.0]:
		var d2 := dir.rotated(Vector3.UP, ang)
		var np := position + d2 * step
		if not sim.terrain.in_bounds(np.x, np.z, 3.0): continue
		if sim.terrain.height_at(np.x, np.z) < Terrain.SEA + 0.15: continue
		if sim.terrain.slope_at(np.x, np.z) > 2.2: continue
		position = Vector3(np.x, sim.terrain.height_at(np.x, np.z), np.z)
		_face(position + d2, dt)
		_speed_now = sp
		return false
	timer = minf(timer, 0.2)
	return false

func _face(p: Vector3, dt: float) -> void:
	var dx := p.x - position.x
	var dz := p.z - position.z
	if absf(dx) + absf(dz) > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(dx, dz), minf(1.0, dt * 7.0))

# ------------------------------------------------------------------ animation
var _lod := false
var _lod_n := 0

func _anim(dt: float, sp: float, flail: bool) -> void:
	if _lod:
		_lod_n += 1
		if _lod_n % 4 != 0: return
		dt *= 4.0
	var k := minf(1.0, dt * 10.0)
	phase += dt * (3.0 + sp * spec["gait"])
	var s := sin(phase)
	match species:
		"bird":
			var flap := 0.0
			if state == S.PERCH:
				flap = 0.05
				_lerp_rot(parts["body"], Vector3(0.25 + maxf(0.0, sin(phase * 0.7)) * 0.5, 0, 0), k)
			else:
				flap = s * 0.95
				_lerp_rot(parts["body"], Vector3(0, 0, 0), k)
			parts["wing_l"].rotation.z = flap
			parts["wing_r"].rotation.z = -flap
		"rabbit":
			var hop := absf(s) if sp > 0.1 else 0.0
			rig.position.y = lerpf(rig.position.y, hop * 0.18 * spec["scale"], k)
			_lerp_rot(parts["leg_bl"], Vector3(-hop * 0.9, 0, 0), k)
			_lerp_rot(parts["leg_br"], Vector3(-hop * 0.9, 0, 0), k)
			_lerp_rot(parts["leg_fl"], Vector3(hop * 0.6, 0, 0), k)
			_lerp_rot(parts["leg_fr"], Vector3(hop * 0.6, 0, 0), k)
			var graze := state == S.GRAZE
			_lerp_rot(parts["head"], Vector3(0.5 if graze else 0.0, 0, 0), k)
			_lerp_rot(parts["ear_l"], Vector3(-0.3 if state == S.FLEE else sin(phase * 0.3) * 0.15, 0, 0.15), k)
			_lerp_rot(parts["ear_r"], Vector3(-0.3 if state == S.FLEE else sin(phase * 0.3 + 1.0) * 0.15, 0, -0.15), k)
		_:
			var amp := clampf(sp / maxf(1.0, spec["run"]) * 1.4, 0.0, 0.8) if not flail else 0.9
			var gallop: bool = sp > spec["walk"] * 1.3
			var a := s * amp
			var b := sin(phase + (0.6 if gallop else PI)) * amp
			_lerp_rot(parts["leg_fl"], Vector3(a, 0, 0), k)
			_lerp_rot(parts["leg_br"], Vector3(a if not gallop else -a, 0, 0), k)
			_lerp_rot(parts["leg_fr"], Vector3(b, 0, 0), k)
			_lerp_rot(parts["leg_bl"], Vector3(b if not gallop else -b, 0, 0), k)
			var head_x := 0.0
			if state == S.GRAZE or state == S.EAT: head_x = 0.9 + sin(phase * 0.5) * 0.1
			elif state == S.REST: head_x = 0.15
			elif state == S.FLEE or state == S.CHASE: head_x = -0.15
			_lerp_rot(parts["head"], Vector3(head_x, sin(phase * 0.2) * 0.25 if state == S.REST else 0.0, 0), k)
			var wag := sin(phase * (2.5 if species == "wolf" else 1.5)) * (0.5 if species == "wolf" else 0.25)
			_lerp_rot(parts["tail"], Vector3(-0.3 if gallop else 0.0, wag, 0), k)
			_lerp_rot(parts["body"], Vector3(sin(phase * 2.0) * 0.05 * amp, 0, 0), k)
			rig.position.y = lerpf(rig.position.y, absf(sin(phase)) * 0.06 * amp * spec["scale"] if gallop else 0.0, k)

func _lerp_rot(n: Node3D, e: Vector3, k: float) -> void:
	n.rotation = n.rotation.lerp(e, k)
