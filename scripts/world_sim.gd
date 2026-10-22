class_name WorldSim
extends Node3D
## The living world: resources (trees, rocks, bushes), tribes, buildings,
## villagers, fire, growth, plus the navigation grid, the religion system and
## the wildlife ecosystem. Everything advances only through update(dt) so the
## time-speed control (pause/1x/2x/4x) affects the whole simulation.

signal event_logged(text: String, color: Color)

const RES_TREE := 0
const RES_ROCK := 1
const RES_BUSH := 2
const RES_MEAT := 3
const BUCKET := 8.0
const MAX_TRIBES := 10
const MAX_POP := 320
const HOUSING := {"hall": 4, "hut": 3, "house": 6, "shrine": 0, "temple": 0}
const MODEL := {"hall": ["townhall"], "hut": ["hut", "hut_b"], "house": ["house", "house_b"], "shrine": ["shrine"], "temple": ["temple"]}
const BUILD_WORK := {"hall": 10.0, "hut": 7.0, "house": 12.0, "shrine": 9.0, "temple": 20.0}
const FOOTPRINT := {"hall": 2.0, "hut": 1.1, "house": 1.4, "shrine": 1.2, "temple": 2.6}
const TRIBE_NAMES := ["Ravnfolk", "Ulfheim", "Skaldir", "Eikvald", "Solbrand", "Myrvik", "Hrafnir", "Isgard", "Bjarkan", "Torvik"]
const TRIBE_COLORS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.9), Color(0.95, 0.8, 0.2), Color(0.6, 0.3, 0.85),
	Color(0.95, 0.5, 0.15), Color(0.15, 0.75, 0.7), Color(0.9, 0.4, 0.65), Color(0.95, 0.95, 0.95)]

class Res:
	var type := 0
	var kind := ""
	var pos := Vector3.ZERO
	var amount := 0.0
	var slot := -1
	var alive := true
	var scale := 1.0
	var target_scale := 1.0
	var yaw := 0.0
	var burning := false
	var bkey := Vector2i.ZERO

class Tribe:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var center := Vector3.ZERO
	var wood := 0.0
	var stone := 0.0
	var food := 0.0
	var members: Array = []
	var buildings: Array = []
	var alive := true
	var blessed := 0.0
	var births := 0
	var ai_timer := 0.0
	var birth_timer := 4.0
	var eat_timer := 12.0
	var stage := "Camp"
	# religion
	var shrine = null          # Building (shrine or temple)
	var heretical := false
	var devotion := 30.0
	var tension := 0.0
	var worshippers := 0
	var heretics := 0
	var ceremony := false
	var ceremony_t := 0.0
	var next_ceremony := 30.0
	var inspired := 0.0
	var last_miracle := 0.0
	var mission_t := 60.0
	var mission_target = null
	var starving := false

	func has_shrine() -> bool:
		return shrine != null and shrine.alive and shrine.built

	func has_temple() -> bool:
		return has_shrine() and shrine.type == "temple"

	func shrine_pos() -> Vector3:
		return shrine.pos if shrine != null else center

class Building:
	var type := "hut"
	var tribe: Tribe
	var pos := Vector3.ZERO
	var node: MeshInstance3D
	var work := 0.0
	var built := false
	var burning := false
	var alive := true

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var pools := {}
var buckets := {}
var resources: Array = []
var growing: Array = []
var tribes: Array = []
var villagers: Array = []
var fires: Array = []
var time := 0.0
var stats := {"births": 0, "deaths": 0, "built": 0, "destroyed": 0, "trees_felled": 0}
var bundle_mesh := BoxMesh.new()
var carry_mats := {}
var _spread_t := 0.0
var _next_tribe := 0
var _stump_free: Array = []
var nav := NavGrid.new()
var religion := Religion.new()
var eco: Ecosystem
var props: Array = []          # trees / rocks thrown or dropped by the God Hand
var marker_mesh := SphereMesh.new()
var marker_mats := {}
var show_faith := false
var show_heretics := true

func setup(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	rng.seed = p_seed
	seed(p_seed)
	terrain.terrain_changed.connect(_on_terrain_changed)
	bundle_mesh.size = Vector3(0.22, 0.16, 0.22)
	for t in [RES_TREE, RES_ROCK, RES_BUSH]:
		var m := StandardMaterial3D.new()
		m.albedo_color = [Color(0.55, 0.36, 0.2), Color(0.6, 0.6, 0.62), Color(0.85, 0.2, 0.3)][t]
		carry_mats[t] = m
	_make_pool("tree_pine", 1800)
	_make_pool("tree_oak", 1800)
	_make_pool("rock", 500)
	_make_pool("bush", 700)
	_make_pool("stump", 400)
	marker_mesh.radius = 0.11
	marker_mesh.height = 0.22
	marker_mesh.radial_segments = 8
	marker_mesh.rings = 4
	for k in ["heretic", "priest", "devout", "believer", "doubter"]:
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = {"heretic": Color(0.7, 0.25, 1.0), "priest": Color(1.0, 1.0, 1.0), "devout": Color(1.0, 0.82, 0.2),
			"believer": Color(0.95, 0.9, 0.6), "doubter": Color(0.55, 0.55, 0.6)}[k]
		marker_mats[k] = mm
	var meat_m := StandardMaterial3D.new()
	meat_m.albedo_color = Color(0.7, 0.25, 0.22)
	carry_mats[RES_MEAT] = meat_m
	nav.setup(terrain)
	religion.setup(self)
	_populate_nature()
	for i in 3:
		var spot = find_settle_spot(40.0)
		if spot != null:
			var t := create_tribe(spot, true)
			for j in 6:
				spawn_villager(t, spot + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), false)
			t.food = 12.0
			t.wood = 6.0
	eco = Ecosystem.new()
	eco.name = "Ecosystem"
	add_child(eco)
	eco.setup(self)

# ------------------------------------------------------------------ pools
func _make_pool(kind: String, cap: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Assets.mesh(kind)
	mm.instance_count = cap
	var hidden := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -200, 0))
	for i in cap:
		mm.set_instance_transform(i, hidden)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Pool_" + kind
	mmi.multimesh = mm
	add_child(mmi)
	var free: Array = []
	for i in range(cap - 1, -1, -1):
		free.append(i)
	pools[kind] = {"mm": mm, "free": free}

func _alloc(kind: String) -> int:
	var f: Array = pools[kind]["free"]
	return f.pop_back() if not f.is_empty() else -1

func _release(kind: String, slot: int) -> void:
	var mm: MultiMesh = pools[kind]["mm"]
	mm.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -200, 0)))
	pools[kind]["free"].append(slot)

func _update_res_xform(r: Res) -> void:
	var mm: MultiMesh = pools[r.kind]["mm"]
	var s := maxf(r.scale, 0.0001)
	mm.set_instance_transform(r.slot, Transform3D(Basis(Vector3.UP, r.yaw).scaled(Vector3.ONE * s), r.pos))

# ------------------------------------------------------------------ resources
func _bkey(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / BUCKET)), int(floor(p.z / BUCKET)))

func add_resource(type: int, pos: Vector3, grow_in := false, kind := "") -> Res:
	if kind == "":
		match type:
			RES_TREE:
				kind = "tree_pine" if (pos.y > 6.0 or terrain.moisture_at(pos.x, pos.z) > 0.72 or rng.randf() < 0.25) else "tree_oak"
			RES_ROCK: kind = "rock"
			_: kind = "bush"
	var slot := _alloc(kind)
	if slot < 0:
		return null
	var r := Res.new()
	r.type = type
	r.kind = kind
	r.pos = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	r.slot = slot
	r.yaw = rng.randf() * TAU
	r.amount = [6.0, 12.0, 5.0][type]
	r.target_scale = rng.randf_range(0.8, 1.25) if type != RES_ROCK else rng.randf_range(0.6, 1.6)
	r.scale = 0.05 if grow_in else r.target_scale
	r.bkey = _bkey(r.pos)
	if not buckets.has(r.bkey):
		buckets[r.bkey] = []
	buckets[r.bkey].append(r)
	resources.append(r)
	if grow_in:
		growing.append(r)
	_update_res_xform(r)
	return r

func remove_resource(r: Res, leave_stump := false) -> void:
	if not r.alive: return
	r.alive = false
	_release(r.kind, r.slot)
	var arr: Array = buckets.get(r.bkey, [])
	arr.erase(r)
	resources.erase(r)
	growing.erase(r)
	if leave_stump and r.type == RES_TREE:
		var s := _alloc("stump")
		if s >= 0:
			var mm: MultiMesh = pools["stump"]["mm"]
			mm.set_instance_transform(s, Transform3D(Basis(Vector3.UP, r.yaw).scaled(Vector3.ONE * r.scale), r.pos))
			_stump_free.append({"slot": s, "t": 60.0})

func count_type(type: int) -> int:
	var c := 0
	for r in resources:
		if r.type == type: c += 1
	return c

func find_nearest(pos: Vector3, type: int, max_r: float, who = null) -> Res:
	var best: Res = null
	var bd := max_r * max_r
	var bc := _bkey(pos)
	var rr := int(ceil(max_r / BUCKET))
	for dz in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var arr = buckets.get(Vector2i(bc.x + dx, bc.y + dz))
			if arr == null: continue
			for r in arr:
				if r.type != type or r.burning or r.scale < r.target_scale * 0.7: continue
				var d: float = r.pos.distance_squared_to(pos)
				if d >= bd: continue
				if who != null:
					if who.blacklist.has(r) and who.blacklist[r] > time: continue
					if not nav.connected(pos, r.pos): continue
				bd = d
				best = r
	return best

func resources_in_radius(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var bc := _bkey(pos)
	var rr := int(ceil(radius / BUCKET))
	for dz in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var arr = buckets.get(Vector2i(bc.x + dx, bc.y + dz))
			if arr == null: continue
			for r in arr:
				if Vector2(r.pos.x - pos.x, r.pos.z - pos.z).length() <= radius:
					out.append(r)
	return out

func harvest(r: Res, amount := -1.0) -> float:
	if not r.alive: return 0.0
	var take := minf(r.amount, [3.0, 2.0, 2.0][r.type] if amount < 0.0 else amount)
	r.amount -= take
	if r.amount <= 0.01:
		if r.type == RES_TREE: stats["trees_felled"] += 1
		remove_resource(r, true)
	return take

func can_grow_tree(p: Vector3) -> bool:
	if not terrain.in_bounds(p.x, p.z, 1.5): return false
	var b := terrain.biome_at(p.x, p.z)
	return b in [Terrain.Biome.GRASS, Terrain.Biome.FOREST, Terrain.Biome.ALPINE, Terrain.Biome.DRY] and terrain.fertility_at(p.x, p.z) > -0.3

func _populate_nature() -> void:
	var dn := FastNoiseLite.new()
	dn.seed = terrain.seed_value + 99
	dn.frequency = 0.045
	for i in 9000:
		var p := Vector3(rng.randf_range(-78, 78), 0, rng.randf_range(-78, 78))
		if not terrain.is_land(p.x, p.z): continue
		var b := terrain.biome_at(p.x, p.z)
		var clump := dn.get_noise_2d(p.x, p.z) * 0.5 + 0.5
		var chance := 0.0
		match b:
			Terrain.Biome.FOREST: chance = 0.25 + clump * 0.55
			Terrain.Biome.GRASS: chance = clump * 0.22
			Terrain.Biome.ALPINE: chance = 0.08 + clump * 0.25
			Terrain.Biome.DRY: chance = clump * 0.05
		if rng.randf() < chance:
			add_resource(RES_TREE, p)
		elif b in [Terrain.Biome.GRASS, Terrain.Biome.FOREST] and rng.randf() < 0.035:
			add_resource(RES_BUSH, p)
		elif b in [Terrain.Biome.ROCK, Terrain.Biome.ALPINE] and rng.randf() < 0.08:
			add_resource(RES_ROCK, p)
		elif b in [Terrain.Biome.GRASS, Terrain.Biome.DRY, Terrain.Biome.BEACH] and rng.randf() < 0.012:
			add_resource(RES_ROCK, p)

# ------------------------------------------------------------------ tribes
func find_settle_spot(min_dist: float, near = null, near_r := 60.0) -> Variant:
	for i in 400:
		var p: Vector3
		if near != null:
			var a := rng.randf() * TAU
			p = near + Vector3(cos(a), 0, sin(a)) * rng.randf_range(min_dist, near_r)
		else:
			p = Vector3(rng.randf_range(-Terrain.HALF + 12, Terrain.HALF - 12), 0, rng.randf_range(-Terrain.HALF + 12, Terrain.HALF - 12))
		if not terrain.in_bounds(p.x, p.z, 10.0): continue
		if not nav.walkable(p): continue
		var b := terrain.biome_at(p.x, p.z)
		if not (b in [Terrain.Biome.GRASS, Terrain.Biome.DRY, Terrain.Biome.FOREST]): continue
		if terrain.slope_at(p.x, p.z) > 0.5: continue
		var ok := true
		for t in tribes:
			if t.alive and t.center.distance_to(p) < min_dist:
				ok = false
				break
		if ok:
			p.y = terrain.height_at(p.x, p.z)
			return p
	return null

func create_tribe(center: Vector3, prebuilt := false) -> Tribe:
	var t := Tribe.new()
	t.id = _next_tribe
	t.name = TRIBE_NAMES[_next_tribe % TRIBE_NAMES.size()]
	t.color = TRIBE_COLORS[_next_tribe % TRIBE_COLORS.size()]
	_next_tribe += 1
	t.center = center
	t.ai_timer = rng.randf()
	tribes.append(t)
	for r in resources_in_radius(center, 3.0):
		remove_resource(r)
	t.last_miracle = time
	t.next_ceremony = rng.randf_range(20.0, 40.0)
	var hall := place_building(t, "hall", center)
	if prebuilt:
		hall.work = BUILD_WORK["hall"]
		_finish_building(hall, false)
	log_event("The %s tribe has settled." % t.name, t.color)
	return t

func nearest_tribe(pos: Vector3, max_d: float) -> Tribe:
	var best: Tribe = null
	var bd := max_d
	for t in tribes:
		if not t.alive: continue
		var d: float = t.center.distance_to(pos)
		if d < bd:
			bd = d
			best = t
	return best

func housing(t: Tribe) -> int:
	var h := 0
	for b in t.buildings:
		if b.built: h += HOUSING[b.type]
	return h

func pending_site(t: Tribe) -> Building:
	for b in t.buildings:
		if not b.built and b.alive: return b
	return null

func count_builders(b: Building) -> int:
	var c := 0
	for v in b.tribe.members:
		if v.bld == b: c += 1
	return c

func footprint(type: String) -> float:
	return FOOTPRINT[type]

## Work time multiplier: inspired tribes (after worship) work faster, religious
## tension slows everything down.
func work_factor(t: Tribe) -> float:
	var f := 1.0 + t.tension * 0.7
	if t.inspired > 0.0: f *= 0.8
	if t.devotion > 70.0: f *= 0.9
	return f

func wanted_resource(t: Tribe) -> int:
	var pop: int = t.members.size()
	if t.food < pop * 1.5 + 4.0: return RES_BUSH
	if t.wood < 18.0 + pop: return RES_TREE
	if t.stone < 12.0 and _has_built(t, "hut"): return RES_ROCK
	var opts: Array = []
	if t.food < 30.0 + pop * 3.0: opts.append_array([RES_BUSH, RES_BUSH])
	if t.wood < 40.0 + pop * 2.0: opts.append(RES_TREE)
	if t.stone < 30.0 + pop: opts.append(RES_ROCK)
	if opts.is_empty(): return -1  # stores are full: rest / stroll
	return opts[rng.randi() % opts.size()]

func _has_built(t: Tribe, type: String) -> bool:
	for b in t.buildings:
		if b.built and b.type == type: return true
	return false

func deposit(t: Tribe, type: int, amt: float) -> void:
	if not t.alive: return
	stats["deposits"] = stats.get("deposits", 0) + 1
	match type:
		RES_TREE: t.wood += amt
		RES_ROCK: t.stone += amt
		RES_BUSH: t.food += amt * 1.5
		RES_MEAT: t.food += amt

func place_building(t: Tribe, type: String, pos: Vector3) -> Building:
	var b := Building.new()
	b.type = type
	b.tribe = t
	b.pos = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh(MODEL[type].pick_random())
	add_child(mi)
	mi.position = b.pos
	# face the hall (doors are on the model's front) so streets look planned
	if type == "hall":
		mi.rotation.y = rng.randf_range(-0.3, 0.3)
	else:
		var to := t.center - b.pos
		mi.rotation.y = atan2(to.x, to.z) + rng.randf_range(-0.25, 0.25) if to.length() > 0.5 else rng.randf() * TAU
	mi.scale = Vector3(1, 0.08, 1)
	Assets.apply_tribe(mi, t.color)
	b.node = mi
	t.buildings.append(b)
	for r in resources_in_radius(b.pos, FOOTPRINT[type] + 0.8):
		remove_resource(r)
	if type in ["shrine", "temple"]:
		t.shrine = b
	nav.set_footprint(b.pos, FOOTPRINT[type], true)
	return b

func add_build_progress(b: Building, dt: float) -> void:
	if b.built or not b.alive: return
	b.work += dt
	var p := clampf(b.work / BUILD_WORK[b.type], 0.0, 1.0)
	b.node.scale = Vector3(lerpf(0.85, 1.0, p), lerpf(0.08, 0.9, p), lerpf(0.85, 1.0, p))
	if p >= 1.0:
		_finish_building(b, true)

func _finish_building(b: Building, announce: bool) -> void:
	b.built = true
	stats["built"] += 1
	var tw := create_tween()
	tw.tween_property(b.node, "scale", Vector3(1.08, 1.12, 1.08), 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_property(b.node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	if announce:
		FX.dust(self, b.pos)
		if b.type == "house":
			log_event("%s raised a stone house." % b.tribe.name, b.tribe.color)
		elif b.type == "shrine":
			log_event("%s built a shrine to the god!" % b.tribe.name, Color(1.0, 0.9, 0.55))
			FX.sparkle(self, b.pos + Vector3(0, 1.5, 0), Color(1.0, 0.9, 0.5), 40, 1.5)
		elif b.type == "temple":
			log_event("%s raised a great temple!" % b.tribe.name, Color(1.0, 0.9, 0.55))
			FX.sparkle(self, b.pos + Vector3(0, 2.5, 0), Color(1.0, 0.9, 0.5), 60, 2.5)

func destroy_building(b: Building, cause := "") -> void:
	if not b.alive: return
	b.alive = false
	b.tribe.buildings.erase(b)
	nav.set_footprint(b.pos, FOOTPRINT[b.type], false)
	stats["destroyed"] += 1
	if b.tribe.shrine == b:
		b.tribe.shrine = null
		b.tribe.ceremony = false
		if b.tribe.alive and b.built:
			log_event("The %s %s was destroyed%s!" % [b.tribe.name, b.type, cause], Color(1, 0.5, 0.3))
			religion.on_hardship(b.tribe, "our holy place was destroyed", 10.0)
	FX.debris(self, b.pos, Color(0.45, 0.32, 0.2), 14, 6.0)
	var n := b.node
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1.2, 0.01, 1.2), 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(n.queue_free)
	if b.type == "hall" and b.tribe.alive:
		log_event("The %s great hall was destroyed%s!" % [b.tribe.name, cause], Color(1, 0.5, 0.3))

func _tribe_ai(t: Tribe, dt: float) -> void:
	var pop: int = t.members.size()
	if pop == 0:
		t.alive = false
		log_event("The %s tribe has perished." % t.name, Color(0.7, 0.7, 0.7))
		for b in t.buildings.duplicate():
			destroy_building(b)
		return
	var cap := housing(t)
	# civilisation stage
	var houses := 0
	for b in t.buildings:
		if b.built and b.type == "house": houses += 1
	var new_stage := "Camp"
	if pop >= 16 and houses >= 3: new_stage = "Town"
	elif pop >= 8 or houses >= 1: new_stage = "Village"
	if new_stage != t.stage:
		if new_stage != "Camp": log_event("%s has grown into a %s!" % [t.name, new_stage], t.color)
		t.stage = new_stage
	# hall missing → rebuild at centre
	var has_hall := false
	for b in t.buildings:
		if b.type == "hall": has_hall = true
	if pending_site(t) == null:
		if not has_hall:
			place_building(t, "hall", t.center)
		elif t.wood >= 10.0 and pop >= cap - 2 and t.buildings.size() < 30:
			var spot = _building_spot(t, "hut")
			if spot != null:
				t.wood -= 10.0
				place_building(t, "hut", spot)
		elif _religious_project(t, pop):
			pass
		elif t.wood >= 14.0 and t.stone >= 8.0 and pop >= cap - 3:
			for b in t.buildings:
				if b.built and b.type == "hut":
					t.wood -= 14.0
					t.stone -= 8.0
					_convert_building(b, "house")
					break
	# births (blessings and devotion help, religious strife hurts)
	t.blessed = maxf(0.0, t.blessed - dt)
	var birth_mul := (2.5 if t.blessed > 0.0 else 1.0) * (1.2 if t.devotion > 60.0 else 1.0) * (1.0 - t.tension * 0.6)
	t.birth_timer -= dt * birth_mul
	if t.birth_timer <= 0.0:
		t.birth_timer = rng.randf_range(6.0, 10.0)
		if pop < cap and t.food >= 5.0 and villagers.size() < MAX_POP:
			t.food -= 4.0
			spawn_villager(t, t.center + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), true)
			t.births += 1
			stats["births"] += 1
	# eating
	t.eat_timer -= dt
	if t.eat_timer <= 0.0:
		t.eat_timer = 15.0
		var need := pop * 0.6
		var passive := 2.0 + houses * 1.5
		t.food += passive
		if t.food >= need:
			t.food -= need
			t.starving = false
		else:
			t.food = 0.0
			var victim = t.members.pick_random()
			kill_villager(victim, "starvation")
			if not t.starving:
				log_event("Famine strikes %s!" % t.name, Color(0.9, 0.6, 0.4))
			t.starving = true
			religion.on_hardship(t, "famine", 8.0)
	# emigration → new tribe
	var pressure := pop >= 16 or (pop >= 10 and pop >= cap and t.wood < 10.0)
	if pressure and tribes.filter(func(x): return x.alive).size() < MAX_TRIBES and rng.randf() < 0.04 * dt:
		var spot = find_settle_spot(32.0, t.center, 70.0)
		if spot != null and nav.connected(t.center, spot):
			var nt := create_tribe(spot)
			nt.wood = 10.0
			nt.food = 10.0
			nt.devotion = t.devotion
			var movers: Array = t.members.filter(func(v): return not v.is_child() and not v.priest).slice(0, 5)
			for v in movers:
				migrate(v, nt)
			log_event("Settlers from %s founded %s." % [t.name, nt.name], nt.color)

## Shrines and temples: built once a tribe has enough believers and materials.
func _religious_project(t: Tribe, pop: int) -> bool:
	if t.heretical: return false
	if t.shrine == null:
		if t.worshippers >= 3 and t.devotion >= 20.0 and t.wood >= 12.0 and t.stone >= 4.0:
			var spot = _building_spot(t, "shrine", 4.0)
			if spot != null:
				t.wood -= 12.0
				t.stone -= 4.0
				place_building(t, "shrine", spot)
				log_event("%s begins a shrine to the god." % t.name, Color(1.0, 0.9, 0.55))
				return true
	elif t.shrine.built and t.shrine.type == "shrine" and t.stage != "Camp":
		if t.worshippers >= 10 and t.devotion >= 45.0 and t.stone >= 26.0 and t.wood >= 18.0:
			t.stone -= 26.0
			t.wood -= 18.0
			var b = t.shrine
			nav.set_footprint(b.pos, FOOTPRINT["shrine"], false)
			_convert_building(b, "temple")
			for r in resources_in_radius(b.pos, FOOTPRINT["temple"] + 0.8):
				remove_resource(r)
			terrain.flatten(b.pos, FOOTPRINT["temple"] + 0.5, 0.6)
			nav.set_footprint(b.pos, FOOTPRINT["temple"], true)
			log_event("%s begins raising a temple." % t.name, Color(1.0, 0.9, 0.55))
			return true
	return false

func _convert_building(b: Building, type: String) -> void:
	b.type = type
	b.built = false
	b.work = 0.0
	b.node.mesh = Assets.mesh(MODEL[type].pick_random())
	Assets.apply_tribe(b.node, b.tribe.color)
	b.node.scale = Vector3(1, 0.08, 1)

func migrate(v: Villager, nt: Tribe) -> void:
	if v.tribe == nt: return
	v.tribe.members.erase(v)
	nt.members.append(v)
	if v.priest: v.set_priest(false)
	v.set_tribe(nt)
	v._reset(0.0)
	v.target = nt.center
	v.state = Villager.S.WANDER
	v.timer = 40.0

## A villager who can't walk home (e.g. carried to another island by the god)
## joins a tribe on their island, or founds one with fellow castaways.
func handle_stranded(v: Villager) -> bool:
	for t in live_tribes():
		if t != v.tribe and nav.connected(v.position, t.center):
			var old: Tribe = v.tribe
			migrate(v, t)
			log_event("%s, cut off from %s, joined %s." % [v.vname, old.name, t.name], t.color)
			return true
	if v.is_child(): return false
	var mates := 0
	for o in v.tribe.members:
		if o != v and not o.is_child() and o.position.distance_to(v.position) < 12.0 and nav.connected(o.position, v.position):
			mates += 1
	var stranded_for: float = v.get_meta("stranded", time)
	if not v.has_meta("stranded"): v.set_meta("stranded", time)
	if (mates >= 1 or time - stranded_for > 25.0) and live_tribes().size() < MAX_TRIBES:
		var spot = find_settle_spot(6.0, v.position, 14.0)
		if spot == null or not nav.connected(spot, v.position): spot = v.position
		var old: Tribe = v.tribe
		var nt := create_tribe(spot)
		nt.wood = 8.0
		nt.food = 8.0
		nt.devotion = old.devotion
		nt.heretical = v.heretic
		for o in old.members.duplicate():
			if o != v and not o.is_child() and o.position.distance_to(v.position) < 12.0 and nav.connected(o.position, v.position):
				migrate(o, nt)
				o.remove_meta("stranded")
		migrate(v, nt)
		v.remove_meta("stranded")
		log_event("Castaways from %s founded %s on new land." % [old.name, nt.name], nt.color)
		return true
	return false

## Something a villager should run from right now (wolf on the hunt, fire).
func threat_near(v: Villager) -> Variant:
	var p := v.position
	for f in fires:
		var fp: Vector3 = f["res"].pos if f["res"] != null else f["bld"].pos
		if Vector2(fp.x - p.x, fp.z - p.z).length() < 3.2:
			return fp
	for a in eco.near(p, 6.0):
		if a.species == "wolf" and (a.state == Animal.S.CHASE and a.prey == v or a.hunger > 0.8):
			if Vector2(a.position.x - p.x, a.position.z - p.z).length() < 6.0:
				return a.position
	return null

## Impact of a villager thrown or dropped by the God Hand.
func on_villager_landed(v: Villager, vel: Vector3) -> void:
	var sp := vel.length()
	var p := v.position
	if sp > 12.0:
		for o in villagers.duplicate():
			if o != v and not o.is_busy_with_god() and Vector2(o.position.x - p.x, o.position.z - p.z).length() < 1.0:
				kill_villager(o, "crushed")
	if sp > 16.0:
		FX.debris(self, p, Color(0.45, 0.35, 0.25), 8, 4.0)
		kill_villager(v, "thrown")
		log_event("%s was hurled to their death by the god." % v.vname, Color(0.9, 0.55, 0.45))
		religion.witness(p, 22.0, "harm", 10.0, [v])
	elif sp > 9.0:
		FX.dust(self, p)
		v._reset(0.0)
		v.state = Villager.S.STUNNED
		v.timer = 2.5
		religion.witness(p, 12.0, "harm", 2.0, [v])
	else:
		v._reset(0.4)
		v.faith = minf(100.0, v.faith + 2.0)   # carried by the god and set down gently
		v.last_miracle = time

## A free, reasonably level, reachable spot for a new building of `type`:
## the whole footprint is checked (no overlap, no water, limited unevenness).
func _building_spot(t: Tribe, type := "hut", min_r := 3.5) -> Variant:
	var fp: float = FOOTPRINT[type]
	var ring := 4.5 + sqrt(float(t.buildings.size())) * 2.7
	for i in 40:
		var a := rng.randf() * TAU
		var p := t.center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(min_r + fp, ring + fp)
		if not terrain.in_bounds(p.x, p.z, 4.0) or not terrain.is_land(p.x, p.z): continue
		if terrain.height_at(p.x, p.z) < Terrain.SEA + 0.8: continue
		var hmin := 999.0
		var hmax := -999.0
		for k in 8:
			var q := p + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * fp
			var h := terrain.height_at(q.x, q.z)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
		if hmin < Terrain.SEA + 0.5 or hmax - hmin > 1.4: continue
		if not nav.walkable(p) or not nav.connected(p, t.center): continue
		var ok := true
		for tt in tribes:
			for b in tt.buildings:
				if Vector2(b.pos.x - p.x, b.pos.z - p.z).length() < fp + FOOTPRINT[b.type] + 0.7:
					ok = false
					break
			if not ok: break
		if ok:
			terrain.flatten(p, fp + 0.4, 0.75)
			return p
	return null

# ------------------------------------------------------------------ villagers
func spawn_villager(t: Tribe, pos: Vector3, child: bool) -> Villager:
	if villagers.size() >= MAX_POP: return null
	var v := Villager.new()
	add_child(v)
	pos.y = terrain.height_at(pos.x, pos.z)
	v.setup(self, t, pos, child)
	t.members.append(v)
	villagers.append(v)
	return v

func kill_villager(v: Villager, cause: String) -> void:
	if v == null or v.dead: return
	v.dead = true
	villagers.erase(v)
	v.tribe.members.erase(v)
	stats["deaths"] += 1
	stats["death_" + cause] = stats.get("death_" + cause, 0) + 1
	FX.soul(self, v.position)
	var tw := create_tween()
	tw.tween_property(v, "scale", Vector3(1.3, 0.05, 1.3) * v.grow, 0.35)
	tw.tween_callback(v.queue_free)

func kill_in_radius(pos: Vector3, r: float, cause: String, victims: Array = []) -> int:
	var n := 0
	for v in villagers.duplicate():
		if v.is_busy_with_god(): continue
		if Vector2(v.position.x - pos.x, v.position.z - pos.z).length() <= r:
			victims.append(v)
			kill_villager(v, cause)
			n += 1
	if eco: eco.kill_in_radius(pos, r, cause)
	return n

func villagers_in_radius(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for v in villagers:
		if Vector2(v.position.x - pos.x, v.position.z - pos.z).length() <= r:
			out.append(v)
	return out

func population() -> int:
	return villagers.size()

func live_tribes() -> Array:
	return tribes.filter(func(t): return t.alive)

func building_count() -> int:
	var c := 0
	for t in tribes:
		c += t.buildings.size()
	return c

# ------------------------------------------------------------------ fire
func ignite_res(r: Res) -> void:
	if not r.alive or r.burning or r.type == RES_ROCK: return
	if fires.size() > 90: return
	r.burning = true
	var node := FX.fire(self, r.pos + Vector3(0, 1.0 * r.scale, 0), 0.9 * r.scale)
	fires.append({"res": r, "bld": null, "t": rng.randf_range(6.0, 10.0), "node": node, "spread": 1.0})

func ignite_building(b: Building) -> void:
	if not b.alive or b.burning: return
	b.burning = true
	var node := FX.fire(self, b.pos + Vector3(0, 1.0, 0), 1.6)
	fires.append({"res": null, "bld": b, "t": rng.randf_range(4.0, 6.0), "node": node, "spread": 1.5})

func ignite_radius(pos: Vector3, r: float) -> void:
	for res in resources_in_radius(pos, r):
		ignite_res(res)
	for t in tribes:
		for b in t.buildings.duplicate():
			if Vector2(b.pos.x - pos.x, b.pos.z - pos.z).length() <= r:
				ignite_building(b)

func extinguish(pos: Vector3, r: float) -> int:
	var n := 0
	for f in fires.duplicate():
		var p: Vector3 = f["res"].pos if f["res"] != null else f["bld"].pos
		if Vector2(p.x - pos.x, p.z - pos.z).length() <= r:
			if f["res"] != null: f["res"].burning = false
			if f["bld"] != null: f["bld"].burning = false
			(f["node"] as Node).queue_free()
			fires.erase(f)
			n += 1
	return n

func _update_fires(dt: float) -> void:
	for f in fires.duplicate():
		f["t"] -= dt
		f["spread"] -= dt
		var p: Vector3 = f["res"].pos if f["res"] != null else f["bld"].pos
		if f["spread"] <= 0.0:
			f["spread"] = 1.5
			for r in resources_in_radius(p, 2.6):
				if rng.randf() < 0.3: ignite_res(r)
			for v in villagers.duplicate():
				if Vector2(v.position.x - p.x, v.position.z - p.z).length() < 0.9:
					kill_villager(v, "fire")
		if f["t"] <= 0.0:
			fires.erase(f)
			(f["node"] as Node).queue_free()
			if f["res"] != null:
				remove_resource(f["res"], true)
				terrain.add_fertility(p, 1.6, -0.35)
			elif f["bld"] != null:
				var bt: Tribe = f["bld"].tribe
				destroy_building(f["bld"], " by fire")
				religion.on_hardship(bt, "fire took our homes", 3.0)

# ------------------------------------------------------------------ divine hooks
func plant(pos: Vector3, radius: float, n: int) -> int:
	var c := 0
	for i in n:
		var a := rng.randf() * TAU
		var p := pos + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * radius
		if not can_grow_tree(p): continue
		var r := add_resource(RES_BUSH if rng.randf() < 0.2 else RES_TREE, p, true)
		if r: c += 1
	return c

func bless(pos: Vector3, radius: float) -> void:
	terrain.add_fertility(pos, radius, 0.25)
	extinguish(pos, radius)
	for t in tribes:
		if t.alive and t.center.distance_to(pos) < radius + 6.0:
			if t.blessed <= 0.0:
				log_event("%s is blessed by the gods." % t.name, Color(0.6, 0.85, 1.0))
			t.blessed = 60.0
			t.food += 4.0
	if rng.randf() < 0.7:
		plant(pos, radius, 2)

## Refresh villager/animal heights and building plinths after an edit.
func _on_terrain_changed(center: Vector3, radius: float) -> void:
	for r in resources_in_radius(center, radius + 1.0):
		r.pos.y = terrain.height_at(r.pos.x, r.pos.z)
		if r.pos.y < Terrain.SEA + 0.1 or (r.type == RES_TREE and terrain.biome_at(r.pos.x, r.pos.z) == Terrain.Biome.SNOW):
			remove_resource(r)
		else:
			_update_res_xform(r)
	for t in tribes:
		for b in t.buildings.duplicate():
			if Vector2(b.pos.x - center.x, b.pos.z - center.z).length() <= radius + 1.0:
				b.pos.y = terrain.height_at(b.pos.x, b.pos.z)
				b.node.position = b.pos
				if b.pos.y < Terrain.SEA - 0.2:
					destroy_building(b, " by the flood")
					religion.on_hardship(t, "the flood", 4.0)
		if t.alive and Vector2(t.center.x - center.x, t.center.z - center.z).length() <= radius + 1.0:
			t.center.y = terrain.height_at(t.center.x, t.center.z)
	for v in villagers:
		if v.is_busy_with_god(): continue
		if Vector2(v.position.x - center.x, v.position.z - center.z).length() <= radius + 1.0:
			v.position.y = maxf(terrain.height_at(v.position.x, v.position.z), Terrain.SEA - 0.25)
	if eco:
		for an in eco.animals:
			if an.species == "bird" or an.is_busy_with_god(): continue
			if Vector2(an.position.x - center.x, an.position.z - center.z).length() <= radius + 1.0:
				an.position.y = terrain.height_at(an.position.x, an.position.z)

# ------------------------------------------------------------------ main loop
func update(dt: float) -> void:
	if dt <= 0.0: return
	var steps := int(ceil(dt / 0.1))
	var sdt := dt / steps
	for s in steps:
		_step(sdt)

var cam_pos := Vector3(0, 60, 60)   # updated by main; drives animation LOD
var cam: Camera3D
var vgrid := {}                      # spatial hash of villagers (rebuilt each step)
const GRID := 8.0

static func gkey(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / GRID)), int(floor(p.z / GRID)))

## Items of a spatial hash within r of p (cell-level filter; callers check exact distance).
static func grid_near(grid: Dictionary, p: Vector3, r: float) -> Array:
	var out: Array = []
	var c := gkey(p)
	var rr := int(ceil(r / GRID))
	for dz in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var arr = grid.get(Vector2i(c.x + dx, c.y + dz))
			if arr != null: out.append_array(arr)
	return out

func _rebuild_grid() -> void:
	vgrid.clear()
	for v in villagers:
		var k := gkey(v.position)
		if vgrid.has(k): vgrid[k].append(v)
		else: vgrid[k] = [v]

var profile := false
var _step_n := 0
var prof := {}

func _prof(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	prof[key] = prof.get(key, 0) + (t1 - t0)
	return t1

func _step(dt: float) -> void:
	time += dt
	var t0 := Time.get_ticks_usec() if profile else 0
	nav.tick(dt)
	_rebuild_grid()
	eco.rebuild_grid()
	if profile: t0 = _prof("nav", t0)
	# AI LOD: off-screen villagers think every other step with twice the dt
	_step_n += 1
	for v in villagers.duplicate():
		if v.dead: continue
		if v.state == Villager.S.FLYING or v.state == Villager.S.CARRIED or v._on_screen():
			v.tick(dt)
		elif (v.get_instance_id() + _step_n) % 2 == 0:
			v.tick(dt * 2.0)
	if profile: t0 = _prof("villagers", t0)
	eco.update(dt)
	if profile: t0 = _prof("animals", t0)
	religion.update(dt)
	if profile: t0 = _prof("religion", t0)
	_update_props(dt)
	for t in tribes:
		if not t.alive: continue
		t.ai_timer -= dt
		if t.ai_timer <= 0.0:
			t.ai_timer = 1.0
			_tribe_ai(t, 1.0)
	for r in growing.duplicate():
		r.scale = minf(r.target_scale, r.scale + dt * 0.35)
		_update_res_xform(r)
		if r.scale >= r.target_scale: growing.erase(r)
	for st in _stump_free.duplicate():
		st["t"] -= dt
		if st["t"] <= 0.0:
			_release("stump", st["slot"])
			_stump_free.erase(st)
	if profile: t0 = _prof("tribes+growth", t0)
	_update_fires(dt)
	if profile: t0 = _prof("fires", t0)
	# natural regrowth: forests spread, bushes reappear
	_spread_t -= dt
	if _spread_t <= 0.0:
		_spread_t = 0.5
		if not resources.is_empty():
			for i in 3:
				var src: Res = resources[rng.randi() % resources.size()]
				if src.type == RES_ROCK or src.burning: continue
				var p := src.pos + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
				var fert := terrain.fertility_at(p.x, p.z)
				if can_grow_tree(p) and rng.randf() < 0.5 + fert * 0.6 and resources_in_radius(p, 1.2).is_empty():
					add_resource(src.type if rng.randf() < 0.8 else RES_BUSH, p, true)
			# wild berry bushes keep reappearing in grassland
			if count_type(RES_BUSH) < 160 + terrain.land_area() / 200:
				for i in 2:
					var bp := Vector3(rng.randf_range(-Terrain.HALF + 6, Terrain.HALF - 6), 0, rng.randf_range(-Terrain.HALF + 6, Terrain.HALF - 6))
					var bb := terrain.biome_at(bp.x, bp.z)
					if bb == Terrain.Biome.GRASS or bb == Terrain.Biome.FOREST or (terrain.fertility_at(bp.x, bp.z) > 0.2 and can_grow_tree(bp)):
						add_resource(RES_BUSH, bp, true)

func prof_report() -> String:
	var total := 0
	for k in prof: total += prof[k]
	var parts: Array = []
	for k in prof: parts.append("%s %.0f%%" % [k, 100.0 * prof[k] / maxf(1.0, total)])
	return "total %.0f ms: %s" % [total / 1000.0, ", ".join(parts)]

func prewarm(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_step(0.1)
		t += 0.1

# ------------------------------------------------------------------ hand props
## A tree / rock / bush lifted by the God Hand becomes a free prop node.
func make_prop(r: Res) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh(r.kind)
	mi.scale = Vector3.ONE * r.scale
	mi.set_meta("kind", r.kind)
	mi.set_meta("type", r.type)
	mi.set_meta("amount", r.amount)
	add_child(mi)
	mi.global_position = r.pos
	remove_resource(r)
	return mi

func throw_prop(mi: MeshInstance3D, v: Vector3) -> void:
	props.append({"node": mi, "vel": v, "spin": Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4)) * minf(1.0, v.length() / 10.0)})

func _update_props(dt: float) -> void:
	for pr in props.duplicate():
		var mi: MeshInstance3D = pr["node"]
		pr["vel"].y -= 22.0 * dt
		var np: Vector3 = mi.global_position + pr["vel"] * dt
		np.x = clampf(np.x, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
		np.z = clampf(np.z, -Terrain.HALF + 1.5, Terrain.HALF - 1.5)
		mi.rotation += pr["spin"] * dt
		var gh := maxf(terrain.height_at(np.x, np.z), Terrain.SEA - 1.0)
		if np.y > gh:
			mi.global_position = np
			continue
		props.erase(pr)
		_land_prop(mi, Vector3(np.x, gh, np.z), pr["vel"].length())

func _land_prop(mi: MeshInstance3D, p: Vector3, speed: float) -> void:
	var type: int = mi.get_meta("type")
	var amount: float = mi.get_meta("amount")
	if speed > 10.0:
		var victims: Array = []
		kill_in_radius(p, 1.4, "crushed", victims)
		for t in tribes:
			for b in t.buildings.duplicate():
				if speed > 15.0 and type == RES_ROCK and Vector2(b.pos.x - p.x, b.pos.z - p.z).length() < FOOTPRINT[b.type] + 0.4:
					destroy_building(b, " by a hurled boulder")
		if not victims.is_empty():
			religion.witness(p, 20.0, "harm", 8.0, victims)
		FX.debris(self, p, Color(0.45, 0.38, 0.3), 10, 5.0)
	var t := nearest_tribe(p, 7.0)
	if t != null and terrain.is_land(p.x, p.z):
		# a gift from the god: delivered straight to the village store
		deposit(t, type, amount * 1.5)
		FX.sparkle(self, p + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.5), 24, 1.0)
		log_event("The god gave %s %s." % [t.name, ["timber", "stone", "berries"][type]], Color(1.0, 0.9, 0.55))
		religion.witness(p, 16.0, "gift", 6.0)
		mi.queue_free()
		return
	if terrain.is_land(p.x, p.z) and (type == RES_ROCK or can_grow_tree(p)) and speed < 14.0:
		var r := add_resource(type, p, false, mi.get_meta("kind"))
		if r != null:
			r.amount = amount
		mi.queue_free()
		return
	FX.debris(self, p, Color(0.5, 0.4, 0.3), 6, 3.0)
	mi.queue_free()

func log_event(text: String, color := Color.WHITE) -> void:
	event_logged.emit(text, color)
	print("[t=%.0f] %s" % [time, text])

func stat_line() -> String:
	var tr := live_tribes()
	var food := 0.0
	var wood := 0.0
	var stone := 0.0
	for t in tr:
		food += t.food
		wood += t.wood
		stone += t.stone
	var rt := religion.totals()
	var ac := eco.counts()
	return "t=%5.0fs pop=%3d tribes=%d buildings=%3d trees=%4d rocks=%3d bushes=%3d fires=%2d food=%.0f wood=%.0f stone=%.0f births=%d deaths=%d built=%d destroyed=%d | faith=%.0f worship=%d heretics=%d priests=%d shrines=%d temples=%d prayer=%.0f | deer=%d rabbit=%d wolf=%d bird=%d" % [
		time, villagers.size(), tr.size(), building_count(), count_type(RES_TREE), count_type(RES_ROCK), count_type(RES_BUSH),
		fires.size(), food, wood, stone, stats["births"], stats["deaths"], stats["built"], stats["destroyed"],
		rt["avg_faith"], rt["worshippers"], rt["heretics"], rt["priests"], rt["shrines"], rt["temples"], religion.prayer,
		ac["deer"], ac["rabbit"], ac["wolf"], ac["bird"]]
