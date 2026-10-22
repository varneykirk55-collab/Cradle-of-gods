class_name Villager
extends Node3D
## An autonomous inhabitant. Driven by WorldSim.update() (so it obeys pause /
## time speed). Utility AI: flee > worship > priest/heretic duties > build >
## hunt / gather what the tribe needs > explore. Moves with A* paths on the
## NavGrid, has an articulated body (legs, arms, head) animated by blended
## procedural poses, and carries faith / resentment for the religion system.

enum S { IDLE, TO_RES, GATHER, RETURN, TO_BUILD, BUILD, WANDER, TO_WORSHIP, WORSHIP, PREACH, TALK,
	HUNT, FLEE, CARRIED, FLYING, STUNNED, MISSION, CHEER }

const STATE_NAMES := ["idle", "fetching", "gathering", "carrying home", "going to build", "building", "wandering",
	"going to worship", "worshipping", "seeking someone", "preaching", "hunting", "fleeing", "held by the god",
	"flying through the air", "dazed", "on a mission", "celebrating"]
const CARRY_MEAT := 3
const NAME_A := ["As", "Bjor", "Ei", "Frey", "Gun", "Hal", "Ing", "Kar", "Lif", "Mag", "Ol", "Rag", "Sig", "Thor", "Ulf", "Vig", "Yr", "Ast", "Dag", "Hel"]
const NAME_B := ["a", "rid", "dis", "vald", "mund", "ny", "ar", "bjorn", "hild", "leif", "run", "stein", "ulf", "veig", "da", "ny", "gerd", "ketil"]

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
var vname := ""

# religion
var faith := 30.0
var resentment := 5.0
var heretic := false
var heresy_cause := ""
var priest := false
var last_miracle := 0.0
var other = null          # villager being preached to / persuaded
var mission_tribe = null
var worship_spot := Vector3.ZERO

# hunting / fleeing / physics
var prey = null           # Animal
var threat := Vector3.ZERO
var vel := Vector3.ZERO
var _threat_t := 0.0
var _swim := false

# navigation
var path := PackedVector3Array()
var path_i := 0
var path_goal := Vector3(INF, 0, INF)
var path_ver := -1
var blacklist := {}

# body
var rig: Node3D
var parts := {}
var bundle: MeshInstance3D
var marker: MeshInstance3D
var pose := {}
var _pose_t := {}

const JOINTS := ["leg_l", "leg_r", "arm_l", "arm_r", "arm_lz", "arm_rz", "torso", "head", "head_y", "lift", "lie", "tool"]

func setup(p_sim, p_tribe, pos: Vector3, child: bool) -> void:
	sim = p_sim
	phase = randf() * TAU
	speed = randf_range(1.9, 2.6)
	lifespan = randf_range(260.0, 380.0)
	vname = NAME_A.pick_random() + NAME_B.pick_random()
	rig = Node3D.new()
	rig.scale = Vector3.ONE * 1.35  # slightly heroic proportions so villagers read from the god camera
	add_child(rig)
	parts = Assets.build_parts("villager_rig", rig, 170.0)
	for k in ["robe", "mitre", "hood", "tool", "spear"]:
		parts[k].visible = false
	# tools ride on the right arm
	for k in ["tool", "spear"]:
		var t: MeshInstance3D = parts[k]
		var xf: Transform3D = parts["arm_r"].transform.affine_inverse() * t.transform
		rig.remove_child(t)
		parts["arm_r"].add_child(t)
		t.transform = xf
	for k in ["mitre", "hood"]:
		var t: MeshInstance3D = parts[k]
		var xf: Transform3D = parts["head"].transform.affine_inverse() * t.transform
		rig.remove_child(t)
		parts["head"].add_child(t)
		t.transform = xf
	for j in JOINTS:
		pose[j] = 0.0
		_pose_t[j] = 0.0
	bundle = MeshInstance3D.new()
	bundle.mesh = sim.bundle_mesh
	bundle.position = Vector3(0, 1.32, 0)
	bundle.visible = false
	add_child(bundle)
	marker = MeshInstance3D.new()
	marker.mesh = sim.marker_mesh
	marker.position = Vector3(0, 1.75, 0)
	marker.visible = false
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	position = pos
	rotation.y = randf() * TAU
	if child:
		grow = 0.5
	else:
		age = randf_range(20.0, 120.0)
	scale = Vector3.ONE * grow
	faith = randf_range(15.0, 45.0)
	resentment = randf_range(0.0, 12.0)
	set_tribe(p_tribe)

func set_tribe(t) -> void:
	tribe = t
	for k in ["torso", "arm_l", "arm_r"]:
		Assets.apply_tribe(parts[k], t.color)

func is_child() -> bool:
	return grow < 1.0

func is_busy_with_god() -> bool:
	return state == S.CARRIED or state == S.FLYING

func describe() -> String:
	var role := "Priest" if priest else ("Heretic" if heretic else ("Child" if is_child() else "Villager"))
	var f := "faith %d%%" % int(faith)
	if heretic: f = "rejects the god (%s)" % heresy_cause
	return "%s %s of %s\n%s, %s, age %d" % [role, vname, tribe.name, f, STATE_NAMES[state], int(age / 6.0) + 14]

func set_heretic(on: bool, cause := "") -> void:
	heretic = on
	heresy_cause = cause
	parts["hood"].visible = on
	if on and priest: set_priest(false)
	_update_marker()

func set_priest(on: bool) -> void:
	priest = on
	parts["robe"].visible = on
	parts["mitre"].visible = on
	_update_marker()

func _update_marker() -> void:
	marker.visible = sim.show_faith or heretic and sim.show_heretics
	if not marker.visible: return
	var m: Material
	if heretic: m = sim.marker_mats["heretic"]
	elif priest: m = sim.marker_mats["priest"]
	elif faith >= 60.0: m = sim.marker_mats["devout"]
	elif faith >= 30.0: m = sim.marker_mats["believer"]
	else: m = sim.marker_mats["doubter"]
	marker.material_override = m

# ------------------------------------------------------------------ main tick
func tick(dt: float) -> void:
	if sim.profile:
		var t0 := Time.get_ticks_usec()
		_tick(dt)
		sim.prof["v_" + STATE_NAMES[state]] = sim.prof.get("v_" + STATE_NAMES[state], 0) + Time.get_ticks_usec() - t0
		return
	_tick(dt)

func _tick(dt: float) -> void:
	age += dt
	if grow < 1.0:
		grow = minf(1.0, grow + dt / 40.0)
		scale = Vector3.ONE * grow
	if age > lifespan and state != S.CARRIED:
		sim.kill_villager(self, "old age")
		return
	if state == S.CARRIED:
		_pose_carried(dt)
		return
	if state == S.FLYING:
		_tick_flying(dt)
		return
	var gh: float = sim.terrain.height_at(position.x, position.z)
	if gh < Terrain.SEA - 0.6:
		sim.kill_villager(self, "drowned")
		return
	_swim = gh < Terrain.SEA + 0.05
	# threat scan
	_threat_t -= dt
	if _threat_t <= 0.0 and state != S.FLEE and state != S.STUNNED:
		_threat_t = 0.6
		var th = sim.threat_near(self)
		if th != null:
			threat = th
			state = S.FLEE
			timer = randf_range(2.5, 4.0)
			_clear_path()
	match state:
		S.IDLE:
			_set_pose_idle()
			idle_t -= dt
			if idle_t <= 0.0:
				_decide()
		S.TO_RES:
			if res == null or not res.alive or res.burning:
				_reset(0.2)
			elif _move_to(res.pos, dt, 0.85):
				state = S.GATHER
				timer = randf_range(1.5, 2.4) * sim.work_factor(tribe)
		S.GATHER:
			_set_pose_work(true)
			if res != null: _face(res.pos, dt)
			timer -= dt
			if timer <= 0.0:
				if res != null and res.alive:
					var got: float = sim.harvest(res)
					if got > 0.0:
						_pick_up(res.type, got)
				res = null
				state = S.RETURN if carry_amt > 0.0 else S.IDLE
		S.RETURN:
			if _move_to(tribe.center, dt, 1.9):
				sim.deposit(tribe, carry_type if carry_type != CARRY_MEAT else WorldSim.RES_MEAT, carry_amt)
				_drop_carry()
				_reset(0.3)
		S.TO_BUILD:
			if bld == null or not bld.alive or bld.built:
				_reset(0.2)
			elif _move_to(bld.pos, dt, sim.footprint(bld.type) + 0.6):
				state = S.BUILD
		S.BUILD:
			if bld == null or not bld.alive or bld.built:
				_reset(0.4)
			else:
				_set_pose_work(true)
				_face(bld.pos, dt)
				sim.add_build_progress(bld, dt / sim.work_factor(tribe))
		S.WANDER:
			timer -= dt
			if _move_to(target, dt, 0.6) or timer <= 0.0:
				_reset(randf_range(0.5, 2.0))
		S.TO_WORSHIP:
			if not tribe.ceremony or heretic:
				_reset(0.5)
			elif _move_to(worship_spot, dt, 0.5):
				state = S.WORSHIP
		S.WORSHIP:
			if not tribe.ceremony or heretic:
				_reset(randf_range(0.2, 1.0))
			else:
				_face(tribe.shrine_pos(), dt)
				_set_pose_worship()
				sim.religion.worship_tick(self, dt)
		S.PREACH:
			timer -= dt
			if other == null or other.dead or timer <= 0.0 or other.is_busy_with_god():
				_reset(0.5)
			elif _move_to(other.position, dt, 1.4):
				state = S.TALK
				timer = 3.0
		S.TALK:
			timer -= dt
			if other == null or other.dead:
				_reset(0.5)
			else:
				_face(other.position, dt)
				_set_pose_preach()
				if timer <= 0.0:
					sim.religion.preach(self, other)
					_reset(randf_range(1.0, 3.0))
		S.MISSION:
			timer -= dt
			if mission_tribe == null or not mission_tribe.alive or timer <= 0.0:
				mission_tribe = null
				_reset(0.5)
			elif _move_to(mission_tribe.center, dt, 4.0):
				sim.religion.mission_arrive(self, mission_tribe)
				mission_tribe = null
				_reset(1.0)
		S.HUNT:
			timer -= dt
			if prey == null or prey.dead or timer <= 0.0 or prey.is_busy_with_god():
				parts["spear"].visible = false
				prey = null
				_reset(0.5)
			else:
				var d: float = Vector2(prey.position.x - position.x, prey.position.z - position.z).length()
				if d < 4.5:
					_face(prey.position, dt)
					_set_pose_throw()
					stuck_t += dt
					if stuck_t > 0.6:
						stuck_t = 0.0
						var meat: float = sim.eco.try_hunt(self, prey)
						if meat > 0.0:
							parts["spear"].visible = false
							prey = null
							_pick_up(CARRY_MEAT, meat)
							state = S.RETURN
				else:
					if path_goal.distance_to(prey.position) > 3.0: _clear_path()
					_move_to(prey.position, dt, 3.5, 1.15)
		S.FLEE:
			timer -= dt
			var away := Vector3(position.x - threat.x, 0, position.z - threat.z)
			if away.length() < 0.01: away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			var dest := position + away.normalized() * 6.0
			_step_free(dest, dt, 1.6)
			_set_pose_panic()
			if timer <= 0.0:
				_reset(0.5)
		S.CHEER:
			timer -= dt
			_face(threat, dt)
			_set_pose_cheer()
			if timer <= 0.0:
				_reset(0.2)
		S.STUNNED:
			timer -= dt
			_target_pose({"lie": -1.45, "lift": 0.05, "arm_lz": 1.2, "arm_rz": -1.2, "leg_l": -0.2, "leg_r": 0.2})
			if timer <= 0.0:
				_reset(0.3)
	_apply_pose(dt)

func _pick_up(type: int, amt: float) -> void:
	carry_type = type
	carry_amt = amt
	parts["tool"].visible = false
	bundle.visible = true
	bundle.set_surface_override_material(0, sim.carry_mats[type])

func _drop_carry() -> void:
	carry_amt = 0.0
	carry_type = -1
	bundle.visible = false

func _reset(wait: float) -> void:
	state = S.IDLE
	res = null
	bld = null
	other = null
	idle_t = wait
	stuck_t = 0.0
	parts["tool"].visible = false
	parts["spear"].visible = false
	_clear_path()

# ------------------------------------------------------------------ decisions
func _decide() -> void:
	var t0 := Time.get_ticks_usec() if sim.profile else 0
	_decide_inner()
	if sim.profile: sim.prof["decide"] = sim.prof.get("decide", 0) + Time.get_ticks_usec() - t0

func _decide_inner() -> void:
	if carry_amt > 0.0:
		state = S.RETURN
		return
	if not sim.nav.connected(position, tribe.center):
		if sim.handle_stranded(self): return
	if is_child():
		_wander(tribe.center, 6.0)
		return
	var rel = sim.religion
	if tribe.ceremony and not heretic and faith >= rel.WORSHIP_MIN and tribe.has_shrine():
		worship_spot = rel.worship_spot(tribe, self)
		state = S.TO_WORSHIP
		return
	if priest:
		if rel.priest_duty(self): return
	elif heretic and randf() < 0.22:
		if rel.heretic_duty(self): return
	var site = sim.pending_site(tribe)
	if site != null and sim.count_builders(site) < (4 if site.type == "temple" else 3) and randf() < 0.75 and not (heretic and site.type in ["shrine", "temple"]):
		bld = site
		state = S.TO_BUILD
		return
	if randf() < 0.06:
		_wander(position, 12.0)
		return
	var want: int = sim.wanted_resource(tribe)
	if want == WorldSim.RES_BUSH and randf() < 0.4:
		var a = sim.eco.find_prey(position, 32.0, self)
		if a != null:
			prey = a
			state = S.HUNT
			timer = 30.0
			parts["spear"].visible = true
			return
	if want < 0:
		_wander(tribe.center, 9.0)
		return
	res = sim.find_nearest(position, want, 42.0, self)
	if res == null:
		for alt in [WorldSim.RES_BUSH, WorldSim.RES_TREE, WorldSim.RES_ROCK]:
			res = sim.find_nearest(position, alt, 42.0, self)
			if res != null: break
	if res != null:
		state = S.TO_RES
		parts["tool"].visible = true
	else:
		_wander(position, 25.0)  # explore

func can_reach(p: Vector3) -> bool:
	return sim.nav.connected(position, p)

func _wander(around: Vector3, radius: float) -> void:
	for i in 8:
		var a := randf() * TAU
		var p := around + Vector3(cos(a), 0, sin(a)) * randf_range(radius * 0.3, radius)
		if sim.terrain.in_bounds(p.x, p.z, 4.0) and sim.nav.walkable(p) and can_reach(p):
			target = p
			state = S.WANDER
			timer = 14.0
			return
	_reset(1.0)

## Called by the God Hand / physics.
func grab() -> void:
	_reset(0.0)
	state = S.CARRIED
	if carry_amt > 0.0: _drop_carry()

func throw(v: Vector3) -> void:
	state = S.FLYING
	vel = v

func _tick_flying(dt: float) -> void:
	vel.y -= 22.0 * dt
	var np := position + vel * dt
	var gh: float = sim.terrain.height_at(np.x, np.z)
	_target_pose({"lie": clampf(-vel.length() * 0.06, -1.2, 0.0), "arm_l": -2.6, "arm_r": -2.3, "leg_l": sin(phase * 3.0) * 0.8, "leg_r": -sin(phase * 3.0) * 0.8})
	phase += dt * 8.0
	rotation.y += dt * minf(vel.length(), 20.0) * 0.15
	_apply_pose(dt)
	if not sim.terrain.in_bounds(np.x, np.z, 1.0):
		np.x = clampf(np.x, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
		np.z = clampf(np.z, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
		vel.x = 0.0
		vel.z = 0.0
	if np.y <= maxf(gh, Terrain.SEA - 0.3):
		position = Vector3(np.x, maxf(gh, Terrain.SEA - 0.3), np.z)
		sim.on_villager_landed(self, vel)
		return
	position = np

# ------------------------------------------------------------------ movement
func _clear_path() -> void:
	path = PackedVector3Array()
	path_i = 0
	path_goal = Vector3(INF, 0, INF)

func _give_up() -> void:
	if res != null:
		blacklist[res] = sim.time + 40.0
	_reset(randf_range(0.5, 1.5))

## Walks toward dest along an A* path (straight when the line is clear).
## Returns true on arrival. Gives up (resets) when dest proves unreachable.
func _move_to(dest: Vector3, dt: float, arrive: float, speed_mul := 1.0) -> bool:
	var flat := Vector2(dest.x - position.x, dest.z - position.z)
	if flat.length() <= arrive:
		_clear_path()
		return true
	if _swim:
		_step_free(dest, dt, 0.6 * speed_mul)
		return false
	if Vector2(path_goal.x - dest.x, path_goal.z - dest.z).length() > 1.5 or (path_ver != sim.terrain.version and stuck_t > 0.4):
		if not _plan(dest):
			return false
	var wp := dest if path_i >= path.size() else path[path_i]
	var to := Vector2(wp.x - position.x, wp.z - position.z)
	if to.length() < 0.6 and path_i < path.size():
		path_i += 1
		wp = dest if path_i >= path.size() else path[path_i]
		to = Vector2(wp.x - position.x, wp.z - position.z)
		if path_i >= path.size() and Vector2(wp.x - dest.x, wp.z - dest.z).length() > arrive + 2.5 and path.size() > 0:
			pass
	if path_i >= path.size() and path.size() > 0:
		var last := path[path.size() - 1]
		if Vector2(last.x - dest.x, last.z - dest.z).length() > arrive + 2.5 and to.length() < 1.0:
			_give_up()   # partial path ended short of the goal
			return false
	if to.length() < 0.001:
		return false
	var dir := Vector3(to.x, 0, to.y).normalized()
	var mul := (0.75 if carry_amt > 0.0 else 1.0) * (0.7 + 0.3 * grow) * speed_mul
	var step := speed * dt * mul
	var np := position + dir * minf(step, to.length())
	if not sim.nav.walkable(np):
		stuck_t += dt
		if stuck_t > 0.5 and stuck_t - dt <= 0.5:
			_plan(dest)
		if stuck_t > 5.0:
			_give_up()
		# slide sideways to get unstuck
		var side := dir.rotated(Vector3.UP, 1.3 if (int(phase * 10.0) % 2 == 0) else -1.3)
		np = position + side * step * 0.6
		if not sim.nav.walkable(np): return false
	else:
		stuck_t = maxf(0.0, stuck_t - dt * 0.5)
	position = Vector3(np.x, sim.terrain.height_at(np.x, np.z), np.z)
	_face(position + dir, dt)
	_set_pose_walk(dt, mul)
	return false

func _plan(dest: Vector3) -> bool:
	path_goal = dest
	path_ver = sim.terrain.version
	path_i = 0
	if sim.nav.line_clear(position, dest):
		path = PackedVector3Array()
		return true
	if not sim.nav.can_path():
		path_goal = Vector3(INF, 0, INF)   # try again next tick
		_set_pose_idle()
		return false
	path = sim.nav.find_path(position, dest)
	if path.is_empty():
		_give_up()
		return false
	path_i = 1 if path.size() > 1 else 0
	return true

## Steering without the grid (fleeing, swimming ashore). Avoids deep water.
func _step_free(dest: Vector3, dt: float, mul: float) -> void:
	var to := Vector3(dest.x - position.x, 0, dest.z - position.z)
	if to.length() < 0.05: return
	var dir := to.normalized()
	if _swim:
		var shore = sim.nav.nearest_walkable(position, 8)
		if shore != null:
			dir = Vector3(shore.x - position.x, 0, shore.z - position.z).normalized()
	var step := speed * dt * mul
	for ang in [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
		var d2 := dir.rotated(Vector3.UP, ang)
		var np := position + d2 * step
		if not sim.terrain.in_bounds(np.x, np.z, 3.0): continue
		if _swim or sim.nav.walkable(np):
			position = Vector3(np.x, maxf(sim.terrain.height_at(np.x, np.z), Terrain.SEA - 0.25), np.z)
			_face(position + d2, dt)
			_set_pose_walk(dt, mul)
			return

func _face(p: Vector3, dt: float) -> void:
	var dx := p.x - position.x
	var dz := p.z - position.z
	if absf(dx) + absf(dz) > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(dx, dz), minf(1.0, dt * 8.0))

# ------------------------------------------------------------------ animation
## Joint conventions: leg/arm x < 0 swings forward; arm_*z raises sideways;
## torso/head x > 0 bows forward; lift moves the whole body up; lie tips it over.
func _target_pose(p: Dictionary) -> void:
	for j in JOINTS:
		_pose_t[j] = p.get(j, 0.0)

func _set_pose_walk(dt: float, mul: float) -> void:
	phase += dt * 11.0 * clampf(mul, 0.6, 1.8)
	var s := sin(phase)
	var carry := carry_amt > 0.0
	_target_pose({"leg_l": s * 0.65, "leg_r": -s * 0.65,
		"arm_l": -2.7 if carry else -s * 0.55, "arm_r": -2.7 if carry else s * 0.55,
		"arm_lz": 0.25 if carry else 0.0, "arm_rz": -0.25 if carry else 0.0,
		"torso": 0.08 + (0.1 if mul > 1.3 else 0.0), "lift": absf(cos(phase)) * 0.05, "head_y": 0.0})

func _set_pose_idle() -> void:
	phase += 0.04
	_target_pose({"torso": sin(phase) * 0.03, "head_y": sin(phase * 0.37) * 0.5, "head": 0.05,
		"arm_l": -2.7 if carry_amt > 0.0 else 0.05, "arm_r": -2.7 if carry_amt > 0.0 else 0.05})

func _set_pose_work(with_tool: bool) -> void:
	phase += 0.16
	var s := sin(phase)
	parts["tool"].visible = with_tool
	_target_pose({"arm_r": -1.4 - s * 0.9, "arm_l": -0.9 - s * 0.4, "torso": 0.25 + s * 0.15, "head": 0.15,
		"leg_l": -0.25, "leg_r": 0.2, "lift": -0.02})

func _set_pose_worship() -> void:
	phase += 0.05
	var s := sin(phase)
	var up := s > 0.0
	_target_pose({"leg_l": -1.35, "leg_r": -1.35, "lift": -0.17, "torso": 0.55 if not up else 0.05,
		"arm_l": -2.9 if up else -0.6, "arm_r": -2.9 if up else -0.6, "arm_lz": 0.35 if up else 0.0,
		"arm_rz": -0.35 if up else 0.0, "head": 0.5 if not up else -0.35})

func _set_pose_preach() -> void:
	phase += 0.12
	var s := sin(phase)
	_target_pose({"arm_r": -1.6 + s * 0.5, "arm_l": -0.4, "arm_rz": -0.3, "head": -0.05 + s * 0.05, "torso": 0.05})

func _set_pose_throw() -> void:
	phase += 0.2
	_target_pose({"arm_r": -2.6 + sin(phase) * 0.9, "arm_l": -1.0, "torso": 0.15, "leg_l": -0.4, "leg_r": 0.35})

func _set_pose_cheer() -> void:
	phase += 0.22
	var j := absf(sin(phase))
	_target_pose({"arm_l": -2.9 + sin(phase) * 0.25, "arm_r": -2.9 - sin(phase) * 0.25, "arm_lz": 0.45, "arm_rz": -0.45,
		"lift": j * 0.18, "leg_l": -j * 0.4, "leg_r": -j * 0.4, "head": -0.3})

## Visible reaction to a divine act seen nearby.
func react(kind: String, at: Vector3) -> void:
	if state in [S.CARRIED, S.FLYING, S.STUNNED, S.WORSHIP, S.TALK] or carry_amt > 0.0: return
	threat = at
	if kind == "harm":
		_reset(0.0)
		state = S.FLEE
		timer = randf_range(2.0, 3.5)
	elif not heretic:
		_reset(0.0)
		state = S.CHEER
		timer = randf_range(1.8, 3.0)

func _set_pose_panic() -> void:
	_pose_t["arm_l"] = -2.8 + sin(phase * 1.3) * 0.3
	_pose_t["arm_r"] = -2.8 - sin(phase * 1.3) * 0.3
	_pose_t["arm_lz"] = 0.5
	_pose_t["arm_rz"] = -0.5
	_pose_t["head"] = -0.2

func _pose_carried(dt: float) -> void:
	phase += dt * 9.0
	var s := sin(phase)
	_target_pose({"leg_l": s * 0.9, "leg_r": -s * 0.9, "arm_l": -2.6 + s * 0.6, "arm_r": -2.6 - s * 0.6,
		"arm_lz": 0.6, "arm_rz": -0.6, "head": -0.3, "torso": -0.1})
	_apply_pose(dt)

var _lod_n := 0

func _apply_pose(dt: float) -> void:
	if sim.profile:
		var t0 := Time.get_ticks_usec()
		_apply_pose_inner(dt)
		sim.prof["pose"] = sim.prof.get("pose", 0) + Time.get_ticks_usec() - t0
		return
	_apply_pose_inner(dt)

## Animation LOD: off-screen or far from the camera, poses update every 6th step.
func _apply_pose_inner(dt: float) -> void:
	_lod_n += 1
	if _lod_n % 6 != 0 and not _on_screen():
		return
	if _lod_n % 6 == 0 and not _on_screen(): dt *= 6.0
	var k := 1.0 - exp(-dt * 12.0)
	for j in JOINTS:
		pose[j] = lerpf(pose[j], _pose_t[j], k)
	if _n_leg_l == null:
		_n_leg_l = parts["leg_l"]; _n_leg_r = parts["leg_r"]; _n_arm_l = parts["arm_l"]
		_n_arm_r = parts["arm_r"]; _n_torso = parts["torso"]; _n_head = parts["head"]; _n_robe = parts["robe"]
	var tor: float = pose["torso"]
	_n_leg_l.basis = Basis(Vector3.RIGHT, pose["leg_l"])
	_n_leg_r.basis = Basis(Vector3.RIGHT, pose["leg_r"])
	_n_arm_l.basis = Basis.from_euler(Vector3(pose["arm_l"], 0, pose["arm_lz"]))
	_n_arm_r.basis = Basis.from_euler(Vector3(pose["arm_r"], 0, pose["arm_rz"]))
	_n_torso.basis = Basis(Vector3.RIGHT, tor)
	if priest: _n_robe.basis = Basis(Vector3.RIGHT, tor * 0.5)
	_n_head.basis = Basis.from_euler(Vector3(pose["head"] + tor * 0.6, pose["head_y"], 0))
	rig.position = Vector3(0, pose["lift"], 0)
	rig.rotation.x = pose["lie"]

var _n_leg_l: Node3D
var _n_leg_r: Node3D
var _n_arm_l: Node3D
var _n_arm_r: Node3D
var _n_torso: Node3D
var _n_head: Node3D
var _n_robe: Node3D

func _on_screen() -> bool:
	var c: Camera3D = sim.cam
	if c == null: return true
	if position.distance_squared_to(sim.cam_pos) > 120.0 * 120.0: return false
	return c.is_position_in_frustum(position)

func _rot(n: Node3D, e: Vector3) -> void:
	n.basis = Basis.from_euler(e)
