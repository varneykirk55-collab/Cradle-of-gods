class_name Powers
extends Node3D
## Divine powers: selection, brush cursor, mouse casting, prayer-power costs,
## and the visual effects for lightning, meteor and rain. With no power
## selected the God Hand (god_hand.gd) handles the mouse instead.

signal power_changed(idx: int)
signal flash(strength: float)
signal cast_done(id: String, pos: Vector3)
signal message(text: String)
## Every frame a brush power (land / remove / raise / lower / forest) is applied.
signal brush_cast(id: String, pos: Vector3)
signal meteor_impact(pos: Vector3)

const LIST := [
	{"id": "land", "name": "Create Land", "short": "Land", "key": "1", "icon": "res://assets/icons/land.png", "color": Color(0.55, 0.95, 0.45), "cost": 0.0,
		"desc": "Raise new land from the sea. Brush mode: hold and drag to paint islands and coastlines. Tile mode: click (or drag) to place square land tiles that join seamlessly. [B] toggles the mode."},
	{"id": "remove", "name": "Remove Land", "short": "Sink", "key": "2", "icon": "res://assets/icons/remove.png", "color": Color(0.35, 0.65, 1.0), "cost": 0.0,
		"desc": "Hold left mouse to return land to the ocean. Cut channels, split islands, drown villages."},
	{"id": "raise", "name": "Raise Land", "short": "Raise", "key": "3", "icon": "res://assets/icons/raise.png", "color": Color(1.0, 0.85, 0.35), "cost": 0.0,
		"desc": "Hold left mouse to lift existing land. Build hills, mountains and land bridges."},
	{"id": "lower", "name": "Lower Land", "short": "Lower", "key": "4", "icon": "res://assets/icons/lower.png", "color": Color(0.9, 0.6, 0.3), "cost": 0.0,
		"desc": "Hold left mouse to sink the earth. Carve valleys, lakes and seas (floods drown villages)."},
	{"id": "villager", "name": "Create Life", "short": "Life", "key": "5", "icon": "res://assets/icons/villager.png", "color": Color(1.0, 0.95, 0.6), "cost": 15.0,
		"desc": "Click to create life. [C] cycles: 3 villagers (join a nearby tribe or found a new one), or a pair of deer, rabbits, wolves or birds."},
	{"id": "forest", "name": "Sow Forest", "short": "Forest", "key": "6", "icon": "res://assets/icons/forest.png", "color": Color(0.5, 1.0, 0.4), "cost": 0.6,
		"desc": "Hold left mouse to grow trees and berry bushes on fertile land."},
	{"id": "rain", "name": "Blessed Rain", "short": "Rain", "key": "7", "icon": "res://assets/icons/rain.png", "color": Color(0.55, 0.8, 1.0), "cost": 25.0,
		"desc": "Summon a rain cloud: fertile land, regrowth, fires put out, nearby tribes blessed. A strong miracle for believers."},
	{"id": "plenty", "name": "Miracle of Plenty", "short": "Plenty", "key": "8", "icon": "res://assets/icons/plenty.png", "color": Color(1.0, 0.75, 0.3), "cost": 20.0,
		"desc": "Shower food on a settlement. Ends famine, wins back heretics who see it, raises faith."},
	{"id": "lightning", "name": "Lightning", "short": "Smite", "key": "9", "icon": "res://assets/icons/lightning.png", "color": Color(0.7, 0.85, 1.0), "cost": 10.0,
		"desc": "Click to smite: kills villagers and animals and sets trees and buildings ablaze. Striking heretics cows other heretics; striking the faithful breeds resentment."},
	{"id": "meteor", "name": "Meteor", "short": "Meteor", "key": "0", "icon": "res://assets/icons/meteor.png", "color": Color(1.0, 0.45, 0.15), "cost": 60.0,
		"desc": "Call down a meteor: a crater, a firestorm and utter destruction."},
]
const LIFE_TYPES := ["villagers", "deer", "rabbit", "wolf", "bird"]
const LIFE_NAMES := {"villagers": "Villagers", "deer": "Deer", "rabbit": "Rabbits", "wolf": "Wolves", "bird": "Birds"}
const BRUSH_MIN := 2.0
const BRUSH_MAX := 20.0

var sim: WorldSim
var terrain: Terrain
var rig: CameraRig
var current := -1
var brush := 6.0
var land_mode := "brush"     # "brush" or "tile"
var life_type := "villagers"
var painting := false
var cooldown := 0.0
var cursor: MeshInstance3D
var tile_cursor: Node3D
var cursor_mat := StandardMaterial3D.new()
var hover_pos = null
var casts := {}
var _last_tile := Vector3(INF, 0, INF)
var _witness_t := 0.0
var _msg_t := 0.0

func setup(p_sim: WorldSim, p_terrain: Terrain, p_rig: CameraRig) -> void:
	sim = p_sim
	terrain = p_terrain
	rig = p_rig
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_mat.no_depth_test = true
	cursor_mat.albedo_color = Color(1, 1, 1, 0.8)
	tm.material = cursor_mat
	cursor = MeshInstance3D.new()
	cursor.mesh = tm
	cursor.visible = false
	add_child(cursor)
	# square outline for tile placement
	tile_cursor = Node3D.new()
	tile_cursor.visible = false
	add_child(tile_cursor)
	for i in 4:
		var bm := BoxMesh.new()
		bm.size = Vector3(Terrain.TILE + 0.2, 0.08, 0.2) if i < 2 else Vector3(0.2, 0.08, Terrain.TILE + 0.2)
		bm.material = cursor_mat
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var h := Terrain.TILE * 0.5
		mi.position = [Vector3(0, 0, -h), Vector3(0, 0, h), Vector3(-h, 0, 0), Vector3(h, 0, 0)][i]
		tile_cursor.add_child(mi)

func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id: return i
	return -1

func select(idx: int) -> void:
	current = idx if idx != current else -1
	power_changed.emit(current)

func current_id() -> String:
	return LIST[current]["id"] if current >= 0 else ""

func toggle_land_mode() -> void:
	land_mode = "tile" if land_mode == "brush" else "brush"
	power_changed.emit(current)

func cycle_life() -> void:
	life_type = LIFE_TYPES[(LIFE_TYPES.find(life_type) + 1) % LIFE_TYPES.size()]
	power_changed.emit(current)

func set_brush(v: float) -> void:
	brush = clampf(v, BRUSH_MIN, BRUSH_MAX)
	power_changed.emit(current)

func radius_for(idx: int) -> float:
	if idx < 0: return 1.0
	match LIST[idx]["id"]:
		"land", "remove", "raise", "lower", "forest": return brush
		"villager": return 1.5
		"rain": return 12.0
		"plenty": return 6.0
		"lightning": return 2.5
		"meteor": return 9.0
	return 1.0

func pick(screen_pos: Vector2) -> Variant:
	var cam := rig.cam
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 900.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p = hit["position"] if not hit.is_empty() else terrain.raycast(from, dir, 900.0)
	if p == null and absf(dir.y) > 0.01:
		# over open sea beyond the collider: hit the water plane
		var t := (Terrain.SEA - from.y) / dir.y
		if t > 0.0: p = from + dir * t
	if p != null and (p as Vector3).y < Terrain.SEA and absf(dir.y) > 0.01:
		var t2 := (Terrain.SEA - from.y) / dir.y
		if t2 > 0.0: p = from + dir * t2   # aim at the water surface, not the sea floor
	if p != null and not terrain.in_bounds(p.x, p.z, 0.5): return null
	return p

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and current >= 0:
			painting = true
			_last_tile = Vector3(INF, 0, INF)
			var p = pick(e.position)
			if p != null: cast(current, p, 0.0)
		elif not e.pressed:
			painting = false

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		painting = false

func is_continuous(id: String) -> bool:
	return id in ["raise", "lower", "forest", "remove"] or (id == "land")

func _process(dt: float) -> void:
	cooldown = maxf(0.0, cooldown - dt)
	_witness_t -= dt
	_msg_t -= dt
	var vp := get_viewport()
	if vp == null or DisplayServer.get_name() == "headless":
		return
	hover_pos = pick(vp.get_mouse_position())
	if hover_pos != null and current >= 0:
		var id := current_id()
		var c: Color = LIST[current]["color"]
		cursor_mat.albedo_color = Color(c, 0.85)
		if id == "land" and land_mode == "tile":
			cursor.visible = false
			tile_cursor.visible = true
			var tc := tile_center(hover_pos)
			tile_cursor.position = Vector3(tc.x, maxf(terrain.height_at(tc.x, tc.z), Terrain.SEA) + 0.3, tc.z)
		else:
			tile_cursor.visible = false
			cursor.visible = true
			var r := radius_for(current)
			cursor.position = Vector3(hover_pos.x, maxf(hover_pos.y, Terrain.SEA) + 0.25, hover_pos.z)
			cursor.scale = Vector3(r, 1.0, r)
		if painting and is_continuous(id):
			cast(current, hover_pos, dt)
	else:
		cursor.visible = false
		tile_cursor.visible = false

func tile_center(p: Vector3) -> Vector3:
	var cx := floorf((p.x + Terrain.HALF) / Terrain.TILE) * Terrain.TILE + Terrain.TILE * 0.5 - Terrain.HALF
	var cz := floorf((p.z + Terrain.HALF) / Terrain.TILE) * Terrain.TILE + Terrain.TILE * 0.5 - Terrain.HALF
	return Vector3(cx, 0, cz)

func _pay(idx: int, scale := 1.0) -> bool:
	var cost: float = LIST[idx]["cost"] * scale
	if cost <= 0.0: return true
	if sim.religion.spend(cost): return true
	if _msg_t <= 0.0:
		_msg_t = 1.5
		message.emit("Not enough prayer power for %s (needs %d). Build shrines and let your people worship." % [LIST[idx]["name"], int(cost)])
	return false

## Land shaping near a settlement counts as a (small) blessing.
func _land_witness(p: Vector3) -> void:
	if _witness_t > 0.0: return
	_witness_t = 2.5
	if sim.nearest_tribe(p, 30.0) != null:
		sim.religion.witness(p, 30.0, "good", 1.5)

## Cast power idx (or id) at world position p. dt > 0 for continuous (held) powers.
func cast(idx_or_id, p: Vector3, dt: float) -> void:
	var idx: int = idx_or_id if idx_or_id is int else index_of(idx_or_id)
	var id: String = LIST[idx]["id"]
	casts[id] = casts.get(id, 0) + 1
	var step := maxf(dt, 1.0 / 30.0)
	if is_continuous(id) and not (id == "land" and land_mode == "tile"):
		brush_cast.emit(id, p)
	match id:
		"land":
			if land_mode == "tile":
				var tc := tile_center(p)
				if tc.distance_to(_last_tile) < 0.5: return
				_last_tile = tc
				terrain.place_tile(tc)
				FX.dust(sim, Vector3(tc.x, Terrain.SEA + 0.5, tc.z))
				cast_done.emit(id, tc)
			else:
				terrain.paint_land(p, brush, step)
				_brush_fx(p, Color(0.85, 0.95, 1.0), 0.06)
			_land_witness(p)
		"remove":
			terrain.remove_land(p, brush, step)
			_brush_fx(p, Color(0.7, 0.85, 1.0), 0.08)
		"raise":
			terrain.modify(p, brush, 7.0 * step)
		"lower":
			terrain.modify(p, brush, -7.0 * step)
		"forest":
			if cooldown <= 0.0:
				cooldown = 0.12
				if not _pay(idx): return
				var n := sim.plant(p, brush, 3)
				FX.sparkle(sim, p + Vector3(0, 0.5, 0), Color(0.6, 1.0, 0.4), 14, brush * 0.5)
				if n > 0 and _witness_t <= 0.0:
					_witness_t = 2.0
					sim.religion.witness(p, 25.0, "good", 2.0)
		"villager":
			if cooldown > 0.0: return
			cooldown = 0.25
			if not terrain.is_land(p.x, p.z): return
			if not _pay(idx, 1.0 if life_type == "villagers" else 0.5): return
			if life_type == "villagers":
				var t := sim.nearest_tribe(p, 22.0)
				if t != null and not sim.nav.connected(p, t.center): t = null
				if t == null:
					t = sim.create_tribe(Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
					t.wood = 10.0
					t.food = 12.0
				for i in 3:
					var v := sim.spawn_villager(t, p + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)), false)
					if v != null:
						v.faith = randf_range(55.0, 80.0)   # born of a miracle
						v.last_miracle = sim.time
				sim.religion.witness(p, 22.0, "good", 8.0)
			else:
				for i in 2:
					var a := sim.eco.spawn(life_type, p + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)), false)
					if a != null and life_type == "bird":
						a.position.y = terrain.height_at(p.x, p.z) + 3.0
			FX.beam(sim, p + Vector3(0, 3, 0), Color(1.0, 0.92, 0.5))
			FX.sparkle(sim, p + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.5), 30, 1.2)
			cast_done.emit(id, p)
		"rain":
			if cooldown > 0.0: return
			cooldown = 0.6
			if not _pay(idx): return
			var crisis := sim.fires.size() > 0 or _tribe_in_crisis(p, 18.0)
			_rain(p)
			sim.religion.witness(p, 26.0, "good", 16.0 if crisis else 10.0)
			cast_done.emit(id, p)
		"plenty":
			if cooldown > 0.0: return
			cooldown = 0.6
			if not _pay(idx): return
			_plenty(p)
			cast_done.emit(id, p)
		"lightning":
			if cooldown > 0.0: return
			cooldown = 0.2
			if not _pay(idx): return
			_lightning(p)
			cast_done.emit(id, p)
		"meteor":
			if cooldown > 0.0: return
			cooldown = 0.8
			if not _pay(idx): return
			_meteor(p)
			cast_done.emit(id, p)

var _fx_t := 0.0
## Spray / dust where the brush is working (rate-limited).
func _brush_fx(p: Vector3, c: Color, every: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _fx_t < every * 4.0: return
	_fx_t = now
	var a := randf() * TAU
	var q := p + Vector3(cos(a), 0, sin(a)) * brush * randf_range(0.3, 0.9)
	FX.sparkle(sim, Vector3(q.x, Terrain.SEA + 0.3, q.z), c, 10, brush * 0.25)

func _tribe_in_crisis(p: Vector3, r: float) -> bool:
	var t := sim.nearest_tribe(p, r)
	return t != null and (t.starving or t.food < 3.0)

func _plenty(p: Vector3) -> void:
	var t := sim.nearest_tribe(p, 14.0)
	var crisis := t != null and (t.starving or t.food < t.members.size())
	if t != null:
		t.food += 25.0 + t.members.size() * 2.0
		t.starving = false
		sim.log_event("A miracle of plenty feeds %s%s." % [t.name, " in its hour of need" if crisis else ""], Color(1.0, 0.8, 0.4))
	for i in 3:
		sim.add_resource(WorldSim.RES_BUSH, p + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), true)
	terrain.add_fertility(p, 6.0, 0.15)
	FX.sparkle(sim, p + Vector3(0, 2.0, 0), Color(1.0, 0.75, 0.3), 70, 4.0)
	FX.beam(sim, p + Vector3(0, 3, 0), Color(1.0, 0.8, 0.35))
	sim.religion.witness(p, 24.0, "good", 18.0 if crisis else 11.0)

func _lightning(p: Vector3) -> void:
	var bolt := Node3D.new()
	sim.add_child(bolt)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.92, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.85, 1.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	cyl.radial_segments = 5
	cyl.rings = 1
	cyl.material = m
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_color = Color(0.4, 0.55, 1.0, 0.45)
	var glow_cyl := CylinderMesh.new()
	glow_cyl.top_radius = 0.5
	glow_cyl.bottom_radius = 0.5
	glow_cyl.height = 1.0
	glow_cyl.radial_segments = 8
	glow_cyl.rings = 1
	glow_cyl.material = gm
	var pts: Array = []
	var top := p + Vector3(randf_range(-3, 3), 38.0, randf_range(-3, 3))
	for i in 11:
		var t := float(i) / 10.0
		var q := top.lerp(p, t)
		if i > 0 and i < 10:
			q += Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		pts.append(q)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new()
		seg.mesh = cyl
		bolt.add_child(seg)
		seg.global_position = (a + b) * 0.5
		var d := b - a
		seg.global_transform.basis = Basis(Quaternion(Vector3.UP, (-d).normalized())).scaled(Vector3(1, d.length(), 1))
		var glow := MeshInstance3D.new()
		glow.mesh = glow_cyl
		seg.add_child(glow)
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 10.0
	light.omni_range = 30.0
	bolt.add_child(light)
	light.global_position = p + Vector3(0, 4, 0)
	var tw := bolt.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(bolt.queue_free)
	FX.sparkle(sim, p + Vector3(0, 0.3, 0), Color(0.7, 0.85, 1.0), 40, 0.8)
	FX.debris(sim, p, Color(0.3, 0.25, 0.2), 10, 6.0)
	flash.emit(0.45)
	rig.shake(0.35)
	var victims: Array = []
	var killed := sim.kill_in_radius(p, 2.5, "lightning", victims)
	sim.religion.witness(p, 22.0, "harm", 7.0 + killed * 2.0, victims)
	sim.ignite_radius(p, 3.0)
	terrain.add_fertility(p, 2.5, -0.6)
	if killed > 0:
		sim.log_event("Lightning struck down %d villager%s." % [killed, "s" if killed > 1 else ""], Color(0.7, 0.85, 1.0))

func _meteor(p: Vector3) -> void:
	var rock := MeshInstance3D.new()
	rock.mesh = Assets.mesh("meteor")
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.12, 0.05)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.42, 0.1)
	mm.emission_energy_multiplier = 0.9
	rock.material_override = mm
	sim.add_child(rock)
	var start := p + Vector3(-30, 55, -22)
	rock.global_position = start
	rock.scale = Vector3.ONE * 1.6
	var trail := FX.fire(rock, start, 2.2)
	trail.local_coords = false
	trail.gravity = Vector3(0, 0, 0)
	var tw := rock.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rock, "global_position", p, 1.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(rock, "rotation", Vector3(4, 2, 3), 1.1)
	tw.chain().tween_callback(func(): _impact(p, rock))

func _impact(p: Vector3, rock: Node3D) -> void:
	rock.queue_free()
	meteor_impact.emit(p)
	FX.explosion(sim, p + Vector3(0, 0.5, 0), 1.6)
	flash.emit(0.7)
	rig.shake(1.6)
	var victims: Array = []
	var killed := sim.kill_in_radius(p, 8.0, "meteor", victims)
	sim.religion.witness(p, 40.0, "harm", 20.0, victims)
	var destroyed := 0
	for t in sim.tribes:
		for b in t.buildings.duplicate():
			if Vector2(b.pos.x - p.x, b.pos.z - p.z).length() <= 8.0:
				sim.destroy_building(b, " by a meteor")
				destroyed += 1
	for r in sim.resources_in_radius(p, 6.5):
		sim.remove_resource(r)
	terrain.modify(p, 7.5, -4.5)
	terrain.modify(p, 3.5, -2.0)
	terrain.add_fertility(p, 10.0, -1.0)
	sim.ignite_radius(p, 11.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 14.0
	light.omni_range = 40.0
	sim.add_child(light)
	light.global_position = p + Vector3(0, 6, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 1.5)
	tw.tween_callback(light.queue_free)
	sim.log_event("A meteor struck! %d dead, %d buildings destroyed." % [killed, destroyed], Color(1.0, 0.55, 0.25))

func _rain(p: Vector3) -> void:
	var cloud := Node3D.new()
	sim.add_child(cloud)
	cloud.global_position = p + Vector3(0, 13, 0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.55, 0.6, 0.7, 0.8)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.roughness = 1.0
	for i in 9:
		var s := SphereMesh.new()
		s.radius = randf_range(2.2, 3.6)
		s.height = s.radius * 1.1
		s.radial_segments = 10
		s.rings = 6
		s.material = cm
		var mi := MeshInstance3D.new()
		mi.mesh = s
		cloud.add_child(mi)
		var a := i * 0.7
		mi.position = Vector3(cos(a) * randf_range(1, 6), randf_range(-0.6, 1.0), sin(a) * randf_range(1, 6))
	var rp := FX.rain(cloud, 9.0)
	rp.position = Vector3(0, -1.5, 0)
	cloud.scale = Vector3.ONE * 0.2
	var tw := cloud.create_tween()
	tw.tween_property(cloud, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK)
	for i in 10:
		tw.tween_interval(0.6)
		tw.tween_callback(func(): sim.bless(p, 12.0))
	tw.tween_callback(func(): rp.emitting = false)
	tw.tween_property(cloud, "scale", Vector3(1.4, 0.05, 1.4), 1.2)
	tw.tween_callback(cloud.queue_free)
	sim.bless(p, 12.0)
