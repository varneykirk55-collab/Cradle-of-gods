class_name Hud
extends CanvasLayer
## On-screen UI: stats, tribe list, power toolbar (generated icons + hotkeys),
## time-speed buttons, tooltip/info box, event log, help overlay, title splash.

var main
var sim: WorldSim
var powers: Powers
var stats_label: Label
var tribe_box: VBoxContainer
var info_title: Label
var info_desc: Label
var log_box: VBoxContainer
var help: PanelContainer
var splash: Control
var flash_rect: ColorRect
var power_buttons: Array = []
var speed_buttons: Array = []
var _acc := 0.0
var _hover := -1

const GOLD := Color(0.86, 0.7, 0.38)
const PANEL_BG := Color(0.05, 0.07, 0.13, 0.82)

func _panel_style(radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

func _label(text: String, size := 15, color := Color(0.95, 0.92, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l

func setup(p_main, p_sim: WorldSim, p_powers: Powers) -> void:
	main = p_main
	sim = p_sim
	powers = p_powers
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top-left stats
	var sp := _panel()
	sp.position = Vector2(12, 12)
	root.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	sv.add_child(_label("CRADLE OF GODS", 20, GOLD))
	stats_label = _label("", 15)
	sv.add_child(stats_label)

	# --- top-right tribes
	var tp := _panel()
	tp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tp.offset_left = -330
	tp.offset_right = -12
	tp.offset_top = 12
	tp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(tp)
	var tv := VBoxContainer.new()
	tp.add_child(tv)
	tv.add_child(_label("TRIBES", 17, GOLD))
	tribe_box = VBoxContainer.new()
	tribe_box.add_theme_constant_override("separation", 4)
	tv.add_child(tribe_box)

	# --- bottom toolbar
	var bar := _panel()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -12
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for i in Powers.LIST.size():
		var d: Dictionary = Powers.LIST[i]
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.icon = load(d["icon"])
		b.expand_icon = true
		b.custom_minimum_size = Vector2(68, 68)
		b.tooltip_text = "%s  [%s]\n%s" % [d["name"], d["key"], d["desc"]]
		b.add_theme_stylebox_override("normal", _btn_style(false))
		b.add_theme_stylebox_override("hover", _btn_style(false, true))
		b.add_theme_stylebox_override("pressed", _btn_style(true))
		b.add_theme_stylebox_override("hover_pressed", _btn_style(true))
		b.pressed.connect(func(): _on_power_button(i))
		b.mouse_entered.connect(_set_hover.bind(i))
		b.mouse_exited.connect(_set_hover.bind(-1))
		vb.add_child(b)
		var l := _label("%s %s" % [d["key"], d["name"].split(" ")[-1]], 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		power_buttons.append(b)
	var sep := VSeparator.new()
	hb.add_child(sep)
	var spd := VBoxContainer.new()
	hb.add_child(spd)
	spd.add_child(_label("TIME", 12, GOLD))
	var sgrid := GridContainer.new()
	sgrid.columns = 2
	spd.add_child(sgrid)
	var sg := ButtonGroup.new()
	var names := ["II", "1x", "2x", "4x"]
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = sg
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, 28)
		b.tooltip_text = ["Pause (Space)", "Normal speed", "Double speed", "Quadruple speed"][i]
		b.add_theme_stylebox_override("normal", _btn_style(false))
		b.add_theme_stylebox_override("hover", _btn_style(false, true))
		b.add_theme_stylebox_override("pressed", _btn_style(true))
		b.pressed.connect(func(): main.set_speed(i))
		sgrid.add_child(b)
		speed_buttons.append(b)

	# --- info / tooltip box above toolbar
	var ip := _panel()
	ip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ip.offset_bottom = -126
	ip.custom_minimum_size = Vector2(560, 0)
	ip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ip)
	var iv := VBoxContainer.new()
	ip.add_child(iv)
	info_title = _label("", 17, GOLD)
	info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(info_title)
	info_desc = _label("", 14)
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_desc.custom_minimum_size = Vector2(540, 0)
	iv.add_child(info_desc)

	# --- event log (bottom-left)
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.offset_left = 14
	log_box.offset_bottom = -14
	log_box.offset_top = -14
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)
	sim.event_logged.connect(_on_event)

	# --- help overlay
	help = _panel()
	help.set_anchors_preset(Control.PRESET_CENTER)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(help)
	var hv := VBoxContainer.new()
	help.add_child(hv)
	hv.add_child(_label("HOW TO PLAY", 22, GOLD))
	hv.add_child(_label(
		"You are a god watching over a young world. Tribes gather wood, stone and\n" +
		"food, build huts that become stone houses, grow, and send settlers to found\n" +
		"new villages. Nurture them or smite them.\n\n" +
		"CAMERA   WASD / Arrows: pan    Q / E: rotate    Mouse wheel or R / F: zoom\n" +
		"         Right or middle mouse drag: orbit    Shift: pan faster\n" +
		"         Tab: jump to next tribe\n" +
		"POWERS   1-7 or click an icon, then left-click (hold for land & forest)\n" +
		"         [ / ]: brush size    Esc: deselect power\n" +
		"TIME     Space: pause    - / +: slower / faster\n" +
		"OTHER    H or F1: toggle this help    F12: screenshot", 15))
	hv.add_child(_label("Press H to close", 13, GOLD))
	help.visible = false

	# --- flash overlay (lightning / meteor)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	powers.flash.connect(_on_flash)
	powers.power_changed.connect(_on_power_changed)

	# --- title splash
	splash = Control.new()
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(splash)
	var tex := TextureRect.new()
	tex.texture = load("res://assets/ui/title_splash.png")
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash.add_child(tex)
	var title := _label("CRADLE OF GODS", 84, Color(1.0, 0.93, 0.7))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.05, 0.9))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 60
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.add_child(title)
	var sub := _label("Shape the land. Shepherd the tribes. Unleash the heavens.\n\nClick or press any key to begin", 24, Color(1, 1, 1))
	sub.add_theme_constant_override("outline_size", 8)
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub.offset_bottom = -60
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.add_child(sub)
	splash.gui_input.connect(_on_splash_input)

	speed_buttons[1].button_pressed = true
	_refresh_info()
	_update_stats()

func _btn_style(pressed: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.2, 0.08, 0.95) if pressed else (Color(0.16, 0.18, 0.28, 0.95) if hover else Color(0.09, 0.11, 0.2, 0.95))
	sb.border_color = Color(1.0, 0.85, 0.4) if pressed else GOLD.darkened(0.3)
	sb.set_border_width_all(3 if pressed else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(3)
	return sb

func _set_hover(i: int) -> void:
	_hover = i
	_refresh_info()

func _on_splash_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		hide_splash()

func splash_visible() -> bool:
	return splash.visible

func hide_splash() -> void:
	if not splash.visible: return
	var tw := create_tween()
	tw.tween_property(splash, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): splash.visible = false)
	_on_event("Welcome, god. Press H for help.", GOLD)

func toggle_help() -> void:
	help.visible = not help.visible

func set_speed_button(i: int) -> void:
	speed_buttons[i].set_pressed_no_signal(true)

func _on_power_button(i: int) -> void:
	powers.select(i)

func _on_power_changed(idx: int) -> void:
	for i in power_buttons.size():
		power_buttons[i].set_pressed_no_signal(i == idx)
	_refresh_info()

func _refresh_info() -> void:
	var i := _hover if _hover >= 0 else powers.current
	if i < 0:
		info_title.text = "No power selected"
		info_desc.text = "Pick a divine power (1-7) and click the world. Right-drag to orbit, wheel to zoom."
	else:
		var d: Dictionary = Powers.LIST[i]
		info_title.text = "%s  [%s]%s" % [d["name"], d["key"], "  - selected" if i == powers.current else ""]
		info_desc.text = d["desc"] + ("  Brush: %.0f" % powers.brush if d["id"] in ["raise", "lower", "forest"] else "")

func _on_flash(strength: float) -> void:
	flash_rect.color = Color(1, 1, 1, strength)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.4)

func _on_event(text: String, color: Color) -> void:
	var l := _label(text, 14, color.lightened(0.25))
	log_box.add_child(l)
	while log_box.get_child_count() > 7:
		log_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)

func _process(dt: float) -> void:
	_acc += dt
	if _acc > 0.25:
		_acc = 0.0
		_update_stats()

func _update_stats() -> void:
	var tr := sim.live_tribes()
	var day := int(sim.time / 60.0) + 1
	stats_label.text = "Year %d   (%s)\nPopulation: %d\nTribes: %d   Buildings: %d\nTrees: %d   Fires: %d\nPower: %s" % [
		day, main.speed_name(), sim.population(), tr.size(), sim.building_count(), sim.count_type(WorldSim.RES_TREE),
		sim.fires.size(), Powers.LIST[powers.current]["name"] if powers.current >= 0 else "none"]
	var rows := tribe_box.get_children()
	for i in maxi(rows.size(), tr.size()):
		if i >= tr.size():
			rows[i].visible = false
			continue
		var row: HBoxContainer
		if i < rows.size():
			row = rows[i]
		else:
			row = HBoxContainer.new()
			var sw := ColorRect.new()
			sw.custom_minimum_size = Vector2(14, 14)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			row.add_child(_label("", 14))
			tribe_box.add_child(row)
		row.visible = true
		var t = tr[i]
		(row.get_child(0) as ColorRect).color = t.color
		(row.get_child(1) as Label).text = "%s (%s)%s  pop %d\n  wood %d  stone %d  food %d" % [
			t.name, t.stage, " *blessed*" if t.blessed > 0.0 else "", t.members.size(), t.wood, t.stone, t.food]
