class_name WorldSim
extends Node3D
## The living world: resources (trees, rocks, bushes), tribes, buildings,
## villagers, fire, growth. Everything advances only through update(dt) so the
## time-speed control (pause/1x/2x/4x) affects the whole simulation.

signal event_logged(text: String, color: Color)

const RES_TREE := 0
const RES_ROCK := 1
const RES_BUSH := 2
const BUCKET := 8.0
const MAX_TRIBES := 8
const MAX_POP := 400
const HOUSING := {"hall": 4, "hut": 3, "house": 6}
const MODEL := {"hall": "townhall", "hut": "hut", "house": "house"}
const BUILD_WORK := {"hall": 10.0, "hut": 7.0, "house": 12.0}
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
	_populate_nature()
	for i in 3:
		var spot = find_settle_spot(40.0)
		if spot != null:
			var t := create_tribe(spot, true)
			for j in 6:
				spawn_villager(t, spot + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), false)
			t.food = 12.0
			t.wood = 6.0

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

func find_nearest(pos: Vector3, type: int, max_r: float) -> Res:
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
				if d < bd:
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

func harvest(r: Res) -> float:
	if not r.alive: return 0.0
	var take := minf(r.amount, [3.0, 2.0, 2.0][r.type])
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
			p = Vector3(rng.randf_range(-62, 62), 0, rng.randf_range(-62, 62))
		if not terrain.in_bounds(p.x, p.z, 10.0): continue
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
	match type:
		RES_TREE: t.wood += amt
		RES_ROCK: t.stone += amt
		RES_BUSH: t.food += amt * 1.5

func place_building(t: Tribe, type: String, pos: Vector3) -> Building:
	var b := Building.new()
	b.type = type
	b.tribe = t
	b.pos = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh(MODEL[type])
	add_child(mi)
	mi.position = b.pos
	mi.rotation.y = rng.randf() * TAU if type != "hall" else rng.randf_range(-0.3, 0.3)
	mi.scale = Vector3(1, 0.08, 1)
	Assets.apply_tribe(mi, t.color)
	b.node = mi
	t.buildings.append(b)
	for r in resources_in_radius(b.pos, 1.8):
		remove_resource(r)
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

func destroy_building(b: Building, cause := "") -> void:
	if not b.alive: return
	b.alive = false
	b.tribe.buildings.erase(b)
	stats["destroyed"] += 1
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
			var spot = _building_spot(t)
			if spot != null:
				t.wood -= 10.0
				place_building(t, "hut", spot)
		elif t.wood >= 14.0 and t.stone >= 8.0 and pop >= cap - 3:
			for b in t.buildings:
				if b.built and b.type == "hut":
					t.wood -= 14.0
					t.stone -= 8.0
					b.type = "house"
					b.built = false
					b.work = 0.0
					b.node.mesh = Assets.mesh("house")
					Assets.apply_tribe(b.node, t.color)
					b.node.scale = Vector3(1, 0.08, 1)
					break
	# births
	t.blessed = maxf(0.0, t.blessed - dt)
	t.birth_timer -= dt * (2.5 if t.blessed > 0.0 else 1.0)
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
		else:
			t.food = 0.0
			var victim = t.members.pick_random()
			kill_villager(victim, "starvation")
	# emigration → new tribe
	if pop >= 16 and tribes.filter(func(x): return x.alive).size() < MAX_TRIBES and rng.randf() < 0.04 * dt:
		var spot = find_settle_spot(32.0, t.center, 60.0)
		if spot != null:
			var nt := create_tribe(spot)
			nt.wood = 10.0
			nt.food = 10.0
			var movers: Array = t.members.filter(func(v): return not v.is_child()).slice(0, 5)
			for v in movers:
				t.members.erase(v)
				nt.members.append(v)
				v.set_tribe(nt)
				v._reset(0.0)
				v.target = spot
				v.state = Villager.S.WANDER
				v.timer = 40.0
			log_event("Settlers from %s founded %s." % [t.name, nt.name], nt.color)

func _building_spot(t: Tribe) -> Variant:
	var ring := 4.0 + sqrt(float(t.buildings.size())) * 2.6
	for i in 30:
		var a := rng.randf() * TAU
		var p := t.center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.5, ring)
		if not terrain.in_bounds(p.x, p.z, 4.0) or not terrain.is_land(p.x, p.z): continue
		if terrain.height_at(p.x, p.z) < Terrain.SEA + 0.8 or terrain.slope_at(p.x, p.z) > 0.8: continue
		var ok := true
		for tt in tribes:
			for b in tt.buildings:
				if Vector2(b.pos.x - p.x, b.pos.z - p.z).length() < 2.8:
					ok = false
					break
			if not ok: break
		if ok: return p
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
	FX.soul(self, v.position)
	var tw := create_tween()
	tw.tween_property(v, "scale", Vector3(1.3, 0.05, 1.3) * v.grow, 0.35)
	tw.tween_callback(v.queue_free)

func kill_in_radius(pos: Vector3, r: float, cause: String) -> int:
	var n := 0
	for v in villagers.duplicate():
		if Vector2(v.position.x - pos.x, v.position.z - pos.z).length() <= r:
			kill_villager(v, cause)
			n += 1
	return n

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
	fires.append({"res": r, "bld": null, "t": rng.randf_range(4.0, 7.0), "node": node, "spread": 1.0})

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
				if rng.randf() < 0.22: ignite_res(r)
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
				destroy_building(f["bld"], " by fire")

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
		if t.alive and Vector2(t.center.x - center.x, t.center.z - center.z).length() <= radius + 1.0:
			t.center.y = terrain.height_at(t.center.x, t.center.z)

# ------------------------------------------------------------------ main loop
func update(dt: float) -> void:
	if dt <= 0.0: return
	var steps := int(ceil(dt / 0.1))
	var sdt := dt / steps
	for s in steps:
		_step(sdt)

func _step(dt: float) -> void:
	time += dt
	for v in villagers.duplicate():
		if not v.dead: v.tick(dt)
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
	_update_fires(dt)
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
			if count_type(RES_BUSH) < 160:
				for i in 2:
					var bp := Vector3(rng.randf_range(-74, 74), 0, rng.randf_range(-74, 74))
					var bb := terrain.biome_at(bp.x, bp.z)
					if bb == Terrain.Biome.GRASS or bb == Terrain.Biome.FOREST or (terrain.fertility_at(bp.x, bp.z) > 0.2 and can_grow_tree(bp)):
						add_resource(RES_BUSH, bp, true)

func prewarm(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_step(0.1)
		t += 0.1

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
	return "t=%5.0fs pop=%3d tribes=%d buildings=%3d trees=%4d rocks=%3d bushes=%3d fires=%2d food=%.0f wood=%.0f stone=%.0f births=%d deaths=%d built=%d destroyed=%d" % [
		time, villagers.size(), tr.size(), building_count(), count_type(RES_TREE), count_type(RES_ROCK), count_type(RES_BUSH),
		fires.size(), food, wood, stone, stats["births"], stats["deaths"], stats["built"], stats["destroyed"]]
