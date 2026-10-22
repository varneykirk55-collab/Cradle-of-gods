extends Node3D
## Entry point: builds the environment, terrain, water, simulation, camera,
## powers, God Hand and HUD; handles global hotkeys and starts the automated
## test / screenshot modes (pass `-- --autotest` or `-- --shots`), which live
## in scripts/autotest.gd and scripts/shots.gd.

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const SPEED_NAMES := ["paused", "1x", "2x", "4x"]

var terrain: Terrain
var sim: WorldSim
var rig: CameraRig
var powers: Powers
var hud: Hud
var hand: GodHand
var speed_idx := 1
var world_seed := 0
var args := PackedStringArray()

func _ready() -> void:
	args = OS.get_cmdline_user_args()
	world_seed = randi() % 100000
	for a in args:
		if a.begins_with("--seed="):
			world_seed = int(a.substr(7))
	if "--autotest" in args or "--shots" in args or "--demo" in args:
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
	sim.cam = rig.cam
	powers = Powers.new()
	add_child(powers)
	powers.setup(sim, terrain, rig)
	hand = GodHand.new()
	hand.name = "GodHand"
	add_child(hand)
	hand.setup(sim, terrain, rig, powers)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, sim, powers, hand)
	if "--autotest" in args:
		hud.splash.visible = false
		var at := AutoTest.new()
		add_child(at)
		at.run(self)
	elif "--shots" in args or "--demo" in args:
		var sh := Shots.new()
		add_child(sh)
		sh.run(self)

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
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	# light aerial perspective for the wider ocean world, and soft glow on
	# emissive things (holy orbs, the hand's aura, fire, meteors)
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.83, 0.93)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_blur = 1.5
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
	float edge = clamp(length(wpos.xz) / 210.0, 0.0, 1.0);
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
	pm.size = Vector2(900, 900)
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
	advance(dt)

## Real time -> simulation time through the speed control.
func advance(dt: float) -> void:
	sim.cam_pos = rig.cam.global_position
	sim.update(dt * SPEEDS[speed_idx])

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo: return
	if hud.splash_visible():
		hud.hide_splash()
		return
	var k: int = e.keycode
	if k >= KEY_1 and k <= KEY_9:
		powers.select(k - KEY_1)
	elif k == KEY_0:
		powers.select(9)
	elif k == KEY_ESCAPE or k == KEY_QUOTELEFT:
		if powers.current >= 0: powers.select(powers.current)
	elif k == KEY_B:
		powers.toggle_land_mode()
	elif k == KEY_C:
		powers.cycle_life()
	elif k == KEY_V:
		hud.set_faith_overlay(not sim.show_faith)
	elif k == KEY_T:
		hud.toggle_tribes()
	elif k == KEY_P:
		hud.set_sandbox(not sim.religion.sandbox)
	elif k == KEY_SPACE:
		set_speed(1 if speed_idx == 0 else 0)
	elif k == KEY_EQUAL or k == KEY_KP_ADD or k == KEY_PERIOD:
		set_speed(mini(speed_idx + 1, 3))
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT or k == KEY_COMMA:
		set_speed(maxi(speed_idx - 1, 0))
	elif k == KEY_BRACKETLEFT:
		powers.set_brush(powers.brush - 1.0)
	elif k == KEY_BRACKETRIGHT:
		powers.set_brush(powers.brush + 1.0)
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
			hud.show_tribe(tr[idx])
	elif k == KEY_F12:
		save_shot("manual_%d" % Time.get_ticks_msec())

func save_shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
	img.save_png(path)
	print("SCREENSHOT ", path)

