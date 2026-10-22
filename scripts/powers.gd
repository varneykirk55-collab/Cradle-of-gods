class_name Powers
extends Node3D
## Divine powers: selection, brush cursor, mouse casting and the visual
## effects for lightning, meteor and rain.

signal power_changed(idx: int)
signal flash(strength: float)

const LIST := [
	{"id": "raise", "name": "Raise Land", "short": "Raise", "key": "1", "icon": "res://assets/icons/raise.png", "color": Color(1.0, 0.85, 0.35),
		"desc": "Hold left mouse to lift the earth. Build hills, mountains and land bridges."},
	{"id": "lower", "name": "Lower Land", "short": "Lower", "key": "2", "icon": "res://assets/icons/lower.png", "color": Color(0.9, 0.6, 0.3),
		"desc": "Hold left mouse to sink the earth. Carve valleys, lakes and seas (floods drown villages)."},
	{"id": "villager", "name": "Create Life", "short": "Life", "key": "3", "icon": "res://assets/icons/villager.png", "color": Color(1.0, 0.95, 0.6),
		"desc": "Click to create 3 villagers. Near a tribe they join it, far away they found a new tribe."},
	{"id": "forest", "name": "Sow Forest", "short": "Forest", "key": "4", "icon": "res://assets/icons/forest.png", "color": Color(0.5, 1.0, 0.4),
		"desc": "Hold left mouse to grow trees and berry bushes on fertile land."},
	{"id": "rain", "name": "Blessed Rain", "short": "Rain", "key": "5", "icon": "res://assets/icons/rain.png", "color": Color(0.55, 0.8, 1.0),
		"desc": "Click to summon a rain cloud: fertile land, regrowth, fires extinguished, nearby tribes blessed with births."},
	{"id": "lightning", "name": "Lightning", "short": "Lightning", "key": "6", "icon": "res://assets/icons/lightning.png", "color": Color(0.7, 0.85, 1.0),
		"desc": "Click to smite: kills villagers and sets trees and buildings ablaze."},
	{"id": "meteor", "name": "Meteor", "short": "Meteor", "key": "7", "icon": "res://assets/icons/meteor.png", "color": Color(1.0, 0.45, 0.15),
		"desc": "Click to call down a meteor: a crater, a firestorm and utter destruction."},
]

var sim: WorldSim
var terrain: Terrain
var rig: CameraRig
var current := -1
var brush := 6.0
var painting := false
var cooldown := 0.0
var cursor: MeshInstance3D
var cursor_mat := StandardMaterial3D.new()
var hover_pos = null
var casts := {}

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

func select(idx: int) -> void:
	current = idx if idx != current else -1
	power_changed.emit(current)

func radius_for(idx: int) -> float:
	if idx < 0: return 1.0
	match LIST[idx]["id"]:
		"raise", "lower", "forest": return brush
		"villager": return 1.5
		"rain": return 12.0
		"lightning": return 2.5
		"meteor": return 9.0
	return 1.0

func pick(screen_pos: Vector2) -> Variant:
	var cam := rig.cam
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 800.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return terrain.raycast(from, dir)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and current >= 0:
			painting = true
			var p = pick(e.position)
			if p != null: cast(current, p, 0.0)
		elif not e.pressed:
			painting = false

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		painting = false

func _process(dt: float) -> void:
	cooldown = maxf(0.0, cooldown - dt)
	var vp := get_viewport()
	if vp == null or DisplayServer.get_name() == "headless":
		return
	hover_pos = pick(vp.get_mouse_position())
	if hover_pos != null and current >= 0:
		cursor.visible = true
		var r := radius_for(current)
		cursor.position = hover_pos + Vector3(0, 0.25, 0)
		cursor.scale = Vector3(r, 1.0, r)
		var c: Color = LIST[current]["color"]
		cursor_mat.albedo_color = Color(c, 0.85)
		if painting and LIST[current]["id"] in ["raise", "lower", "forest"]:
			cast(current, hover_pos, dt)
	else:
		cursor.visible = false

## Cast power idx at world position p. dt > 0 for continuous (held) powers.
func cast(idx: int, p: Vector3, dt: float) -> void:
	var id: String = LIST[idx]["id"]
	casts[id] = casts.get(id, 0) + 1
	match id:
		"raise":
			terrain.modify(p, brush, 7.0 * maxf(dt, 1.0 / 30.0))
		"lower":
			terrain.modify(p, brush, -7.0 * maxf(dt, 1.0 / 30.0))
		"forest":
			if cooldown <= 0.0:
				cooldown = 0.12
				sim.plant(p, brush, 3)
				FX.sparkle(sim, p + Vector3(0, 0.5, 0), Color(0.6, 1.0, 0.4), 14, brush * 0.5)
		"villager":
			if cooldown > 0.0: return
			cooldown = 0.25
			if not terrain.is_land(p.x, p.z): return
			var t := sim.nearest_tribe(p, 22.0)
			if t == null:
				t = sim.create_tribe(Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
				t.wood = 10.0
				t.food = 12.0
			for i in 3:
				sim.spawn_villager(t, p + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)), false)
			FX.beam(sim, p + Vector3(0, 3, 0), Color(1.0, 0.92, 0.5))
			FX.sparkle(sim, p + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.5), 30, 1.2)
		"rain":
			if cooldown > 0.0: return
			cooldown = 0.6
			_rain(p)
		"lightning":
			if cooldown > 0.0: return
			cooldown = 0.2
			_lightning(p)
		"meteor":
			if cooldown > 0.0: return
			cooldown = 0.8
			_meteor(p)

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
	var killed := sim.kill_in_radius(p, 2.5, "lightning")
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
	FX.explosion(sim, p + Vector3(0, 0.5, 0), 1.6)
	flash.emit(0.7)
	rig.shake(1.6)
	var killed := sim.kill_in_radius(p, 8.0, "meteor")
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
