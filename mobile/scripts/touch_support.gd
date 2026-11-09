class_name TouchSupport
extends CanvasLayer
## MOBILE ONLY. Touch camera gestures, a help / fullscreen button pair and a
## "turn your phone sideways" cover.
##
## One finger is handled by Godot itself (it is emulated as the left mouse
## button, which already drives the God Hand, powers and every HUD button).
## This node adds what the mouse and keyboard did for the camera:
##   two-finger drag   pan          pinch   zoom          twist   rotate

var rig: CameraRig
var hud: Hud
var _t := {}                 # finger index -> last position (viewport coords)
var _cover: ColorRect
var _fs_button: Button

func setup(p_rig: CameraRig, p_hud: Hud) -> void:
	rig = p_rig
	hud = p_hud
	layer = 5

	# --- top-centre buttons: help and fullscreen
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.offset_top = 8
	add_child(row)
	var help_b := _make_button("?")
	help_b.pressed.connect(func(): hud.toggle_help())
	row.add_child(help_b)
	_fs_button = _make_button("Full")
	_fs_button.pressed.connect(_toggle_fullscreen)
	row.add_child(_fs_button)

	# --- portrait cover
	_cover = ColorRect.new()
	_cover.color = Color(0.03, 0.04, 0.09, 0.97)
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var msg := Label.new()
	msg.text = "Turn your phone sideways\nto play Cradle of Gods"
	msg.add_theme_font_size_override("font_size", 40)
	msg.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cover.add_child(msg)
	_cover.visible = false
	add_child(_cover)

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64, 44)
	b.add_theme_font_size_override("font_size", 20)
	hud._style_button(b)
	return b

func _toggle_fullscreen() -> void:
	var w := get_window()
	if w.mode == Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	else:
		w.mode = Window.MODE_FULLSCREEN

func _process(_dt: float) -> void:
	var s := get_viewport().get_visible_rect().size
	_cover.visible = s.y > s.x

func _input(e: InputEvent) -> void:
	if rig == null: return
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			_t[st.index] = st.position
			if _t.size() == 2:
				_cancel_one_finger_action()
		else:
			_t.erase(st.index)
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if _t.size() == 2 and _t.has(sd.index):
			_gesture(sd.index, sd.position)
		_t[sd.index] = sd.position

## A second finger landed: whatever the first finger started (a grab, a pan, a
## power stroke) is released, then the pair controls the camera instead.
func _cancel_one_finger_action() -> void:
	if get_viewport().gui_get_hovered_control() != null: return   # first finger is on a button: leave it
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = _t.values()[0]
	ev.global_position = ev.position
	Input.parse_input_event(ev)

func _gesture(moved: int, new_pos: Vector2) -> void:
	var ids: Array = _t.keys()
	var a_old: Vector2 = _t[ids[0]]
	var b_old: Vector2 = _t[ids[1]]
	var a_new := new_pos if ids[0] == moved else a_old
	var b_new := new_pos if ids[1] == moved else b_old
	var mid_old := (a_old + b_old) * 0.5
	var mid_new := (a_new + b_new) * 0.5
	var len_old := a_old.distance_to(b_old)
	var len_new := a_new.distance_to(b_new)

	# pan: the ground follows the fingers
	var d := mid_new - mid_old
	var k := 0.93 * rig.dist / maxf(1.0, get_viewport().get_visible_rect().size.y)
	var fwd := Vector3(-sin(rig.yaw), 0, -cos(rig.yaw))
	var right := Vector3(cos(rig.yaw), 0, -sin(rig.yaw))
	rig.focus += (-right * d.x + fwd * d.y) * k

	# pinch zoom
	if len_old > 12.0 and len_new > 12.0:
		rig.dist = clampf(rig.dist * len_old / len_new, CameraRig.MIN_D, CameraRig.MAX_D)

	# twist rotate (clockwise fingers turn the world clockwise)
	if len_old > 60.0 and len_new > 60.0:
		var da := wrapf((b_new - a_new).angle() - (b_old - a_old).angle(), -PI, PI)
		rig.yaw -= da
