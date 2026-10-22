extends Node3D
func mk(pos: Vector3, ramp: Array, gravity: Vector3, curve: bool, vel: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 8
	p.lifetime = 2.2
	add_child(p)
	p.global_position = pos
	p.mesh = FX._quad(1.5, FX.pmat(Color(1, 1, 1)))
	p.direction = Vector3.UP
	p.gravity = gravity
	p.initial_velocity_min = vel
	p.initial_velocity_max = vel
	p.color_ramp = FX._ramp(ramp)
	if curve:
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(1, 1))
		p.scale_amount_curve = c
	p.emitting = true
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 3, 14); cam.look_at(Vector3(0, 2, 0))
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.5, 0.75, 0.95); add_child(env)
	var g := [Color(0.5, 0.47, 0.45, 0.0), Color(0.5, 0.47, 0.45, 0.35), Color(0.65, 0.65, 0.65, 0.0)]
	mk(Vector3(-6, 0, 0), g, Vector3(0.4, 1.2, 0), false, 0.8)                     # A: as in game
	mk(Vector3(-2, 0, 0), [Color(0.5, 0.47, 0.45, 0.3), Color(0.5, 0.47, 0.45, 0.35), Color(0.65, 0.65, 0.65, 0.0)], Vector3(0.4, 1.2, 0), false, 0.8)  # B: alpha start .3
	mk(Vector3(2, 0, 0), g, Vector3(0, -9.8, 0), false, 3.0)                    # C: default-ish gravity
	mk(Vector3(6, 0, 0), g, Vector3(0.4, 1.2, 0), true, 0.8)                     # D: with scale curve
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/fxprobe2.png"))
	get_tree().quit()
