extends Node3D
# Isolated FX render probe: run with xvfb to inspect particle colours over time.
func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3, 14)
	cam.look_at(Vector3(0, 2, 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.75, 0.95)
	add_child(env)
	FX.fire(self, Vector3(-4, 0, 0), 1.5)
	FX.explosion(self, Vector3(3, 0, 0), 1.0)
	for t in [0.3, 1.0, 2.0, 3.2]:
		await get_tree().create_timer(t if t == 0.3 else 0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/fxprobe_%.1f.png" % t))
	get_tree().quit()
