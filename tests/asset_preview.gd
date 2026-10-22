extends Node3D
## Renders every v2 model for visual inspection: `godot --path . res://tests/asset_preview.tscn`
## Saves screenshots/preview_*.png then quits.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.6, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	var x := -6.0
	for m in ["deer", "wolf", "rabbit", "bird", "villager_rig"]:
		var inst: Node3D = load("res://assets/models/%s.glb" % m).instantiate()
		add_child(inst)
		inst.position = Vector3(x, 0.0 if m != "bird" else 0.6, 0)
		inst.scale = Vector3.ONE * (3.0 if m in ["rabbit", "bird"] else 1.5)
		inst.rotation.y = 0.6
		x += 3.0
	var hand: Node3D = load("res://assets/models/god_hand.glb").instantiate()
	add_child(hand)
	hand.position = Vector3(0, 3.5, -2)
	hand.scale = Vector3.ONE * 3.0
	cam.position = Vector3(0, 4, 9)
	cam.look_at(Vector3(0, 1.2, 0))
	await _shot("preview_models")
	for m in ["shrine", "temple", "hut_b", "house_b"]:
		pass
	var bx := -6.0
	for c in get_children():
		if c is Node3D and c != cam and c != sun and c != ground and c != env:
			c.visible = false
	for m in ["shrine", "temple", "hut_b", "house_b", "hut", "house"]:
		var inst: Node3D = load("res://assets/models/%s.glb" % m).instantiate()
		add_child(inst)
		inst.position = Vector3(bx, 0, 0)
		inst.rotation.y = 0.5
		bx += 2.6
	await _shot("preview_buildings")
	for c in get_children():
		if c is Node3D and c != cam and c != sun and c != ground and c != env:
			c.visible = false
	hand.visible = true
	hand.position = Vector3(0, 1.5, 0)
	hand.rotation = Vector3(0.0, 0.0, 0.0)
	cam.position = Vector3(2.5, 4.5, 4)
	cam.look_at(Vector3(0, 1.0, -1.0))
	await _shot("preview_hand_open")
	var sk: Skeleton3D = _find_skel(hand)
	for i in sk.get_bone_count():
		print("BONE ", i, " ", sk.get_bone_name(i), " rest ", sk.get_bone_rest(i).basis.get_euler())
		if sk.get_bone_name(i) != "hand":
			var rr := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(i, rr * Quaternion(Vector3.RIGHT, 0.9))
	await _shot("preview_hand_curl")
	cam.position = Vector3(-4, 1.0, -1)
	cam.look_at(Vector3(0, 1.3, -1.0))
	await _shot("preview_hand_curl_side")
	get_tree().quit()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r: return r
	return null

func _shot(name: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % name))
	print("SHOT ", name)
