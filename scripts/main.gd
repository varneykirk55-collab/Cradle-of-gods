extends Node3D
## Entry point: builds the environment, terrain, water, simulation, camera,
## powers and HUD; handles global hotkeys and the automated test / screenshot
## modes (pass `-- --autotest` or `-- --shots` on the command line).

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const SPEED_NAMES := ["paused", "1x", "2x", "4x"]

var terrain: Terrain
var sim: WorldSim
var rig: CameraRig
var powers: Powers
var hud: Hud
var speed_idx := 1
var world_seed := 0
var args := PackedStringArray()

func _ready() -> void:
	args = OS.get_cmdline_user_args()
	world_seed = randi() % 100000
	for a in args:
		if a.begins_with("--seed="):
			world_seed = int(a.substr(7))
	if "--autotest" in args or "--shots" in args:
		if not _has_seed_arg(): world_seed = 4242
	print("Cradle of Gods - world seed %d" % world_seed)
	_setup_environment()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(world_seed)
	_setup_water()
	sim = WorldSim.new()
	add_child(sim)
	sim.setup(terrain, world_seed)
	rig = CameraRig.new()
	rig.terrain = terrain
	add_child(rig)
	var first: Vector3 = sim.tribes[0].center if not sim.tribes.is_empty() else Vector3.ZERO
	rig.set_view(first, 55.0, 0.7, 0.8, true)
	powers = Powers.new()
	add_child(powers)
	powers.setup(sim, terrain, rig)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, sim, powers)
	if "--autotest" in args:
		hud.splash.visible = false
		_autotest()
	elif "--shots" in args:
		_shots()

func _has_seed_arg() -> bool:
	for a in args:
		if a.begins_with("--seed="): return true
	return false

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.4)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _setup_water() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec4 shallow : source_color = vec4(0.22, 0.72, 0.78, 1.0);
uniform vec4 deep : source_color = vec4(0.05, 0.28, 0.48, 1.0);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.35 + TIME * 1.2) * 0.05 + cos(wpos.z * 0.3 + TIME * 0.9) * 0.05;
}
void fragment() {
	float w = sin(wpos.x * 0.7 + TIME * 1.5) * cos(wpos.z * 0.6 + TIME * 1.1);
	float edge = clamp(length(wpos.xz) / 140.0, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, 0.35 + edge * 0.5 + w * 0.06);
	ALPHA = clamp(0.62 + fres * 0.3 + edge * 0.3, 0.0, 0.97);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	pm.subdivide_width = 80
	pm.subdivide_depth = 80
	pm.material = m
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = pm
	water.position = Vector3(0, Terrain.SEA - 0.12, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.07, 0.25, 0.35)
	var fm := PlaneMesh.new()
	fm.size = Vector2(700, 700)
	fm.material = floor_mat
	var sea_floor := MeshInstance3D.new()
	sea_floor.mesh = fm
	sea_floor.position = Vector3(0, Terrain.MIN_H + 1.0, 0)
	add_child(sea_floor)

func set_speed(i: int) -> void:
	speed_idx = clampi(i, 0, SPEEDS.size() - 1)
	if hud: hud.set_speed_button(speed_idx)

func speed_name() -> String:
	return SPEED_NAMES[speed_idx]

func _process(dt: float) -> void:
	if "--autotest" in args: return  # autotest drives the sim explicitly
	sim.update(dt * SPEEDS[speed_idx])

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo: return
	if hud.splash_visible():
		hud.hide_splash()
		return
	var k: int = e.keycode
	if k >= KEY_1 and k <= KEY_7:
		powers.select(k - KEY_1)
	elif k == KEY_ESCAPE:
		if powers.current >= 0: powers.select(powers.current)
	elif k == KEY_SPACE:
		set_speed(1 if speed_idx == 0 else 0)
	elif k == KEY_EQUAL or k == KEY_KP_ADD or k == KEY_PERIOD:
		set_speed(mini(speed_idx + 1, 3))
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT or k == KEY_COMMA:
		set_speed(maxi(speed_idx - 1, 0))
	elif k == KEY_BRACKETLEFT:
		powers.brush = maxf(2.0, powers.brush - 1.0)
		hud._refresh_info()
	elif k == KEY_BRACKETRIGHT:
		powers.brush = minf(16.0, powers.brush + 1.0)
		hud._refresh_info()
	elif k == KEY_H or k == KEY_F1:
		hud.toggle_help()
	elif k == KEY_TAB:
		var tr := sim.live_tribes()
		if not tr.is_empty():
			var idx := 0
			for i in tr.size():
				if tr[i].center.distance_to(rig.focus) < 3.0:
					idx = (i + 1) % tr.size()
			rig.focus = tr[idx].center
			rig.dist = 32.0
	elif k == KEY_F12:
		_save_shot("manual_%d" % Time.get_ticks_msec())

func _save_shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
	img.save_png(path)
	print("SCREENSHOT ", path)

# ======================================================================= tests
func _check(name: String, ok: bool, detail := "") -> bool:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	return ok

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _autotest() -> void:
	var fails := 0
	await _frames(2)
	print("STAT ", sim.stat_line())
	var pop0 := sim.population()
	var b0 := sim.building_count()
	for i in 10:
		sim.prewarm(30.0)
		print("STAT ", sim.stat_line())
	if not _check("sim grows population", sim.population() > pop0, "%d -> %d" % [pop0, sim.population()]): fails += 1
	if not _check("sim constructs buildings", sim.stats["built"] > b0, "built=%d" % sim.stats["built"]): fails += 1
	var t0: WorldSim.Tribe = sim.live_tribes()[0]
	# --- raise / lower terrain + collision
	var p := t0.center + Vector3(14, 0, 0)
	var h0 := terrain.height_at(p.x, p.z)
	for i in 30: powers.cast(0, p, 1.0 / 30.0)
	terrain.rebuild_dirty()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var h1 := terrain.height_at(p.x, p.z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 100, p.z), Vector3(p.x, -100, p.z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var coll_y: float = hit["position"].y if not hit.is_empty() else -999.0
	if not _check("raise terrain", h1 > h0 + 3.0, "%.2f -> %.2f" % [h0, h1]): fails += 1
	if not _check("collision follows terrain", absf(coll_y - h1) < 0.6, "collider y=%.2f mesh y=%.2f" % [coll_y, h1]): fails += 1
	for i in 30: powers.cast(1, p, 1.0 / 30.0)
	var h2 := terrain.height_at(p.x, p.z)
	if not _check("lower terrain", h2 < h1 - 3.0, "%.2f -> %.2f" % [h1, h2]): fails += 1
	# --- spawn villagers
	var popa := sim.population()
	powers.cooldown = 0.0
	powers.cast(2, t0.center + Vector3(2, 0, 2), 0.0)
	if not _check("spawn villagers", sim.population() == popa + 3, "%d -> %d" % [popa, sim.population()]): fails += 1
	var tribes_a := sim.live_tribes().size()
	var far = sim.find_settle_spot(30.0)
	if far != null:
		powers.cooldown = 0.0
		powers.cast(2, far, 0.0)
		_check("spawn far away founds tribe", sim.live_tribes().size() == tribes_a + 1, "%d -> %d tribes" % [tribes_a, sim.live_tribes().size()])
	# --- forest
	var trees_a := sim.count_type(WorldSim.RES_TREE) + sim.count_type(WorldSim.RES_BUSH)
	var fp = sim.find_settle_spot(10.0)
	for i in 10:
		powers.cooldown = 0.0
		powers.cast(3, fp if fp != null else t0.center, 0.1)
	var trees_b := sim.count_type(WorldSim.RES_TREE) + sim.count_type(WorldSim.RES_BUSH)
	if not _check("sow forest", trees_b > trees_a, "%d -> %d plants" % [trees_a, trees_b]): fails += 1
	# --- rain / bless
	powers.cooldown = 0.0
	var fert0 := terrain.fertility_at(t0.center.x, t0.center.z)
	powers.cast(4, t0.center, 0.0)
	if not _check("blessed rain", t0.blessed > 0.0 and terrain.fertility_at(t0.center.x, t0.center.z) > fert0, "blessed=%.0f fert %.2f->%.2f" % [t0.blessed, fert0, terrain.fertility_at(t0.center.x, t0.center.z)]): fails += 1
	# --- lightning on a villager
	var victim: Villager = t0.members[0]
	var d0: int = sim.stats["deaths"]
	powers.cooldown = 0.0
	powers.cast(5, victim.position, 0.0)
	if not _check("lightning kills", sim.stats["deaths"] > d0 and victim.dead, "deaths %d -> %d" % [d0, sim.stats["deaths"]]): fails += 1
	var fires := sim.fires.size()
	print("INFO fires after lightning: %d" % fires)
	# --- meteor on a village
	var target: Vector3 = sim.live_tribes()[1].center if sim.live_tribes().size() > 1 else t0.center
	var bb := sim.building_count()
	var hm := terrain.height_at(target.x, target.z)
	var d1: int = sim.stats["deaths"]
	powers.cooldown = 0.0
	powers.cast(6, target, 0.0)
	await get_tree().create_timer(1.6).timeout
	var ha := terrain.height_at(target.x, target.z)
	if not _check("meteor destroys buildings", sim.building_count() < bb, "%d -> %d buildings" % [bb, sim.building_count()]): fails += 1
	if not _check("meteor crater", ha < hm - 3.0, "height %.2f -> %.2f" % [hm, ha]): fails += 1
	print("INFO meteor deaths: %d, fires now: %d" % [sim.stats["deaths"] - d1, sim.fires.size()])
	# --- fire burns out over time
	for i in 6:
		sim.prewarm(10.0)
		await _frames(1)
		print("STAT ", sim.stat_line())
	# --- long run stability
	for i in 10:
		sim.prewarm(30.0)
		print("STAT ", sim.stat_line())
	if not _check("world still alive after long run", sim.population() > 0, "pop=%d" % sim.population()): fails += 1
	print("POWER CASTS ", powers.casts)
	print("AUTOTEST DONE fails=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _shots() -> void:
	set_speed(1)
	await _frames(8)
	await _save_shot("01_title_splash")
	hud.splash.visible = false
	sim.prewarm(300.0)
	terrain.rebuild_dirty()
	rig.set_view(Vector3(0, 0, 0), 150.0, 0.6, 1.0, true)
	await _frames(20)
	await _save_shot("02_world_overview")
	var tr := sim.live_tribes()
	var t0: WorldSim.Tribe = tr[0]
	rig.set_view(t0.center, 26.0, 0.9, 0.62, true)
	await _frames(30)
	await _save_shot("03_village_closeup")
	hud.toggle_help()
	await _frames(4)
	await _save_shot("04_help_overlay")
	hud.toggle_help()
	# rain + bless
	powers.select(4)
	var t1: WorldSim.Tribe = tr[1] if tr.size() > 1 else t0
	rig.set_view(t1.center, 45.0, 2.2, 0.55, true)
	powers.cast(4, t1.center + Vector3(4, 0, 0), 0.0)
	await _frames(40)
	await _save_shot("05_blessed_rain")
	# lightning into a forest near a village + fire
	powers.select(5)
	var tree = sim.find_nearest(t0.center, WorldSim.RES_TREE, 40.0)
	var lp: Vector3 = tree.pos if tree != null else t0.center + Vector3(6, 0, 6)
	rig.set_view(lp, 30.0, 0.4, 0.6, true)
	powers.cooldown = 0.0
	powers.cast(5, lp, 0.0)
	await _frames(2)
	await _save_shot("06_lightning")
	for i in 8:
		sim.update(0.5)
		await _frames(2)
	await _save_shot("07_forest_fire")
	# meteor on a village
	powers.select(6)
	var t2: WorldSim.Tribe = tr[tr.size() - 1]
	rig.set_view(t2.center, 55.0, 1.4, 0.65, true)
	await _frames(4)
	await _save_shot("08_before_meteor")
	powers.cooldown = 0.0
	powers.cast(6, t2.center, 0.0)
	await get_tree().create_timer(0.85).timeout
	await _save_shot("09_meteor_falling")
	await get_tree().create_timer(0.5).timeout
	await _save_shot("10_meteor_impact")
	await get_tree().create_timer(2.5).timeout
	await _save_shot("11_crater")
	# terrain sculpting
	powers.select(0)
	var mp := t0.center + Vector3(-16, 0, 10)
	for i in 60: powers.cast(0, mp, 1.0 / 30.0)
	for i in 20: powers.cast(1, mp + Vector3(10, 0, -6), 1.0 / 30.0)
	rig.set_view(mp, 60.0, 0.5, 0.7, true)
	await _frames(10)
	await _save_shot("12_terrain_sculpt")
	print("SHOTS DONE ", sim.stat_line())
	get_tree().quit()
