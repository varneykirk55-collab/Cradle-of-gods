class_name CameraRig
extends Node3D
## RTS / god camera. WASD/arrows pan, Q/E rotate, wheel or R/F zoom,
## right- or middle-mouse drag orbits, Shift = fast. Smoothed and clamped
## to the world bounds and kept above the terrain.

var cam := Camera3D.new()
var terrain: Terrain
var focus := Vector3.ZERO
var yaw := 0.7
var pitch := 0.85
var dist := 70.0
var _f := Vector3.ZERO
var _yaw := 0.7
var _pitch := 0.85
var _dist := 70.0
var dragging := false
var shake_amt := 0.0
const BOUND := 76.0
const MIN_D := 7.0
const MAX_D := 170.0

func _ready() -> void:
	cam.fov = 50.0
	cam.near = 0.2
	cam.far = 800.0
	add_child(cam)
	cam.current = true
	snap()

func snap() -> void:
	_f = focus
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_apply(0.0)

func set_view(p_focus: Vector3, p_dist: float, p_yaw: float, p_pitch: float, instant := false) -> void:
	focus = p_focus
	dist = p_dist
	yaw = p_yaw
	pitch = p_pitch
	if instant: snap()

func shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist * 0.88, MIN_D, MAX_D)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.13, MIN_D, MAX_D)
	elif e is InputEventMouseMotion and dragging:
		var mm := e as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.005, 0.25, 1.45)

func _input(e: InputEvent) -> void:
	# make sure a drag that ends over the UI still releases
	if e is InputEventMouseButton and not e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = false

func _process(dt: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
	var fast := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if Input.is_key_pressed(KEY_Q): yaw += dt * 1.6
	if Input.is_key_pressed(KEY_E): yaw -= dt * 1.6
	if Input.is_key_pressed(KEY_R): dist = clampf(dist * (1.0 - dt * 1.5), MIN_D, MAX_D)
	if Input.is_key_pressed(KEY_F): dist = clampf(dist * (1.0 + dt * 1.5), MIN_D, MAX_D)
	if mv != Vector2.ZERO:
		mv = mv.normalized() * dist * 0.9 * dt * fast
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		focus += right * mv.x - fwd * mv.y
	focus.x = clampf(focus.x, -BOUND, BOUND)
	focus.z = clampf(focus.z, -BOUND, BOUND)
	if terrain:
		focus.y = maxf(terrain.height_at(focus.x, focus.z), Terrain.SEA)
	_apply(dt)

func _apply(dt: float) -> void:
	var k := 1.0 if dt <= 0.0 else 1.0 - exp(-dt * 9.0)
	_f = _f.lerp(focus, k)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, dist, k)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	var p := _f + off
	if terrain:
		p.y = maxf(p.y, maxf(terrain.height_at(p.x, p.z), Terrain.SEA) + 1.5)
	var sh := Vector3.ZERO
	if shake_amt > 0.01:
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		shake_amt = lerpf(shake_amt, 0.0, minf(1.0, dt * 4.0)) if dt > 0.0 else 0.0
	global_position = Vector3.ZERO
	cam.global_position = p + sh
	cam.look_at(_f + sh * 0.5, Vector3.UP)
