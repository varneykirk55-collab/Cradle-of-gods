class_name GodHand
extends Node3D
## The player's divine hand: a skinned, animated 3D right hand that follows
## the mouse over the world.
##   * Hand tool (no power selected): left-press on a villager, animal, tree,
##     rock or bush grabs it; carry it anywhere; release slowly to set it down
##     gently (the hand lowers it to the nearest valid ground), or flick the
##     mouse and release to throw it. Left-drag on empty ground pulls the world
##     (pans the camera, Black & White style). A short click on a building
##     opens that settlement's panel.
##   * With a power selected the hand becomes the casting hand (palm down,
##     fingers spread, glowing in the power's colour) and pulses on each cast.
## Fingers blend between poses (relaxed, open, grip, claw, point, cast) and
## carried things swing like a pendulum from the fist.

signal hover_changed(text: String)
signal settlement_clicked(tribe)
## "grab", "place" or "throw", with what is held ("villager", "animal", "prop").
signal hand_event(kind: String, pos: Vector3, what: String)

enum H { IDLE, GRAB_DOWN, HOLD, PLACE_DOWN, RELEASE, PAN, CLICK }

const THROW_MIN := 5.5
const PALM_LOCAL := Vector3(0.0, -0.06, -0.24)   # palm centre in the model's space
const BUILDING_H := {"hall": 3.0, "hut": 2.0, "house": 2.8, "shrine": 2.2, "temple": 4.3}
const THROW_MAX := 42.0
const FINGERS := ["index", "middle", "ring", "pinky"]
# curl angles per finger segment (positive = toward the palm) + sideways spread
const POSES := {
	"relaxed": {"f": [0.28, 0.32, 0.22], "spread": 0.03, "thumb": [0.15, 0.1, 0.1], "thumb_swing": 0.1},
	"open": {"f": [0.02, 0.03, 0.02], "spread": 0.12, "thumb": [0.0, 0.0, 0.0], "thumb_swing": -0.15},
	"grip": {"f": [1.25, 1.35, 0.95], "spread": 0.0, "thumb": [0.55, 0.45, 0.4], "thumb_swing": 0.65},
	"claw": {"f": [0.75, 0.85, 0.55], "spread": 0.08, "thumb": [0.4, 0.3, 0.3], "thumb_swing": 0.35},
	"point": {"f": [1.45, 1.55, 1.05], "spread": 0.0, "thumb": [0.5, 0.5, 0.4], "thumb_swing": 0.6},
	"cast": {"f": [-0.05, 0.0, 0.0], "spread": 0.2, "thumb": [-0.1, 0.0, 0.0], "thumb_swing": -0.3},
}

var sim: WorldSim
var terrain: Terrain
var rig: CameraRig
var powers: Powers
var model: Node3D
var skel: Skeleton3D
var bones := {}
var rest := {}
var mats: Array = []
var shadow: MeshInstance3D
var ring: MeshInstance3D
var ring_mat := StandardMaterial3D.new()
var reticle: MeshInstance3D

var state := H.IDLE
var pose_name := "relaxed"
var cur := {}            # blended finger values
var hand_scale := 2.0
var ground = null        # Vector3 under the pointer
var hover = null         # {"kind", "obj", "pos"}
var held = null          # {"kind", "obj"}
var hand_pos := Vector3.ZERO
var hand_vel := Vector3.ZERO
var _hist: Array = []
var _state_t := 0.0
var _swing := Vector3.ZERO
var _swing_v := Vector3.ZERO
var _press_screen := Vector2.ZERO
var _pan_anchor := Vector3.ZERO
var _place_target := Vector3.ZERO
var _pulse := 0.0
var _hover_text := ""
var _wiggle := 0.0
var virtual_pointer = null   # tests: world point used instead of the mouse
var enabled := true
var stats := {"grabs": 0, "throws": 0, "places": 0, "pans": 0, "clicks": 0, "gifts": 0}

func setup(p_sim: WorldSim, p_terrain: Terrain, p_rig: CameraRig, p_powers: Powers) -> void:
	sim = p_sim
	terrain = p_terrain
	rig = p_rig
	powers = p_powers
	model = load("res://assets/models/god_hand.glb").instantiate()
	add_child(model)
	skel = _find_skel(model)
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		bones[n] = i
		rest[n] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
	_setup_materials(model)
	for k in ["f0", "f1", "f2", "spread", "t0", "t1", "t2", "tswing"]:
		cur[k] = 0.0
	# soft blob shadow straight below the hand for depth perception
	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = Assets.soft_texture()
	sm.albedo_color = Color(0, 0, 0, 0.45)
	q.material = sm
	shadow.mesh = q
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	# hover highlight ring + small aim reticle
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 4
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.no_depth_test = true
	tm.material = ring_mat
	ring = MeshInstance3D.new()
	ring.mesh = tm
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	reticle = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.16
	rm.outer_radius = 0.24
	rm.rings = 16
	rm.ring_segments = 3
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.no_depth_test = true
	rmat.albedo_color = Color(1, 0.95, 0.75, 0.7)
	rm.material = rmat
	reticle.mesh = rm
	reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(reticle)
	powers.cast_done.connect(func(_id, _p): _pulse = 1.0)
	powers.power_changed.connect(func(_i): if held != null: _drop_now())

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r: return r
	return null

const SKIN_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.6;
uniform float emission_base = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float rim_strength = 0.3;
uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float glow = 0.0;
uniform float fade_start = 0.22;
uniform float fade_end = 0.62;
varying float along;
void vertex() {
	along = VERTEX.z;
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = rim_color.rgb * fres * rim_strength + glow_color.rgb * glow * (0.25 + fres * 1.2) + albedo.rgb * emission_base;
	ALPHA = 1.0 - smoothstep(fade_start, fade_end, along);
}
"""

func _setup_materials(n: Node) -> void:
	var sh := Shader.new()
	sh.code = SKIN_SHADER
	for mi in _meshes(n):
		for s in mi.mesh.get_surface_count():
			var base: Material = mi.mesh.surface_get_material(s)
			var m := ShaderMaterial.new()
			m.shader = sh
			if base is StandardMaterial3D:
				var b := base as StandardMaterial3D
				var c := b.albedo_color
				if b.resource_name == "HandSkin": c = Color(0.78, 0.52, 0.38)   # warm, slightly tanned divine skin
				m.set_shader_parameter("albedo", c)
				m.set_shader_parameter("metallic", b.metallic)
				m.set_shader_parameter("roughness", b.roughness)
				if b.emission_enabled:
					m.set_shader_parameter("emission_base", 1.2)
			mi.set_surface_override_material(s, m)
			mats.append(m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if not enabled: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if powers.current >= 0: return
		if e.pressed: press(e.position)
		else: release()

func _input(e: InputEvent) -> void:
	# a release over the UI must still drop what we hold
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		if state in [H.HOLD, H.PAN, H.CLICK, H.GRAB_DOWN] and get_viewport().gui_get_hovered_control() != null:
			release()

func press(screen := Vector2.ZERO) -> void:
	_press_screen = screen
	if state == H.HOLD or state == H.GRAB_DOWN: return
	if hover != null and hover["kind"] in ["villager", "animal", "res"]:
		held = hover
		state = H.GRAB_DOWN
		_state_t = 0.0
		return
	if ground != null:
		_pan_anchor = ground
		state = H.CLICK
		_state_t = 0.0

func release() -> void:
	match state:
		H.GRAB_DOWN:
			_attach()       # quick click: lift it and set it straight back down
			if state == H.HOLD and not _begin_place():
				_let_go(Vector3.ZERO)
		H.HOLD:
			var v := hand_vel
			if v.length() > THROW_MIN:
				_throw(v)
			elif not _begin_place():
				_refuse_t = 2.0     # nowhere safe to set it down: keep holding
		H.CLICK:
			if hover != null and hover["kind"] == "building":
				stats["clicks"] += 1
				settlement_clicked.emit(hover["obj"].tribe)
			state = H.IDLE
		H.PAN:
			state = H.IDLE

# ------------------------------------------------------------------ grabbing
func _attach() -> void:
	if held == null: return
	match held["kind"]:
		"villager", "animal":
			var o = held["obj"]
			if o.dead:
				held = null
				state = H.IDLE
				return
			o.grab()
		"res":
			var r = held["obj"]
			if not r.alive:
				held = null
				state = H.IDLE
				return
			held = {"kind": "prop", "obj": sim.make_prop(r)}
	stats["grabs"] += 1
	hand_event.emit("grab", hand_pos, held["kind"])
	state = H.HOLD
	_swing = Vector3.ZERO
	_swing_v = Vector3.ZERO

func _held_node() -> Node3D:
	if held == null: return null
	return held["obj"] as Node3D

func _throw(v: Vector3) -> void:
	if held != null: hand_event.emit("throw", hand_pos, held["kind"])
	v = v * 1.15 + Vector3(0, 2.5, 0)
	if v.length() > THROW_MAX: v = v.normalized() * THROW_MAX
	_let_go(v)
	stats["throws"] += 1
	if held_kind_was == "villager":
		sim.religion.witness(hand_pos, 20.0, "harm", 3.0)
	held_kind_was = ""

var held_kind_was := ""
var _refuse_t := 0.0

func _let_go(v: Vector3) -> void:
	if held == null:
		state = H.IDLE
		return
	held_kind_was = held["kind"]
	match held["kind"]:
		"villager", "animal":
			var o = held["obj"]
			if not o.dead:
				o.rotation.x = 0.0
				o.rotation.z = 0.0
				o.throw(v)
		"prop":
			sim.throw_prop(held["obj"], v)
	held = null
	state = H.RELEASE
	_state_t = 0.0

## Collision-aware placement: nearest walkable, unbuilt ground under the hand.
## Returns false (and keeps holding) when a land creature has no safe ground nearby.
func _begin_place() -> bool:
	if held == null:
		state = H.IDLE
		return true
	var p: Vector3 = ground if ground != null else hand_pos
	var spot = p
	if held["kind"] in ["villager", "animal"] and not (held["kind"] == "animal" and held["obj"].species == "bird"):
		var w = sim.nav.nearest_walkable(p, 5)
		if w == null:
			return false
		spot = Vector3(w.x + randf_range(-0.2, 0.2), 0, w.z + randf_range(-0.2, 0.2))
		spot = _out_of_buildings(spot)
	spot.y = maxf(terrain.height_at(spot.x, spot.z), Terrain.SEA - 0.3)
	_place_target = spot
	state = H.PLACE_DOWN
	_state_t = 0.0
	return true

func _out_of_buildings(p: Vector3) -> Vector3:
	for t in sim.tribes:
		for b in t.buildings:
			var d := Vector2(p.x - b.pos.x, p.z - b.pos.z)
			var r: float = sim.footprint(b.type) + 0.5
			if d.length() < r:
				var dir := d.normalized() if d.length() > 0.01 else Vector2(1, 0)
				p = Vector3(b.pos.x + dir.x * (r + 0.2), p.y, b.pos.z + dir.y * (r + 0.2))
	return p

func _drop_now() -> void:
	if state == H.HOLD or state == H.GRAB_DOWN:
		if state == H.GRAB_DOWN: _attach()
		_let_go(Vector3.ZERO)

# ------------------------------------------------------------------ per-frame
func _pointer_ray() -> Array:
	var cam := rig.cam
	if virtual_pointer != null:
		var from := cam.global_position
		return [from, ((virtual_pointer as Vector3) - from).normalized()]
	var mp := get_viewport().get_mouse_position()
	return [cam.project_ray_origin(mp), cam.project_ray_normal(mp)]

func _process(dt: float) -> void:
	if dt <= 0.0: dt = 1.0 / 60.0
	var headless := DisplayServer.get_name() == "headless"
	var over_ui := not headless and virtual_pointer == null and get_viewport().gui_get_hovered_control() != null
	if not headless and virtual_pointer == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if over_ui or not enabled else Input.MOUSE_MODE_HIDDEN
	hand_scale = clampf(rig._dist * 0.08, 2.0, 10.0)
	var ray := _pointer_ray()
	if virtual_pointer != null:
		ground = virtual_pointer
	elif not headless:
		ground = powers.pick(get_viewport().get_mouse_position())
	_update_hover(ray, over_ui)
	_state_t += dt
	var cast_mode := powers.current >= 0
	var target_h := 0.6 * hand_scale
	var target_pos: Vector3 = ground if ground != null else hand_pos
	match state:
		H.IDLE:
			pose_name = "cast" if cast_mode else ("open" if hover != null and hover["kind"] != "building" else ("point" if hover != null else "relaxed"))
			if hover != null and not cast_mode:
				if hover["kind"] == "building":
					target_h = BUILDING_H[hover["obj"].type] + 0.5 * hand_scale
				else:
					target_h = 0.22 * hand_scale + _hover_top(hover)
		H.CLICK:
			pose_name = "claw"
			target_h = 0.35 * hand_scale
			if virtual_pointer == null and not headless and get_viewport().get_mouse_position().distance_to(_press_screen) > 7.0:
				state = H.PAN
				stats["pans"] += 1
		H.PAN:
			pose_name = "claw"
			target_h = 0.35 * hand_scale
			_do_pan(ray)
			target_pos = _pan_anchor
		H.GRAB_DOWN:
			pose_name = "open" if _state_t < 0.08 else "grip"
			if held == null or not _held_valid():
				held = null
				state = H.IDLE
			else:
				target_pos = _grab_point(held)
				target_h = 0.12 * hand_scale
				if _state_t > 0.17:
					_attach()
		H.HOLD:
			pose_name = "grip"
			target_h = 1.0 * hand_scale + _hang_len()
			if held == null or not _held_valid():
				held = null
				state = H.IDLE
		H.PLACE_DOWN:
			pose_name = "grip"
			target_pos = _place_target
			target_h = _hang_len() + 0.14 * hand_scale + 0.05
			var node := _held_node()
			if node == null:
				state = H.IDLE
			elif _state_t > 1.2 or (_state_t > 0.1 and node.global_position.y <= _place_target.y + 0.2):
				stats["places"] += 1
				hand_event.emit("place", node.global_position, held["kind"])
				_let_go(Vector3.ZERO)
		H.RELEASE:
			pose_name = "open"
			if _state_t > 0.3: state = H.IDLE
	# smooth, slightly springy follow
	var want := target_pos + Vector3(0, target_h, 0)
	var prev := hand_pos
	var k := 1.0 - exp(-dt * (22.0 if state in [H.GRAB_DOWN, H.PLACE_DOWN] else 16.0))
	if virtual_pointer != null and state == H.HOLD and _hist.is_empty():
		hand_pos = want
	hand_pos = hand_pos.lerp(want, k)
	var inst_v := (hand_pos - prev) / dt
	_hist.append(inst_v)
	if _hist.size() > 5: _hist.pop_front()
	hand_vel = Vector3.ZERO
	for hv in _hist: hand_vel += hv
	hand_vel /= _hist.size()
	_place_hand(dt)
	_update_held(dt)
	_update_fingers(dt)
	_update_glow(dt, cast_mode)
	model.visible = not over_ui and enabled
	shadow.visible = model.visible and ground != null
	reticle.visible = model.visible and ground != null and not cast_mode and state != H.HOLD
	if ground != null:
		var gy := maxf(terrain.height_at(hand_pos.x, hand_pos.z), Terrain.SEA)
		shadow.global_position = Vector3(hand_pos.x, gy + 0.08, hand_pos.z)
		var sz := hand_scale * (0.9 + clampf((hand_pos.y - gy) * 0.06, 0.0, 0.8))
		shadow.scale = Vector3(sz, 1, sz * 1.3)
		reticle.global_position = (ground as Vector3) + Vector3(0, 0.12, 0)
		reticle.scale = Vector3.ONE * clampf(hand_scale * 0.5, 0.6, 2.5)

func _held_valid() -> bool:
	if held == null: return false
	if held["obj"] is Object and not is_instance_valid(held["obj"]): return false
	match held["kind"]:
		"villager", "animal": return not held["obj"].dead
		"res": return held["obj"].alive
		"prop": return is_instance_valid(held["obj"])
	return false

func _hover_top(h: Dictionary) -> float:
	match h["kind"]:
		"villager": return 1.1
		"animal": return 0.9 * h["obj"].spec["scale"]
		"res": return 1.5 if h["obj"].type == WorldSim.RES_TREE else 0.6
	return 0.0

## Where the fingers close around a thing.
func _grab_point(h: Dictionary) -> Vector3:
	var o = h["obj"]
	match h["kind"]:
		"villager": return o.position + Vector3(0, 0.9 * o.grow, 0)
		"animal": return o.position + Vector3(0, 0.7 * o.spec["scale"] * o.grow, 0)
		"res": return o.pos + Vector3(0, 1.0 * o.scale if o.type == WorldSim.RES_TREE else 0.4, 0)
	return hand_pos

## Distance from the fist down to the bottom of what it carries.
func _hang_len() -> float:
	if held == null: return 0.5
	match held["kind"]:
		"villager": return 1.2 * held["obj"].grow
		"animal": return 0.95 * held["obj"].spec["scale"] * held["obj"].grow
		"prop":
			return 1.0 * held["obj"].scale.y if held["obj"].get_meta("type") == WorldSim.RES_TREE else 0.4
	return 0.5

func _grip_world() -> Vector3:
	# the fist closes just under the palm
	return hand_pos - Vector3(0, 0.12 * hand_scale, 0)

## Camera-relative pose (as in Black & White): the back of the hand faces the
## viewer, fingers reach up-screen into the world, the forearm trails toward
## the bottom of the screen and fades out. Motion adds roll / lean.
func _place_hand(dt: float) -> void:
	var cb := rig.cam.global_transform.basis.orthonormalized()
	var right := cb.x
	var up_s := cb.y
	var lateral := hand_vel.dot(right)
	var vertical := hand_vel.dot(up_s)
	var lean := 0.3 + clampf(vertical * 0.01, -0.2, 0.2)
	var roll := clampf(-lateral * 0.02, -0.5, 0.5)
	# reaching down / carrying: turn palm-down so what we hold dangles in view below the fist
	if state == H.GRAB_DOWN: lean = 0.95
	if state == H.HOLD or state == H.PLACE_DOWN: lean = 0.82 + clampf(vertical * 0.01, -0.2, 0.2)
	if state == H.PAN or state == H.CLICK: lean += 0.25
	if pose_name == "cast": lean += 0.2 + _pulse * 0.3
	var b := cb * Basis(Vector3.RIGHT, PI * 0.5 - lean) * Basis(Vector3.BACK, roll)
	var cur_b := model.global_transform.basis.orthonormalized()
	var nb := Basis(cur_b.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), minf(1.0, dt * 12.0)))
	# hand_pos is the palm: place the model so its palm lands exactly there
	var off := nb * (PALM_LOCAL * hand_scale)
	model.global_transform = Transform3D(nb.scaled(Vector3.ONE * hand_scale), hand_pos - off)

func _update_held(dt: float) -> void:
	var node := _held_node()
	if node == null or not (state in [H.HOLD, H.GRAB_DOWN, H.PLACE_DOWN]) or state == H.GRAB_DOWN:
		return
	# pendulum: the carried thing lags behind the hand's acceleration
	var acc := Vector3(hand_vel.x, 0, hand_vel.z)
	_swing_v += (-acc * 0.012 - _swing * 9.0) * dt * 6.0
	_swing_v *= exp(-dt * 3.0)
	_swing += _swing_v * dt
	_swing = _swing.limit_length(0.7)
	var grip := _grip_world()
	var hang := _hang_len()
	var tilt := Basis(Vector3(_swing.z, 0, -_swing.x).normalized() if _swing.length() > 0.001 else Vector3.RIGHT, _swing.length())
	var base := grip - tilt * Vector3(0, hang, 0)
	node.global_position = base
	var yaw: float = model.global_rotation.y
	node.rotation = Vector3(0, lerp_angle(node.rotation.y, yaw, minf(1.0, dt * 4.0)), 0)
	node.rotation.x = -_swing.z * 0.8
	node.rotation.z = _swing.x * 0.8

func _do_pan(ray: Array) -> void:
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if absf(dir.y) < 0.02: return
	var t := (_pan_anchor.y - from.y) / dir.y
	if t <= 0.0: return
	var hit := from + dir * t
	var delta := _pan_anchor - hit
	delta.y = 0.0
	if delta.length() > 30.0: return
	rig.focus += delta
	rig.focus.x = clampf(rig.focus.x, -rig.BOUND, rig.BOUND)
	rig.focus.z = clampf(rig.focus.z, -rig.BOUND, rig.BOUND)
	rig._f = rig.focus
	rig._apply(0.0)

# ------------------------------------------------------------------ hover
func _update_hover(ray: Array, over_ui: bool) -> void:
	var nh = null
	if not over_ui and powers.current < 0 and state in [H.IDLE, H.CLICK] and ground != null:
		nh = _find_hover(ray)
	if state == H.HOLD and held != null:
		nh = null
	hover = nh
	var text := ""
	_refuse_t = maxf(0.0, _refuse_t - get_process_delta_time())
	if state == H.HOLD and held != null and _refuse_t > 0.0:
		text = "No safe ground here for %s - move over land to set them down, or flick to throw" % _held_name()
	elif state == H.HOLD and held != null:
		text = "Carrying %s - release slowly to set down, flick & release to throw" % _held_name()
	elif hover != null:
		match hover["kind"]:
			"villager": text = hover["obj"].describe() + "\n[Left drag] pick up"
			"animal": text = hover["obj"].describe() + "\n[Left drag] pick up"
			"res": text = ["Tree", "Rock", "Berry bush"][hover["obj"].type] + "\n[Left drag] uproot and carry - drop it in a village as a gift"
			"building":
				var b = hover["obj"]
				text = "%s %s%s\n[Click] settlement info" % [b.tribe.name, b.type.capitalize(), "" if b.built else " (under construction)"]
	if text != _hover_text:
		_hover_text = text
		hover_changed.emit(text)
	if hover != null and hover["kind"] != "building":
		ring.visible = true
		var c := Color(0.6, 1.0, 0.6, 0.9)
		var p: Vector3
		var r := 0.7
		match hover["kind"]:
			"villager":
				p = hover["obj"].position
				c = Color(0.75, 0.4, 1.0, 0.95) if hover["obj"].heretic else (Color(1, 1, 1, 0.95) if hover["obj"].priest else Color(1.0, 0.9, 0.45, 0.95))
			"animal":
				p = hover["obj"].position
				r = 0.9 * hover["obj"].spec["scale"]
				c = Color(0.6, 1.0, 0.6, 0.95)
			"res":
				p = hover["obj"].pos
				r = 1.0
				c = Color(0.7, 0.95, 1.0, 0.9)
		ring.global_position = Vector3(p.x, maxf(p.y, Terrain.SEA) + 0.1, p.z)
		ring.scale = Vector3(r, 1, r)
		ring_mat.albedo_color = c
	elif hover != null:
		ring.visible = true
		var b = hover["obj"]
		ring.global_position = b.pos + Vector3(0, 0.15, 0)
		var rr: float = sim.footprint(b.type) + 0.6
		ring.scale = Vector3(rr, 1, rr)
		ring_mat.albedo_color = Color(b.tribe.color, 0.9)
	else:
		ring.visible = false

func _held_name() -> String:
	if held == null: return ""
	match held["kind"]:
		"villager": return held["obj"].vname
		"animal": return "a " + held["obj"].spec["name"].to_lower()
		"prop": return ["a tree", "a boulder", "a berry bush"][held["obj"].get_meta("type")]
	return "something"

func _find_hover(ray: Array) -> Variant:
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var tol := 0.55 + rig._dist * 0.012
	var best = null
	var bs := 1.0
	for v in sim.villagers:
		if v.dead or v.is_busy_with_god(): continue
		var s := _ray_dist(from, dir, v.position + Vector3(0, 0.6, 0)) / tol
		if s < bs:
			bs = s
			best = {"kind": "villager", "obj": v}
	for a in sim.eco.animals:
		if a.dead or a.is_busy_with_god(): continue
		var s: float = _ray_dist(from, dir, a.position + Vector3(0, 0.4 * a.spec["scale"], 0)) / (tol * (0.8 + a.spec["scale"] * 0.3))
		if s < bs:
			bs = s
			best = {"kind": "animal", "obj": a}
	if best != null: return best
	var g: Vector3 = ground
	var rb = null
	var rd := 1.4 + rig._dist * 0.006
	for r in sim.resources_in_radius(g, 2.5):
		if r.burning or r.scale < r.target_scale * 0.6: continue
		var d := Vector2(r.pos.x - g.x, r.pos.z - g.z).length()
		if d < rd:
			rd = d
			rb = r
	if rb != null: return {"kind": "res", "obj": rb}
	for t in sim.tribes:
		for b in t.buildings:
			if Vector2(b.pos.x - g.x, b.pos.z - g.z).length() < sim.footprint(b.type) + 0.3:
				return {"kind": "building", "obj": b}
	return null

static func _ray_dist(o: Vector3, d: Vector3, p: Vector3) -> float:
	var t := (p - o).dot(d)
	if t < 0.0: return INF
	return (p - (o + d * t)).length()

# ------------------------------------------------------------------ fingers
func _update_fingers(dt: float) -> void:
	var p: Dictionary = POSES[pose_name]
	var k := 1.0 - exp(-dt * 14.0)
	_wiggle += dt
	var w := sin(_wiggle * 2.2) * 0.04 if pose_name in ["relaxed", "open", "cast"] else 0.0
	var pf: Array = p["f"]
	var pt: Array = p["thumb"]
	cur["f0"] = lerpf(cur["f0"], pf[0] - _pulse * 0.25, k)
	cur["f1"] = lerpf(cur["f1"], pf[1] - _pulse * 0.2, k)
	cur["f2"] = lerpf(cur["f2"], pf[2], k)
	cur["spread"] = lerpf(cur["spread"], p["spread"] + _pulse * 0.12, k)
	cur["t0"] = lerpf(cur["t0"], pt[0], k)
	cur["t1"] = lerpf(cur["t1"], pt[1], k)
	cur["t2"] = lerpf(cur["t2"], pt[2], k)
	cur["tswing"] = lerpf(cur["tswing"], p["thumb_swing"], k)
	var point := pose_name == "point"
	for fi in FINGERS.size():
		var f: String = FINGERS[fi]
		var phase := float(fi) * 0.7
		var spread_dir: float = [-1.0, -0.3, 0.4, 1.0][fi]
		for s in 3:
			var c: float = cur["f%d" % s] + w * sin(_wiggle * 3.0 + phase + s)
			if point and f == "index": c = 0.05 * s
			var q := Quaternion(Vector3.RIGHT, -c)
			if s == 0:
				q = Quaternion(Vector3.FORWARD, cur["spread"] * spread_dir) * q
			_set_bone("%s_%d" % [f, s + 1], q)
	_set_bone("thumb_1", Quaternion(Vector3.FORWARD, -cur["tswing"]) * Quaternion(Vector3.RIGHT, -cur["t0"]))
	_set_bone("thumb_2", Quaternion(Vector3.RIGHT, -cur["t1"]))
	_set_bone("thumb_3", Quaternion(Vector3.RIGHT, -cur["t2"]))

func _set_bone(n: String, q: Quaternion) -> void:
	if not bones.has(n): return
	skel.set_bone_pose_rotation(bones[n], rest[n] * q)

func _update_glow(dt: float, cast_mode: bool) -> void:
	_pulse = maxf(0.0, _pulse - dt * 3.0)
	var g := 0.0
	var col := Color(1.0, 0.9, 0.6)
	if cast_mode:
		col = Powers.LIST[powers.current]["color"]
		g = 0.35 + _pulse * 1.2 + sin(_wiggle * 4.0) * 0.08
	elif hover != null:
		g = 0.25
	elif state == H.HOLD:
		g = 0.15
	for m in mats:
		m.set_shader_parameter("glow", g)
		m.set_shader_parameter("glow_color", col)
