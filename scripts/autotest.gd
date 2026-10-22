class_name AutoTest
extends Node
## Headless regression test: `godot --headless --path . --fixed-fps 30 -- --autotest`
## Drives the real game objects (terrain, sim, powers, God Hand) through every
## major system and prints PASS / FAIL lines; exits non-zero on failure.

var m          # main
var sim: WorldSim
var terrain: Terrain
var powers: Powers
var hand: GodHand
var fails := 0
var passes := 0

func _check(name: String, ok: bool, detail := "") -> bool:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok: passes += 1
	else: fails += 1
	return ok

func _frames(n: int, step_sim := true) -> void:
	for i in n:
		await get_tree().process_frame
		if step_sim: sim.update(1.0 / 30.0)

func _flush() -> void:
	terrain.rebuild_dirty(true)
	sim.nav.flush()
	await get_tree().physics_frame
	await get_tree().physics_frame

func run(p_main) -> void:
	m = p_main
	sim = m.sim
	terrain = m.terrain
	powers = m.powers
	hand = m.hand
	sim.religion.sandbox = true
	await _frames(2, false)
	var t_start := Time.get_ticks_msec()
	await _test_world()
	await _test_growth()
	await _test_terrain_tools()
	await _test_land_creation()
	await _test_walk_new_land()
	await _test_build_on_new_land()
	await _test_hand_villager()
	await _test_hand_animal_and_props()
	await _test_religion()
	await _test_heresy()
	await _test_ecosystem()
	await _test_powers()
	await _test_speed()
	await _test_long_run()
	print("POWER CASTS ", powers.casts)
	print("HAND STATS ", hand.stats)
	print("RELIGION STATS ", sim.religion.stats)
	print("ECO STATS ", sim.eco.stats, " causes ", sim.eco.causes)
	print("NAV STATS ", sim.nav.stats)
	print("AUTOTEST DONE passes=%d fails=%d (%.1fs)" % [passes, fails, (Time.get_ticks_msec() - t_start) / 1000.0])
	get_tree().quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------- 1-2 world
func _test_world() -> void:
	print("STAT ", sim.stat_line())
	_check("world: procedural island generated", terrain.land_area() > 9000, "land cells=%d" % terrain.land_area())
	var sea_corner := terrain.height_at(-100, -100)
	_check("world: open ocean around the island", sea_corner < -5.0, "corner height=%.1f" % sea_corner)
	_check("world: starting tribes", sim.live_tribes().size() >= 3, "tribes=%d" % sim.live_tribes().size())
	var ac := sim.eco.counts()
	_check("world: wildlife spawned", ac["deer"] > 5 and ac["rabbit"] > 5 and ac["wolf"] > 2 and ac["bird"] > 5, str(ac))
	var islands := 0
	for k in sim.nav.island_sizes:
		if sim.nav.island_sizes[k] > 500: islands += 1
	_check("world: nav grid has the main landmass", islands >= 1, "big islands=%d" % islands)

func _test_growth() -> void:
	var pop0 := sim.population()
	var b0: int = sim.stats["built"]
	var w0 := 0.0
	for t in sim.live_tribes(): w0 += t.wood + t.stone + t.food
	var us := Time.get_ticks_usec()
	for i in 10:
		sim.prewarm(30.0)
		print("STAT ", sim.stat_line())
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	print("PERF 300 s of simulation (3000 steps) took %.0f ms -> %.2f ms/step at pop %d" % [ms, ms / 3000.0, sim.population()])
	_check("sim grows population", sim.population() > pop0, "%d -> %d" % [pop0, sim.population()])
	_check("sim constructs buildings", sim.stats["built"] > b0, "built=%d" % sim.stats["built"])
	_check("villagers gather resources", sim.stats.get("deposits", 0) > 50, "deposits=%d" % sim.stats.get("deposits", 0))
	var stages := {}
	for t in sim.live_tribes(): stages[t.stage] = true
	_check("settlements progress beyond Camp", stages.has("Village") or stages.has("Town"), str(stages.keys()))
	var stuck := 0
	for v in sim.villagers:
		if v.stuck_t > 3.0: stuck += 1
	_check("villagers are not stuck", stuck <= maxi(2, sim.population() / 25), "stuck=%d of %d" % [stuck, sim.population()])
	_check("pathfinding used", sim.nav.stats["paths"] > 0, str(sim.nav.stats))

# ---------------------------------------------------------------- 6 raise/lower
func _test_terrain_tools() -> void:
	var t0 = sim.live_tribes()[0]
	var p: Vector3 = t0.center + Vector3(14, 0, 0)
	var h0 := terrain.height_at(p.x, p.z)
	for i in 30: powers.cast("raise", p, 1.0 / 30.0)
	await _flush()
	var h1 := terrain.height_at(p.x, p.z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 100, p.z), Vector3(p.x, -100, p.z))
	var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
	var coll_y: float = hit["position"].y if not hit.is_empty() else -999.0
	_check("raise terrain", h1 > h0 + 3.0, "%.2f -> %.2f" % [h0, h1])
	_check("collision follows terrain", absf(coll_y - h1) < 0.6, "collider y=%.2f mesh y=%.2f" % [coll_y, h1])
	for i in 30: powers.cast("lower", p, 1.0 / 30.0)
	var h2 := terrain.height_at(p.x, p.z)
	_check("lower terrain", h2 < h1 - 3.0, "%.2f -> %.2f" % [h1, h2])

# ---------------------------------------------------------------- 3-5 land creation
func _test_land_creation() -> void:
	var p := Vector3(92, 0, -92)
	var h0 := terrain.height_at(p.x, p.z)
	powers.land_mode = "brush"
	powers.brush = 8.0
	for i in 45: powers.cast("land", p + Vector3(i * 0.25, 0, 0), 1.0 / 30.0)
	await _flush()
	var h1 := terrain.height_at(p.x, p.z)
	_check("brush: create land from deep ocean", h0 < -5.0 and h1 > Terrain.SEA + 0.8, "%.2f -> %.2f" % [h0, h1])
	_check("brush: new land is walkable", sim.nav.walkable(p), "")
	var coast_b := terrain.biome_at(p.x + 8.0 + 11.0, p.z)
	var mid_b := terrain.biome_at(p.x + 5.0, p.z)
	print("INFO brush biomes: centre=%d edge=%d" % [mid_b, coast_b])
	var beach := false
	for d in range(6, 16):
		if terrain.biome_at(p.x + 11.0 + d * 0.5, p.z) == Terrain.Biome.BEACH: beach = true
	_check("brush: natural beach at the coastline", beach, "")
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 100, p.z), Vector3(p.x, -100, p.z))
	var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
	_check("brush: collider updated on new land", not hit.is_empty() and absf(hit["position"].y - h1) < 0.6, "")
	# --- tile mode: a row of tiles, then check the seams
	powers.land_mode = "tile"
	var base := Vector3(-95, 0, 60)
	var centers: Array = []
	for i in 5:
		powers._last_tile = Vector3(INF, 0, INF)
		var c := powers.tile_center(base + Vector3(i * Terrain.TILE, 0, 0))
		powers.cast("land", c, 0.0)
		centers.append(c)
	await _flush()
	var all_land := true
	var seam_ok := true
	var max_step := 0.0
	for i in centers.size():
		if not terrain.is_land(centers[i].x, centers[i].z): all_land = false
		if i > 0:
			var seam: Vector3 = (centers[i] + centers[i - 1]) * 0.5
			if not terrain.is_land(seam.x, seam.z): seam_ok = false
	for x in range(int(centers[0].x), int(centers[4].x)):
		max_step = maxf(max_step, absf(terrain.height_at(x + 1, base.z) - terrain.height_at(x, base.z)))
	_check("tiles: placed tiles are land", all_land, "")
	_check("tiles: adjacent tiles connect without gaps", seam_ok and max_step < 1.0, "max step between cells %.2f" % max_step)
	_check("tiles: connected landmass for navigation", sim.nav.connected(centers[0], centers[4]), "")
	# narrow land connection: a diagonal chain of tiles
	powers._last_tile = Vector3(INF, 0, INF)
	var c5 := powers.tile_center(centers[4] + Vector3(0, 0, Terrain.TILE))
	powers.cast("land", c5, 0.0)
	await _flush()
	_check("tiles: repeated placement extends the shape", sim.nav.connected(centers[0], c5), "")
	# --- remove land
	var rp: Vector3 = centers[2]
	for i in 60: powers.cast("remove", rp, 1.0 / 30.0)
	await _flush()
	_check("remove land: returns to ocean", terrain.height_at(rp.x, rp.z) < Terrain.SEA - 1.0, "h=%.2f" % terrain.height_at(rp.x, rp.z))
	_check("remove land: splits the landmass", not sim.nav.connected(centers[0], centers[4]), "")
	powers.land_mode = "brush"

# ---------------------------------------------------------------- 7 walk new land
func _test_walk_new_land() -> void:
	var t0 = sim.live_tribes()[0]
	# find the coast in some direction and build a peninsula out into the sea
	var dir := Vector3.ZERO
	var coast := Vector3.ZERO
	for a in 16:
		var d := Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0))
		for r in range(4, 90, 2):
			var q: Vector3 = t0.center + d * r
			if not terrain.in_bounds(q.x, q.z, 30.0): break
			if not terrain.is_land(q.x, q.z):
				if coast == Vector3.ZERO or r < t0.center.distance_to(coast):
					coast = q
					dir = d
				break
	if coast == Vector3.ZERO:
		_check("walk: found a coast", false)
		return
	powers.brush = 4.0
	for i in 80:
		powers.cast("land", coast - dir * 3.0 + dir * (i * 0.25), 1.0 / 30.0)
	await _flush()
	var tip := coast + dir * 14.0
	tip.y = terrain.height_at(tip.x, tip.z)
	_check("walk: peninsula is land", terrain.is_land(tip.x, tip.z), "tip h=%.2f" % tip.y)
	_check("walk: peninsula connected to the village", sim.nav.connected(t0.center, tip), "")
	var v: Villager = null
	for o in t0.members:
		if not o.is_child() and o.state != Villager.S.CARRIED:
			v = o
			break
	if v == null:
		_check("walk: villager available", false)
		return
	v._reset(0.0)
	v.target = tip
	v.state = Villager.S.WANDER
	v.timer = 120.0
	var start := v.position
	var reached := false
	for i in 1200:
		sim._step(0.1)
		if v.dead: break
		if Vector2(v.position.x - tip.x, v.position.z - tip.z).length() < 1.5:
			reached = true
			break
		if v.state != Villager.S.WANDER:
			v.target = tip
			v.state = Villager.S.WANDER
			v.timer = 120.0
	_check("walk: villager walks onto new land", reached, "from %s to %s, now %s" % [start, tip, v.position])

# ---------------------------------------------------------------- 8 build on new land
func _test_build_on_new_land() -> void:
	var c := Vector3(-60, 0, -95)
	powers.brush = 11.0
	for i in 70: powers.cast("land", c + Vector3(sin(i * 0.3) * 3.0, 0, cos(i * 0.3) * 3.0), 1.0 / 30.0)
	await _flush()
	_check("new island: created", terrain.is_land(c.x, c.z) and not sim.nav.connected(c, sim.live_tribes()[0].center), "")
	var nt0 := sim.live_tribes().size()
	powers.life_type = "villagers"
	powers.cooldown = 0.0
	powers.cast("villager", c, 0.0)
	powers.cooldown = 0.0
	powers.cast("villager", c + Vector3(1.5, 0, 1.5), 0.0)
	var nt = sim.nearest_tribe(c, 5.0)
	_check("new island: Create Life founds a settlement", nt != null and sim.live_tribes().size() == nt0 + 1, "")
	if nt == null: return
	nt.wood = 40.0
	nt.food = 40.0
	for i in 900:
		sim._step(0.1)
	var built := 0
	for b in nt.buildings:
		if b.built: built += 1
	_check("new island: settlement builds on created land", built >= 2, "built=%d buildings=%d pop=%d" % [built, nt.buildings.size(), nt.members.size()])
	var trees := 0
	for r in sim.resources_in_radius(c, 14.0):
		if r.type == WorldSim.RES_TREE: trees += 1
	powers.cooldown = 0.0
	for i in 6:
		powers.cooldown = 0.0
		powers.cast("forest", c + Vector3(6, 0, -6), 0.1)
	var trees2 := 0
	for r in sim.resources_in_radius(c, 14.0):
		if r.type == WorldSim.RES_TREE: trees2 += 1
	_check("new island: trees grow on new land", trees2 > trees, "%d -> %d" % [trees, trees2])

# ---------------------------------------------------------------- 9 hand + villager
func _wait_hover(kind: String, obj, frames := 20) -> bool:
	for i in frames:
		await _frames(1, false)
		if hand.hover != null and hand.hover["kind"] == kind and hand.hover["obj"] == obj:
			return true
	return false

func _pointer(p: Vector3) -> void:
	hand.virtual_pointer = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)

func _test_hand_villager() -> void:
	var t0 = sim.live_tribes()[0]
	m.rig.set_view(t0.center, 30.0, 0.8, 0.9, true)
	await _frames(2, false)
	var v: Villager = null
	for o in t0.members:
		if not o.is_child(): v = o
	_pointer(v.position)
	var hovered := await _wait_hover("villager", v)
	_check("hand: hover detects villager", hovered, "")
	hand.press()
	await _frames(12)
	_check("hand: grab villager", hand.state == GodHand.H.HOLD and v.state == Villager.S.CARRIED, "hand=%d v=%d" % [hand.state, v.state])
	# carry 12 m sideways, slowly
	var start := v.position
	var dest: Vector3 = t0.center + Vector3(6, 0, 6)
	if not sim.nav.walkable(dest): dest = t0.center + Vector3(-4, 0, 3)
	for i in 40:
		_pointer(start.lerp(dest, (i + 1) / 40.0))
		await _frames(1)
	await _frames(20)
	var carried_d := Vector2(v.position.x - dest.x, v.position.z - dest.z).length()
	_check("hand: carried villager follows the hand", carried_d < 2.5 and v.position.y > terrain.height_at(v.position.x, v.position.z) + 0.3, "dist %.2f, height above ground %.2f" % [carried_d, v.position.y - terrain.height_at(v.position.x, v.position.z)])
	hand.release()
	_check("hand: slow release places gently", hand.state == GodHand.H.PLACE_DOWN, "state=%d" % hand.state)
	await _frames(40)
	var on_ground: bool = absf(v.position.y - terrain.height_at(v.position.x, v.position.z)) < 0.3
	_check("hand: villager set down alive on ground", not v.dead and on_ground and v.state != Villager.S.CARRIED and v.state != Villager.S.FLYING and v.state != Villager.S.STUNNED,
		"dead=%s state=%d dist to target %.2f" % [v.dead, v.state, Vector2(v.position.x - dest.x, v.position.z - dest.z).length()])
	# placement over water lands on the nearest shore
	# --- throw
	var v2: Villager = null
	for o in t0.members:
		if not o.is_child() and o != v and o.state != Villager.S.CARRIED: v2 = o
	_pointer(v2.position)
	await _wait_hover("villager", v2)
	hand.press()
	await _frames(12)
	_check("hand: grab second villager", hand.state == GodHand.H.HOLD, "")
	var p0 := v2.position
	var dir := Vector3(1, 0, 0.3).normalized()
	for i in 6:
		_pointer(hand.hand_pos + dir * (2.0 + i * 0.8))
		await _frames(1)
	var hv := hand.hand_vel.length()
	hand.release()
	_check("hand: fast release throws", v2.state == Villager.S.FLYING, "hand speed %.1f state=%d" % [hv, v2.state])
	var flew := false
	for i in 120:
		await _frames(1)
		if v2.dead or v2.state != Villager.S.FLYING:
			flew = true
			break
	var d := Vector2(v2.position.x - p0.x, v2.position.z - p0.z).length()
	_check("hand: thrown villager flies and lands", flew and d > 6.0, "travelled %.1f m, dead=%s" % [d, v2.dead])
	hand.virtual_pointer = null

# ---------------------------------------------------------------- 10 hand + animals/props
func _test_hand_animal_and_props() -> void:
	var a: Animal = null
	for o in sim.eco.animals:
		if o.species == "deer" and not o.dead: a = o
	if a == null:
		a = sim.eco.spawn("deer", sim.live_tribes()[0].center + Vector3(8, 0, 8), false)
	m.rig.set_view(a.position, 30.0, 0.8, 0.9, true)
	await _frames(2, false)
	_pointer(a.position)
	_check("hand: hover detects animal", await _wait_hover("animal", a), "")
	hand.press()
	await _frames(12)
	_check("hand: grab deer", a.state == Animal.S.CARRIED, "state=%d" % a.state)
	var dest := a.position + Vector3(8, 0, 0)
	for i in 30:
		_pointer(a.position.lerp(dest, 0.2))
		await _frames(1)
	await _frames(15)
	hand.release()
	await _frames(40)
	_check("hand: deer relocated and released", not a.dead and a.state != Animal.S.CARRIED and a.state != Animal.S.FLYING, "state=%d" % a.state)
	# uproot a tree and drop it in a village as a gift
	var t0 = sim.live_tribes()[0]
	var tree = sim.find_nearest(t0.center + Vector3(10, 0, 10), WorldSim.RES_TREE, 150.0)
	if tree == null:
		_check("hand: found a tree", false)
		return
	m.rig.set_view(tree.pos, 30.0, 0.8, 0.9, true)
	await _frames(2, false)
	var hv := false
	for i in 20:
		_pointer(tree.pos)
		await _frames(1, false)
		if hand.hover != null and hand.hover["kind"] == "res":
			hv = true
			break
	_check("hand: hover detects tree", hv, "")
	hand.press()
	await _frames(12)
	_check("hand: uproot tree", hand.held != null and hand.held["kind"] == "prop", "")
	var wood0: float = t0.wood
	for i in 40:
		_pointer(hand.hand_pos.lerp(t0.center + Vector3(2, 0, 0), 0.25))
		await _frames(1)
	await _frames(20)
	hand.release()
	await _frames(60)
	_check("hand: tree dropped in village becomes a gift of wood", t0.wood > wood0 + 3.0, "wood %.0f -> %.0f" % [wood0, t0.wood])
	hand.virtual_pointer = null

# ---------------------------------------------------------------- 11-12 religion
func _test_religion() -> void:
	var tr: Array = sim.live_tribes()
	var t = tr[0]
	for o in tr:
		if o.members.size() > t.members.size() and not o.heretical: t = o
	var rt := sim.religion.totals()
	print("INFO religion before: ", rt)
	var f0: float = t.devotion
	sim.religion.prayer = 0.0
	sim.religion.sandbox = false
	_check("prayer: miracles cost prayer power", not sim.religion.can_afford(25.0), "")
	sim.religion.prayer = 300.0
	powers.cooldown = 0.0
	powers.cast("rain", t.center, 0.0)
	sim.religion._tick(1.0)
	_check("faith: miracle raises devotion", t.devotion > f0, "%.1f -> %.1f" % [f0, t.devotion])
	_check("prayer: casting spent prayer", sim.religion.prayer < 300.0, "prayer=%.0f" % sim.religion.prayer)
	sim.religion.sandbox = true
	# give the tribe what it needs and let it build a shrine, then a temple
	for v in t.members: v.faith = maxf(v.faith, 60.0)
	t.wood += 80.0
	t.stone += 80.0
	t.food += 80.0
	var shrine_ok := false
	for i in 2400:
		sim._step(0.1)
		if t.has_shrine():
			shrine_ok = true
			break
	_check("religion: tribe builds a shrine", shrine_ok, "shrine=%s" % (t.shrine != null))
	if not shrine_ok: return
	var ceremony := false
	var priest := false
	var p0 := sim.religion.prayer
	sim.religion.sandbox = false
	var prayed := 0.0
	for i in 2400:
		var before := sim.religion.prayer
		sim._step(0.1)
		prayed += maxf(0.0, sim.religion.prayer - before)
		for v in t.members:
			if v.priest: priest = true
			if v.state == Villager.S.WORSHIP: ceremony = true
		if ceremony and priest and prayed > 3.0: break
	sim.religion.sandbox = true
	_check("religion: a priest is appointed", priest, "")
	_check("religion: villagers gather and worship at the shrine", ceremony, "ceremonies=%d" % sim.religion.stats["ceremonies"])
	_check("religion: worship generates prayer power", prayed > 0.5, "+%.1f prayer" % prayed)
	# temple
	if t.stage == "Camp": t.stage = "Village"
	for v in t.members: v.faith = maxf(v.faith, 70.0)
	while t.members.size() < 12:
		sim.spawn_villager(t, t.center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), false)
	for v in t.members: v.faith = maxf(v.faith, 70.0)
	t.stone += 100.0
	t.wood += 100.0
	t.food += 100.0
	var temple := false
	for i in 3600:
		sim._step(0.1)
		if t.stage == "Camp": t.stage = "Village"
		if t.has_temple():
			temple = true
			break
	_check("religion: shrine upgraded to a temple", temple, "shrine type=%s built=%s" % [t.shrine.type if t.shrine else "-", t.shrine.built if t.shrine else false])
	print("INFO religion after: ", sim.religion.totals())

# ---------------------------------------------------------------- 13 heresy
func _test_heresy() -> void:
	var tr: Array = sim.live_tribes()
	var t = tr[tr.size() - 1]
	for o in tr:
		if o.members.size() >= 8 and not o.has_temple(): t = o
	print("INFO heresy target %s pop %d" % [t.name, t.members.size()])
	var h0: int = sim.religion.stats["heresies"]
	# famine with no divine help + a smiting of their kin
	for v in t.members:
		v.last_miracle = sim.time - 400.0
	t.last_miracle = sim.time - 400.0
	for i in 4:
		sim.religion.on_hardship(t, "famine", 12.0)
	var victim = null
	for v in t.members:
		if not v.heretic and not v.priest and not v.is_child(): victim = v
	if victim:
		powers.cooldown = 0.0
		powers.cast("lightning", victim.position, 0.0)
	sim.religion._tick(1.0)
	var her: Array = t.members.filter(func(v): return v.heretic)
	_check("heresy: hardship and smiting create heretics", sim.religion.stats["heresies"] > h0 and her.size() > 0, "heretics=%d" % her.size())
	var causes := {}
	for v in her: causes[v.heresy_cause] = true
	_check("heresy: heretics have understandable causes", not causes.is_empty() and not causes.has(""), str(causes.keys()))
	var hooded := true
	for v in her:
		if not v.parts["hood"].visible: hooded = false
	_check("heresy: heretics are visibly marked", hooded, "")
	var pers0: int = sim.religion.stats["persuasions"]
	for i in 600:
		sim._step(0.1)
	_check("heresy: heretics try to persuade believers", sim.religion.stats["persuasions"] > pers0, "persuasions=%d" % sim.religion.stats["persuasions"])
	# respond: a miracle of plenty in their midst wins some back
	var rec0: int = sim.religion.stats["recants"]
	her = t.members.filter(func(v): return v.heretic)
	var hn0 := her.size()
	for i in 3:
		powers.cooldown = 0.0
		powers.cast("plenty", t.center, 0.0)
		for v in t.members: v.last_miracle = sim.time
	sim.religion._tick(1.0)
	her = t.members.filter(func(v): return v.heretic)
	_check("heresy: miracles convert dissenters", sim.religion.stats["recants"] > rec0 or her.size() < hn0, "heretics %d -> %d" % [hn0, her.size()])
	# punish one heretic with the hand: throw them
	var target = null
	for v in sim.villagers:
		if v.heretic and not v.is_busy_with_god(): target = v
	if target == null:
		var cand = t.members[0] if not t.members.is_empty() else sim.villagers[0]
		cand.set_heretic(true, "test")
		target = cand
	target.grab()
	target.throw(Vector3(0, 12, 22))
	for i in 60: sim._step(1.0 / 30.0)
	_check("heresy: a heretic can be punished with the hand", target.dead or target.state == Villager.S.STUNNED or target.state != Villager.S.FLYING, "dead=%s" % target.dead)
	print("INFO heresy stats ", sim.religion.stats)

# ---------------------------------------------------------------- 14 ecosystem
func _test_ecosystem() -> void:
	var s0: Dictionary = sim.eco.stats.duplicate()
	var c0 := sim.eco.counts()
	# make sure there are hungry wolves near prey
	var wolves: Array = sim.eco.animals.filter(func(a): return a.species == "wolf")
	for w in wolves: w.hunger = 0.6
	for i in 3000:
		sim._step(0.1)
		if i % 600 == 0: print("STAT ", sim.stat_line())
	var s1: Dictionary = sim.eco.stats
	print("INFO eco %s -> %s, counts %s -> %s" % [s0, s1, c0, sim.eco.counts()])
	_check("ecosystem: animals reproduce", s1["born"] > s0["born"], "born %d" % (s1["born"] - s0["born"]))
	_check("ecosystem: wolves hunt prey", s1["predation"] > s0["predation"], "kills %d" % (s1["predation"] - s0["predation"]))
	_check("ecosystem: villagers hunt wildlife", s1["hunted"] > s0["hunted"], "hunted %d" % (s1["hunted"] - s0["hunted"]))
	_check("ecosystem: animals die naturally / environmentally", s1["died"] > s0["died"], "")
	var c := sim.eco.counts()
	var bounded := true
	for k in c:
		if c[k] > Ecosystem.SPEC[k]["cap"] * 1.35: bounded = false
	_check("ecosystem: populations stay bounded", bounded, str(c))
	var flying := 0
	for a in sim.eco.animals:
		if a.species == "bird" and a.position.y > terrain.height_at(a.position.x, a.position.z) + 3.0: flying += 1
	_check("ecosystem: birds fly", flying > 0, "airborne birds=%d" % flying)

# ---------------------------------------------------------------- 17 all powers
func _test_powers() -> void:
	var t0 = sim.live_tribes()[0]
	var popa := sim.population()
	powers.cooldown = 0.0
	powers.life_type = "villagers"
	powers.cast("villager", t0.center + Vector3(2, 0, 2), 0.0)
	_check("power: Create Life (villagers)", sim.population() == popa + 3 or sim.population() >= WorldSim.MAX_POP - 3, "%d -> %d" % [popa, sim.population()])
	var deer0 := sim.eco.count("deer")
	powers.cooldown = 0.0
	powers.life_type = "deer"
	var lp = sim.nav.nearest_walkable(t0.center + Vector3(-6, 0, 5), 6)
	powers.cast("villager", lp if lp != null else t0.center, 0.0)
	_check("power: Create Life (animals)", sim.eco.count("deer") >= deer0 + 1, "%d -> %d" % [deer0, sim.eco.count("deer")])
	powers.life_type = "villagers"
	var fp = sim.find_settle_spot(10.0)
	var trees_a := sim.count_type(WorldSim.RES_TREE) + sim.count_type(WorldSim.RES_BUSH)
	for i in 10:
		powers.cooldown = 0.0
		powers.cast("forest", fp if fp != null else t0.center, 0.1)
	_check("power: Sow Forest", sim.count_type(WorldSim.RES_TREE) + sim.count_type(WorldSim.RES_BUSH) > trees_a, "")
	powers.cooldown = 0.0
	var fert0 := terrain.fertility_at(t0.center.x, t0.center.z)
	powers.cast("rain", t0.center, 0.0)
	_check("power: Blessed Rain", t0.blessed > 0.0 and terrain.fertility_at(t0.center.x, t0.center.z) > fert0, "")
	var food0: float = t0.food
	powers.cooldown = 0.0
	powers.cast("plenty", t0.center, 0.0)
	_check("power: Miracle of Plenty", t0.food > food0 + 20.0, "%.0f -> %.0f" % [food0, t0.food])
	var victim: Villager = t0.members[0]
	var d0: int = sim.stats["deaths"]
	powers.cooldown = 0.0
	powers.cast("lightning", victim.position, 0.0)
	_check("power: Lightning kills", sim.stats["deaths"] > d0 and victim.dead, "")
	var ftree = sim.find_nearest(Vector3.ZERO, WorldSim.RES_TREE, 200.0)
	if ftree != null:
		powers.cooldown = 0.0
		powers.cast("lightning", ftree.pos, 0.0)
	_check("power: Lightning ignites trees", sim.fires.size() > 0, "fires=%d" % sim.fires.size())
	var tr := sim.live_tribes()
	var target: Vector3 = tr[1].center if tr.size() > 1 else t0.center
	var bb := sim.building_count()
	var hm := terrain.height_at(target.x, target.z)
	powers.cooldown = 0.0
	powers.cast("meteor", target, 0.0)
	await get_tree().create_timer(1.6).timeout
	_check("power: Meteor destroys buildings", sim.building_count() < bb, "%d -> %d" % [bb, sim.building_count()])
	_check("power: Meteor crater", terrain.height_at(target.x, target.z) < hm - 3.0, "")
	for i in 6:
		sim.prewarm(10.0)
		await _frames(1, false)
	_check("power: every power was cast", powers.casts.size() == Powers.LIST.size(), str(powers.casts.keys()))

func _test_speed() -> void:
	m.set_speed(0)
	var t := sim.time
	await _frames(3, false)
	m.advance(0.1)
	_check("speed: pause stops the simulation", sim.time == t, "")
	m.set_speed(3)
	m.advance(0.1)
	_check("speed: 4x advances the simulation 4x", absf(sim.time - t - 0.4) < 0.01, "dt=%.2f" % (sim.time - t))
	m.set_speed(1)

# ---------------------------------------------------------------- 20 long run
func _test_long_run() -> void:
	var us := Time.get_ticks_usec()
	for i in 30:
		sim.prewarm(40.0)
		if i % 3 == 0: print("STAT ", sim.stat_line())
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	print("PERF long run: 1200 s of simulation took %.0f ms (%.2f ms/step), pop %d, animals %d" % [ms, ms / 12000.0, sim.population(), sim.eco.animals.size()])
	_check("long run: world still alive", sim.population() > 0, "pop=%d" % sim.population())
	_check("long run: population capped", sim.population() <= WorldSim.MAX_POP, "")
	_check("long run: wildlife survives", sim.eco.animals.size() > 0, "animals=%d" % sim.eco.animals.size())
	for i in 90: await get_tree().process_frame   # let one-shot effects from the batch run expire
	var kinds := {}
	for c in sim.get_children():
		kinds[c.get_class()] = kinds.get(c.get_class(), 0) + 1
	print("INFO sim children by class ", kinds)
	var nodes := sim.get_child_count()
	print("INFO sim child nodes %d, fires %d, props %d" % [nodes, sim.fires.size(), sim.props.size()])
	_check("long run: no node leak", nodes < 2500, "nodes=%d" % nodes)
