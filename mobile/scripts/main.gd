extends Node3D
## Entry point (mobile web build): builds the environment, terrain, water,
## simulation, camera, powers, God Hand, HUD and touch support. There are no
## keyboard shortcuts; every action has an on-screen control (see hud.gd and
## touch_support.gd). A world seed can be passed in the page URL: index.html?seed=1234

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const SPEED_NAMES := ["paused", "1x", "2x", "4x"]

var terrain: Terrain
var sim: WorldSim
var rig: CameraRig
var powers: Powers
var hud: Hud
var hand: GodHand
var audio: AudioDirector
var speed_idx := 1
var world_seed := 0

func _ready() -> void:
	world_seed = randi() % 100000
	if OS.has_feature("web"):
		# index.html?seed=1234 reproduces a world
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('seed')")
		if q != null and str(q).is_valid_int():
			world_seed = int(str(q))
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
	hand.hand_event.connect(sim.on_hand_event)   # villagers stop and stare at the hand
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, sim, powers, hand)
	var touch := TouchSupport.new()
	touch.name = "TouchSupport"
	add_child(touch)
	touch.setup(rig, hud)

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_bottom_color = Color(0.62, 0.74, 0.84)   # below the horizon reads as distant sea haze
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
	env.glow_enabled = false   # MOBILE: glow is a full-screen pass; off for phones
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
	sun.directional_shadow_max_distance = 110.0   # MOBILE: desktop 160
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # MOBILE: one cascade (desktop 2)
	add_child(sun)

## Sea surface (shaders/water.gdshader) reads the live terrain heightmap for
## depth, so every coast gets shallows, shelf, deep water and foam.
func _setup_water() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("height_tex", terrain.height_tex)
	m.set_shader_parameter("wave_normal", load("res://assets/textures/water_normal.png"))
	m.set_shader_parameter("detail_tex", load("res://assets/textures/terrain_detail.png"))
	m.set_shader_parameter("half_size", Terrain.HALF)
	m.set_shader_parameter("sea", Terrain.SEA)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1700, 1700)
	pm.subdivide_width = 120
	pm.subdivide_depth = 120
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
	fm.size = Vector2(1700, 1700)
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
	advance(dt)

## Real time -> simulation time through the speed control.
func advance(dt: float) -> void:
	sim.cam_pos = rig.cam.global_position
	sim.update(dt * SPEEDS[speed_idx])

## Save / load the single save slot (see save_game.gd); results show as a toast.
func save_game(path := SaveGame.DEFAULT_PATH) -> Dictionary:
	var r := SaveGame.save(self, path)
	print("SAVE ", r)
	if hud:
		hud.show_toast(r["msg"])
		if r["ok"]: hud.refresh_save_info()
	return r

func load_game(path := SaveGame.DEFAULT_PATH) -> Dictionary:
	var r := SaveGame.load_into(self, path)
	print("LOAD ", r)
	if hud: hud.show_toast(r["msg"])
	if r["ok"]: sim.log_event(r["msg"], Color(0.85, 0.92, 1.0))
	return r
