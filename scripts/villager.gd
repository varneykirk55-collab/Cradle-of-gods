class_name Villager
extends Node3D
## An autonomous inhabitant. Driven by WorldSim.update() (so it obeys pause /
## time speed). Simple utility AI: build > gather what the tribe needs > explore.

enum S { IDLE, TO_RES, GATHER, RETURN, TO_BUILD, BUILD, WANDER }

var sim          # WorldSim
var tribe        # WorldSim.Tribe
var state := S.IDLE
var target := Vector3.ZERO
var res = null   # WorldSim.Res
var bld = null   # WorldSim.Building
var carry_type := -1
var carry_amt := 0.0
var timer := 0.0
var idle_t := 0.0
var stuck_t := 0.0
var speed := 2.2
var age := 0.0
var lifespan := 300.0
var grow := 1.0
var phase := 0.0
var dead := false
var body: MeshInstance3D
var bundle: MeshInstance3D

func setup(p_sim, p_tribe, pos: Vector3, child: bool) -> void:
	sim = p_sim
	phase = randf() * TAU
	speed = randf_range(1.9, 2.6)
	lifespan = randf_range(260.0, 380.0)
	body = MeshInstance3D.new()
	body.mesh = Assets.mesh("villager")
	add_child(body)
	bundle = MeshInstance3D.new()
	bundle.mesh = sim.bundle_mesh
	bundle.position = Vector3(0, 0.98, 0)
	bundle.visible = false
	add_child(bundle)
	position = pos
	rotation.y = randf() * TAU
	if child:
		grow = 0.5
	else:
		age = randf_range(20.0, 120.0)
	scale = Vector3.ONE * grow
	set_tribe(p_tribe)

func set_tribe(t) -> void:
	tribe = t
	Assets.apply_tribe(body, t.color)

func is_child() -> bool:
	return grow < 1.0

func tick(dt: float) -> void:
	age += dt
	if grow < 1.0:
		grow = minf(1.0, grow + dt / 40.0)
		scale = Vector3.ONE * grow
	if age > lifespan:
		sim.kill_villager(self, "old age")
		return
	if sim.terrain.height_at(position.x, position.z) < Terrain.SEA - 0.6:
		sim.kill_villager(self, "drowned")
		return
	match state:
		S.IDLE:
			_anim_idle(dt)
			idle_t -= dt
			if idle_t <= 0.0:
				_decide()
		S.TO_RES:
			if res == null or not res.alive or res.burning:
				_reset(0.2)
			elif _move_to(res.pos, dt, 0.85):
				state = S.GATHER
				timer = randf_range(1.5, 2.4)
		S.GATHER:
			_anim_work(dt)
			timer -= dt
			if timer <= 0.0:
				if res != null and res.alive:
					var got: float = sim.harvest(res)
					if got > 0.0:
						carry_type = res.type
						carry_amt = got
						bundle.visible = true
						bundle.set_surface_override_material(0, sim.carry_mats[carry_type])
				res = null
				state = S.RETURN if carry_amt > 0.0 else S.IDLE
		S.RETURN:
			if _move_to(tribe.center, dt, 1.9):
				sim.deposit(tribe, carry_type, carry_amt)
				carry_amt = 0.0
				carry_type = -1
				bundle.visible = false
				_reset(0.3)
		S.TO_BUILD:
			if bld == null or not bld.alive or bld.built:
				_reset(0.2)
			elif _move_to(bld.pos, dt, 1.5):
				state = S.BUILD
		S.BUILD:
			if bld == null or not bld.alive or bld.built:
				_reset(0.4)
			else:
				_anim_work(dt)
				_face(bld.pos, dt)
				sim.add_build_progress(bld, dt)
		S.WANDER:
			timer -= dt
			if _move_to(target, dt, 0.6) or timer <= 0.0:
				_reset(randf_range(0.5, 2.0))

func _reset(wait: float) -> void:
	state = S.IDLE
	res = null
	bld = null
	idle_t = wait
	stuck_t = 0.0

func _decide() -> void:
	if carry_amt > 0.0:
		state = S.RETURN
		return
	if is_child():
		_wander(tribe.center, 6.0)
		return
	var site = sim.pending_site(tribe)
	if site != null and sim.count_builders(site) < 3 and randf() < 0.75:
		bld = site
		state = S.TO_BUILD
		return
	if randf() < 0.08:
		_wander(position, 12.0)
		return
	var want: int = sim.wanted_resource(tribe)
	if want < 0:
		_wander(tribe.center, 9.0)
		return
	res = sim.find_nearest(position, want, 42.0)
	if res == null:
		for alt in [WorldSim.RES_BUSH, WorldSim.RES_TREE, WorldSim.RES_ROCK]:
			res = sim.find_nearest(position, alt, 42.0)
			if res != null: break
	if res != null:
		state = S.TO_RES
	else:
		_wander(position, 25.0)  # explore

func _wander(around: Vector3, radius: float) -> void:
	for i in 8:
		var a := randf() * TAU
		var p := around + Vector3(cos(a), 0, sin(a)) * randf_range(radius * 0.3, radius)
		if sim.terrain.in_bounds(p.x, p.z, 4.0) and sim.terrain.is_land(p.x, p.z):
			target = p
			state = S.WANDER
			timer = 14.0
			return
	_reset(1.0)

func _move_to(dest: Vector3, dt: float, arrive: float) -> bool:
	var to := Vector3(dest.x - position.x, 0.0, dest.z - position.z)
	var d := to.length()
	if d <= arrive:
		return true
	var dir := to / d
	var step := speed * dt * (0.75 if carry_amt > 0.0 else 1.0) * (0.7 + 0.3 * grow)
	var np := position + dir * minf(step, d)
	var h: float = sim.terrain.height_at(np.x, np.z)
	if h < Terrain.SEA + 0.1:
		var side := dir.rotated(Vector3.UP, 1.3 if (int(phase * 10.0) % 2 == 0) else -1.3)
		np = position + side * step
		h = sim.terrain.height_at(np.x, np.z)
		stuck_t += dt
		if h < Terrain.SEA + 0.1 or stuck_t > 4.0:
			if stuck_t > 4.0 or h < Terrain.SEA + 0.1:
				_reset(0.5)
				if carry_amt > 0.0:
					carry_amt = 0.0
					bundle.visible = false
			return false
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	position = Vector3(np.x, h, np.z)
	_face(position + dir, dt)
	_anim_walk(dt)
	return false

func _face(p: Vector3, dt: float) -> void:
	var dx := p.x - position.x
	var dz := p.z - position.z
	if absf(dx) + absf(dz) > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(dx, dz), minf(1.0, dt * 8.0))

func _anim_walk(dt: float) -> void:
	phase += dt * 13.0
	body.position.y = absf(sin(phase)) * 0.08
	body.rotation.z = sin(phase) * 0.12
	body.rotation.x = lerpf(body.rotation.x, 0.08, minf(1.0, dt * 8.0))

func _anim_work(dt: float) -> void:
	phase += dt * 9.0
	body.position.y = lerpf(body.position.y, 0.0, minf(1.0, dt * 10.0))
	body.rotation.x = 0.15 + sin(phase) * 0.35
	body.rotation.z = 0.0

func _anim_idle(dt: float) -> void:
	phase += dt * 2.0
	var k := minf(1.0, dt * 8.0)
	body.position.y = lerpf(body.position.y, 0.0, k)
	body.rotation.z = lerpf(body.rotation.z, 0.0, k)
	body.rotation.x = lerpf(body.rotation.x, sin(phase) * 0.04, k)
