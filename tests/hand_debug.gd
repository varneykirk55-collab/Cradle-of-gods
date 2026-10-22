extends SceneTree
## Debug helper: renders the God Hand over a village. godot --path . -s res://tests/hand_debug.gd
func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.hud.splash.visible = false
	var t0 = main.sim.live_tribes()[0]
	main.rig.set_view(t0.center, 20.0, 0.9, 0.75, true)
	var sp = main.sim.nav.nearest_walkable(t0.center + Vector3(9, 0, 4), 6)
	var v = main.sim.spawn_villager(t0, sp, false)
	v._reset(60.0)
	var gp: Vector3 = v.position
	main.rig.set_view(gp, 18.0, 0.9, 0.75, true)
	main.hand.virtual_pointer = gp
	if OS.get_cmdline_user_args().has("--noskel"):
		main.hand.set_process(false)
		main.hand.model.global_transform = Transform3D(Basis().scaled(Vector3.ONE * 2.0), gp + Vector3(0, 2, 0))
	for i in 10: await process_frame
	var h = main.hand
	if OS.get_cmdline_user_args().has("--grab"):
		h.press()
		for i in 12:
			h.virtual_pointer = v.position
			await process_frame
			main.sim.update(1.0 / 30.0)
		for i in 10:
			h.virtual_pointer = gp + Vector3(i * 0.3, 0, 0)
			await process_frame
	if OS.get_cmdline_user_args().has("--nofade"):
		for m in h.mats:
			m.set_shader_parameter("fade_start", 100.0)
			m.set_shader_parameter("fade_end", 101.0)
	if OS.get_cmdline_user_args().has("--std"):
		for mi in h._meshes(h.model):
			for s in mi.mesh.get_surface_count(): mi.set_surface_override_material(s, null)
	for i in 3: await process_frame
	print("HAND pos ", h.hand_pos, " model ", h.model.global_transform, " vis ", h.model.visible, " is_vis_tree ", h.model.is_visible_in_tree(), " ground ", h.ground, " scale ", h.hand_scale)
	for mi in h._meshes(h.model):
		print("MESH ", mi.name, " aabb ", mi.get_aabb(), " skin ", mi.skin, " skel ", mi.skeleton, " gt ", mi.global_transform.origin)
	print("CAM ", main.rig.cam.global_position, " focus ", main.rig.focus)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_hand.png"))
	quit()
