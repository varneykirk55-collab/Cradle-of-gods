class_name Hud
extends CanvasLayer
## On-screen UI: world / religion / wildlife stats, prayer-power bar, tribe
## list (click to visit), settlement panel, divine toolbar (God Hand + 10
## powers), land-mode / brush-size / life-type options, time-speed buttons,
## God Hand hover tooltip, event log, toasts, help overlay and title splash.

var main
var sim: WorldSim
var powers: Powers
var hand: GodHand
var stats_label: Label
var tribe_box: VBoxContainer
var info_title: Label
var info_desc: Label
var log_box: VBoxContainer
var help: PanelContainer
var splash: Control
var flash_rect: ColorRect
var tooltip: PanelContainer
var tooltip_label: Label
var toast: Label
var prayer_bar: ProgressBar
var prayer_label: Label
var sandbox_box: CheckBox
var faith_box: CheckBox
var options_row: HBoxContainer
var land_mode_buttons: Array = []
var brush_row: HBoxContainer
var brush_slider: HSlider
var brush_label: Label
var life_row: HBoxContainer
var life_option: OptionButton
var settle_panel: PanelContainer
var settle_label: Label
var settle_title: Label
var settle_tribe = null
var tribe_fold: Button
var info_panel: PanelContainer
var hand_button: Button
var power_buttons: Array = []
var speed_buttons: Array = []
var audio_box: VBoxContainer
var audio_sliders := {}
var audio_mute: CheckBox
var _acc := 0.0
var _hover := -1
var _hover_text := ""

const GOLD := Color(0.86, 0.7, 0.38)
const PANEL_BG := Color(0.05, 0.07, 0.13, 0.82)
const HERETIC := Color(0.78, 0.5, 1.0)

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

func _btn_style(pressed: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.2, 0.08, 0.95) if pressed else (Color(0.16, 0.18, 0.28, 0.95) if hover else Color(0.09, 0.11, 0.2, 0.95))
	sb.border_color = Color(1.0, 0.85, 0.4) if pressed else GOLD.darkened(0.3)
	sb.set_border_width_all(3 if pressed else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(3)
	return sb

func _style_button(b: BaseButton) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _btn_style(false))
	b.add_theme_stylebox_override("hover", _btn_style(false, true))
	b.add_theme_stylebox_override("pressed", _btn_style(true))
	b.add_theme_stylebox_override("hover_pressed", _btn_style(true))

func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(56, 26)
	b.add_theme_font_size_override("font_size", 13)
	_style_button(b)
	return b

func setup(p_main, p_sim: WorldSim, p_powers: Powers, p_hand: GodHand) -> void:
	main = p_main
	sim = p_sim
	powers = p_powers
	hand = p_hand
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top-left stats + prayer
	var sp := _panel()
	sp.position = Vector2(12, 12)
	root.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	sv.add_child(_label("CRADLE OF GODS", 20, GOLD))
	stats_label = _label("", 14)
	sv.add_child(stats_label)
	var pr := HBoxContainer.new()
	sv.add_child(pr)
	pr.add_child(_label("Prayer", 13, GOLD))
	prayer_bar = ProgressBar.new()
	prayer_bar.max_value = Religion.PRAYER_CAP
	prayer_bar.show_percentage = false
	prayer_bar.custom_minimum_size = Vector2(150, 14)
	prayer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.35)
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.14, 0.2)
	bg.set_corner_radius_all(4)
	prayer_bar.add_theme_stylebox_override("fill", fill)
	prayer_bar.add_theme_stylebox_override("background", bg)
	pr.add_child(prayer_bar)
	prayer_label = _label("", 13)
	pr.add_child(prayer_label)
	var opts := HBoxContainer.new()
	sv.add_child(opts)
	sandbox_box = CheckBox.new()
	sandbox_box.text = "Infinite prayer [P]"
	sandbox_box.focus_mode = Control.FOCUS_NONE
	sandbox_box.add_theme_font_size_override("font_size", 12)
	sandbox_box.toggled.connect(func(on): sim.religion.sandbox = on)
	opts.add_child(sandbox_box)
	faith_box = CheckBox.new()
	faith_box.text = "Faith overlay [V]"
	faith_box.focus_mode = Control.FOCUS_NONE
	faith_box.add_theme_font_size_override("font_size", 12)
	faith_box.toggled.connect(func(on): set_faith_overlay(on))
	opts.add_child(faith_box)
	var snd := Button.new()
	snd.text = "Sound"
	snd.tooltip_text = "Music, ambience and effects volume. M mutes everything."
	snd.add_theme_font_size_override("font_size", 12)
	_style_button(snd)
	snd.pressed.connect(func(): audio_box.visible = not audio_box.visible)
	opts.add_child(snd)
	_build_audio_box(sv)

	# --- top-right tribes
	var tp := _panel()
	tp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tp.offset_left = -360
	tp.offset_right = -12
	tp.offset_top = 12
	tp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(tp)
	var tv := VBoxContainer.new()
	tp.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	var tl := _label("SETTLEMENTS", 15, GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var fold := Button.new()
	fold.text = "-"
	fold.tooltip_text = "Collapse / expand the list [T]. Click a settlement to visit it."
	fold.custom_minimum_size = Vector2(26, 22)
	_style_button(fold)
	fold.pressed.connect(toggle_tribes)
	th.add_child(fold)
	tribe_fold = fold
	tribe_box = VBoxContainer.new()
	tribe_box.add_theme_constant_override("separation", 2)
	tv.add_child(tribe_box)

	# --- settlement panel (right, below the list)
	settle_panel = _panel()
	settle_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	settle_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settle_panel.offset_right = -12
	settle_panel.offset_top = 40
	root.add_child(settle_panel)
	var sbx := VBoxContainer.new()
	settle_panel.add_child(sbx)
	var sh := HBoxContainer.new()
	sbx.add_child(sh)
	settle_title = _label("", 17, GOLD)
	settle_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(settle_title)
	var close := Button.new()
	close.text = "x"
	_style_button(close)
	close.pressed.connect(func(): settle_panel.visible = false)
	sh.add_child(close)
	settle_label = _label("", 13)
	sbx.add_child(settle_label)
	settle_panel.visible = false

	# --- bottom toolbar
	var bar := _panel()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -10
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	bar.add_child(hb)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hb.add_child(hv)
	hand_button = Button.new()
	hand_button.toggle_mode = true
	hand_button.icon = load("res://assets/icons/hand.png")
	hand_button.expand_icon = true
	hand_button.custom_minimum_size = Vector2(62, 62)
	hand_button.tooltip_text = "God Hand  [Esc / `]\nGrab, carry, place and throw villagers, animals, trees and rocks.\nDrag empty ground to pull the world. Click a building for settlement info."
	_style_button(hand_button)
	hand_button.pressed.connect(func(): if powers.current >= 0: powers.select(powers.current))
	hand_button.mouse_entered.connect(_set_hover.bind(-2))
	hand_button.mouse_exited.connect(_set_hover.bind(-1))
	hv.add_child(hand_button)
	var hl := _label("` Hand", 11)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(hl)
	hb.add_child(VSeparator.new())
	for i in Powers.LIST.size():
		var d: Dictionary = Powers.LIST[i]
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)
		var b := Button.new()
		b.toggle_mode = true
		b.icon = load(d["icon"])
		b.expand_icon = true
		b.custom_minimum_size = Vector2(62, 62)
		var cost := "" if d["cost"] <= 0.0 else "\nCost: %d prayer" % int(d["cost"])
		b.tooltip_text = "%s  [%s]\n%s%s" % [d["name"], d["key"], d["desc"], cost]
		_style_button(b)
		b.pressed.connect(func(): _on_power_button(i))
		b.mouse_entered.connect(_set_hover.bind(i))
		b.mouse_exited.connect(_set_hover.bind(-1))
		vb.add_child(b)
		var l := _label("%s %s" % [d["key"], d["short"]], 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		power_buttons.append(b)
	hb.add_child(VSeparator.new())
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
		b.custom_minimum_size = Vector2(38, 26)
		b.tooltip_text = ["Pause (Space)", "Normal speed", "Double speed", "Quadruple speed"][i]
		_style_button(b)
		b.pressed.connect(func(): main.set_speed(i))
		sgrid.add_child(b)
		speed_buttons.append(b)

	# --- info / options box above toolbar
	var ip := _panel()
	info_panel = ip
	ip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ip.offset_bottom = -116
	ip.custom_minimum_size = Vector2(640, 0)
	root.add_child(ip)
	var iv := VBoxContainer.new()
	ip.add_child(iv)
	info_title = _label("", 16, GOLD)
	info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(info_title)
	info_desc = _label("", 13)
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_desc.custom_minimum_size = Vector2(620, 0)
	iv.add_child(info_desc)
	options_row = HBoxContainer.new()
	options_row.alignment = BoxContainer.ALIGNMENT_CENTER
	options_row.add_theme_constant_override("separation", 10)
	iv.add_child(options_row)
	var lg := ButtonGroup.new()
	for m in ["brush", "tile"]:
		var b := _small_button(m.capitalize(), "Land creation mode [B]: %s" % ("paint land continuously" if m == "brush" else "place connected square tiles"))
		b.button_group = lg
		b.pressed.connect(func(): if powers.land_mode != m: powers.toggle_land_mode())
		options_row.add_child(b)
		land_mode_buttons.append(b)
	brush_row = HBoxContainer.new()
	options_row.add_child(brush_row)
	brush_row.add_child(_label("Brush", 13, GOLD))
	brush_slider = HSlider.new()
	brush_slider.min_value = Powers.BRUSH_MIN
	brush_slider.max_value = Powers.BRUSH_MAX
	brush_slider.step = 1.0
	brush_slider.value = powers.brush
	brush_slider.custom_minimum_size = Vector2(160, 20)
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.value_changed.connect(func(v): powers.set_brush(v))
	brush_row.add_child(brush_slider)
	brush_label = _label("", 13)
	brush_row.add_child(brush_label)
	life_row = HBoxContainer.new()
	options_row.add_child(life_row)
	life_row.add_child(_label("Create [C]", 13, GOLD))
	life_option = OptionButton.new()
	life_option.focus_mode = Control.FOCUS_NONE
	for t in Powers.LIFE_TYPES:
		life_option.add_item(Powers.LIFE_NAMES[t])
	life_option.item_selected.connect(_on_life_selected)
	life_row.add_child(life_option)

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

	# --- hand tooltip + toast
	tooltip = _panel()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label = _label("", 13)
	tooltip.add_child(tooltip_label)
	tooltip.visible = false
	root.add_child(tooltip)
	toast = _label("", 18, Color(1.0, 0.85, 0.6))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 90
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	root.add_child(toast)
	hand.hover_changed.connect(func(t): _hover_text = t)
	hand.settlement_clicked.connect(show_tribe)
	powers.message.connect(show_toast)

	# --- help overlay
	help = _panel()
	help.set_anchors_preset(Control.PRESET_CENTER)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(help)
	var hvb := VBoxContainer.new()
	help.add_child(hvb)
	hvb.add_child(_label("HOW TO PLAY", 22, GOLD))
	hvb.add_child(_label(HELP_TEXT, 14))
	hvb.add_child(_label("Press H to close", 13, GOLD))
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
	var sub := _label("Shape the land. Shepherd the faithful. Punish the heretic.\n\nClick or press any key to begin", 24, Color(1, 1, 1))
	sub.add_theme_constant_override("outline_size", 8)
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub.offset_bottom = -60
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.add_child(sub)
	splash.gui_input.connect(_on_splash_input)

	speed_buttons[1].button_pressed = true
	_on_power_changed(powers.current)
	_update_stats()

const HELP_TEXT := """You are a god watching over a young world. Tribes gather, build, worship and grow.
Win their faith with miracles; heretics arise from famine, neglect and cruelty.

GOD HAND (no power selected - Esc or ` returns to the hand)
  Left-drag a villager / animal / tree / rock / bush   pick it up and carry it
  Release slowly   set it down gently        Flick the mouse + release   throw it
  Drop a tree, rock or bush in a village   a gift of wood, stone or food (faith!)
  Left-drag empty ground   pull the world (pan)     Click a building   settlement info
CAMERA   WASD / Arrows pan (Shift faster)   Q / E rotate   Wheel or R / F zoom
         Right- or middle-drag orbit        Tab next settlement
POWERS   1 Land  2 Remove  3 Raise  4 Lower  5 Life  6 Forest  7 Rain  8 Plenty
         9 Lightning  0 Meteor     then left-click / hold on the world
         B land mode (brush / tile)    C life type    [ / ] brush size
RELIGION P infinite prayer (sandbox)   V faith overlay (gold = devout, white = priest,
         purple = heretic)   Miracles cost prayer, worship at shrines produces it
TIME     Space pause   - / + slower / faster    T fold settlement list    H or F1 help    F12 screenshot
SOUND    M mute    Sound button (top left): music, ambience and effects volume"""

func _on_life_selected(i: int) -> void:
	powers.life_type = Powers.LIFE_TYPES[i]
	_refresh_info()

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

func set_faith_overlay(on: bool) -> void:
	sim.show_faith = on
	faith_box.set_pressed_no_signal(on)
	for v in sim.villagers:
		v._update_marker()

func set_sandbox(on: bool) -> void:
	sim.religion.sandbox = on
	sandbox_box.set_pressed_no_signal(on)

func show_toast(text: String) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	var tw := toast.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.8)

func show_tribe(t) -> void:
	settle_tribe = t
	settle_panel.visible = t != null
	_update_settlement()

func _on_power_button(i: int) -> void:
	powers.select(i)

func _on_power_changed(idx: int) -> void:
	for i in power_buttons.size():
		power_buttons[i].set_pressed_no_signal(i == idx)
	hand_button.set_pressed_no_signal(idx < 0)
	var id := powers.current_id()
	land_mode_buttons[0].get_parent().visible = true
	for b in land_mode_buttons:
		b.visible = id == "land"
	land_mode_buttons[0].set_pressed_no_signal(powers.land_mode == "brush")
	land_mode_buttons[1].set_pressed_no_signal(powers.land_mode == "tile")
	brush_row.visible = id in ["land", "remove", "raise", "lower", "forest"] and not (id == "land" and powers.land_mode == "tile")
	brush_slider.set_value_no_signal(powers.brush)
	brush_label.text = "%d" % int(powers.brush)
	life_row.visible = id == "villager"
	life_option.select(Powers.LIFE_TYPES.find(powers.life_type))
	_refresh_info()

func toggle_tribes() -> void:
	tribe_box.visible = not tribe_box.visible
	tribe_fold.text = "-" if tribe_box.visible else "+"

func _refresh_info() -> void:
	# the info box only appears while hovering the toolbar or using a power
	info_panel.visible = _hover != -1 or powers.current >= 0
	var i := _hover if _hover >= 0 else powers.current
	if _hover == -2 or i < 0:
		info_title.text = "God Hand"
		info_desc.text = "Left-drag villagers, animals, trees and rocks to carry them; flick to throw. Drag the ground to pan, click buildings for info. Pick a power with 1-0."
	else:
		var d: Dictionary = Powers.LIST[i]
		var extra := ""
		if d["id"] == "land": extra = "  Mode: %s." % powers.land_mode.capitalize()
		if d["id"] == "villager": extra = "  Creating: %s." % Powers.LIFE_NAMES[powers.life_type]
		if d["cost"] > 0.0: extra += "  Cost %d prayer." % int(d["cost"])
		info_title.text = "%s  [%s]%s" % [d["name"], d["key"], "  - selected" if i == powers.current else ""]
		info_desc.text = d["desc"] + extra

func _on_flash(strength: float) -> void:
	flash_rect.color = Color(1, 1, 1, strength)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.4)

func _on_event(text: String, color: Color) -> void:
	var l := _label(text, 13, color.lightened(0.25))
	log_box.add_child(l)
	while log_box.get_child_count() > 8:
		log_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)

func _process(dt: float) -> void:
	_acc += dt
	if _acc > 0.25:
		_acc = 0.0
		_update_stats()
		if settle_panel.visible: _update_settlement()
	if _hover_text != "" and not splash.visible:
		tooltip.visible = true
		tooltip_label.text = _hover_text
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		tooltip.position = Vector2(minf(mp.x + 28, vs.x - tooltip.size.x - 8), minf(mp.y + 24, vs.y - tooltip.size.y - 8))
	else:
		tooltip.visible = false

func _update_stats() -> void:
	var tr := sim.live_tribes()
	var day := int(sim.time / 60.0) + 1
	var rt := sim.religion.totals()
	var ac := sim.eco.counts()
	stats_label.text = "Year %d   (%s)\nPopulation %d   Settlements %d\nBuildings %d   Trees %d   Fires %d\nWorshippers %d   Heretics %d   Priests %d\nShrines %d   Temples %d   Avg faith %d%%\nDeer %d  Rabbits %d  Wolves %d  Birds %d\nTool: %s" % [
		day, main.speed_name(), sim.population(), tr.size(), sim.building_count(), sim.count_type(WorldSim.RES_TREE),
		sim.fires.size(), rt["worshippers"], rt["heretics"], rt["priests"], rt["shrines"], rt["temples"], int(rt["avg_faith"]),
		ac["deer"], ac["rabbit"], ac["wolf"], ac["bird"],
		Powers.LIST[powers.current]["name"] if powers.current >= 0 else "God Hand"]
	prayer_bar.value = sim.religion.prayer
	prayer_label.text = "inf" if sim.religion.sandbox else "%d" % int(sim.religion.prayer)
	var rows := tribe_box.get_children()
	for i in maxi(rows.size(), tr.size()):
		if i >= tr.size():
			rows[i].visible = false
			continue
		var row: Button
		if i < rows.size():
			row = rows[i]
		else:
			row = Button.new()
			row.flat = true
			row.focus_mode = Control.FOCUS_NONE
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_constant_override("h_separation", 6)
			row.custom_minimum_size = Vector2(0, 20)
			row.icon = _swatch()
			row.pressed.connect(_on_tribe_row.bind(i))
			tribe_box.add_child(row)
		row.visible = true
		var t = tr[i]
		row.add_theme_color_override("font_color", HERETIC.lightened(0.2) if t.heretical else Color(0.95, 0.92, 0.85))
		row.add_theme_color_override("icon_normal_color", t.color)
		var holy: String = (" Temple" if t.has_temple() else (" Shrine" if t.has_shrine() else ""))
		var warn: String = "  ! %d heretics" % t.heretics if t.heretics > 0 else ""
		row.text = "%s  %s  pop %d  %s %d%%%s%s%s%s" % [
			t.name, t.stage, t.members.size(), sim.religion.tribe_label(t), int(t.devotion), holy, warn,
			"  blessed" if t.blessed > 0.0 else "", "  STARVING" if t.starving else ""]
		row.tooltip_text = "%s (%s): %d worshippers, %d heretics, tension %d%%\nwood %d  stone %d  food %d\nClick to visit." % [
			t.name, sim.religion.tribe_label(t), t.worshippers, t.heretics, int(t.tension * 100), t.wood, t.stone, t.food]

var _swatch_tex: Texture2D
func _swatch() -> Texture2D:
	if _swatch_tex == null:
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_swatch_tex = ImageTexture.create_from_image(img)
	return _swatch_tex

func _on_tribe_row(i: int) -> void:
	var tr := sim.live_tribes()
	if i >= tr.size(): return
	var t = tr[i]
	main.rig.focus = t.center
	main.rig.dist = 34.0
	show_tribe(t)

func _update_settlement() -> void:
	var t = settle_tribe
	if t == null or not t.alive:
		settle_panel.visible = false
		return
	var counts := {}
	for b in t.buildings:
		var k: String = b.type + ("" if b.built else " (building)")
		counts[k] = counts.get(k, 0) + 1
	var blist := ""
	for k in counts:
		blist += "%s x%d, " % [k, counts[k]]
	var priests := 0
	var children := 0
	var hunters := 0
	var worshipping := 0
	for v in t.members:
		if v.priest: priests += 1
		if v.is_child(): children += 1
		if v.state == Villager.S.HUNT: hunters += 1
		if v.state == Villager.S.WORSHIP: worshipping += 1
	var status: Array = []
	if t.starving: status.append("famine")
	if t.blessed > 0.0: status.append("blessed")
	if t.ceremony: status.append("ceremony in progress (%d worshipping)" % worshipping)
	if t.inspired > 0.0: status.append("inspired by worship")
	if t.tension >= 0.25: status.append("religious tension")
	if t.heretical: status.append("heretic settlement")
	settle_title.text = "%s - %s" % [t.name, t.stage]
	settle_label.text = "Population %d (%d children)   Housing %d\nWood %d   Stone %d   Food %d\nBuildings: %s\n\nReligion: %s, devotion %d%%\nWorshippers %d   Heretics %d   Priests %d\nHoly site: %s\nHunters out: %d\nStatus: %s" % [
		t.members.size(), children, sim.housing(t), t.wood, t.stone, t.food, blist.trim_suffix(", "),
		sim.religion.tribe_label(t), int(t.devotion), t.worshippers, t.heretics, priests,
		("Temple" if t.has_temple() else ("Shrine" if t.has_shrine() else ("under construction" if t.shrine != null else "none yet (needs 4 believers, wood and stone)"))),
		hunters, ", ".join(status) if not status.is_empty() else "content"]

# ------------------------------------------------------------------ audio settings
func _build_audio_box(parent: Control) -> void:
	audio_box = VBoxContainer.new()
	audio_box.visible = false
	audio_box.add_theme_constant_override("separation", 2)
	parent.add_child(audio_box)
	for bus in ["Master", "Music", "Ambience", "SFX"]:
		var row := HBoxContainer.new()
		audio_box.add_child(row)
		var l := _label({"Master": "Volume", "Music": "Music", "Ambience": "Ambience", "SFX": "Effects"}[bus], 12)
		l.custom_minimum_size = Vector2(72, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(150, 18)
		sl.focus_mode = Control.FOCUS_NONE
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.value_changed.connect(func(v): main.audio.set_volume(bus, v))
		row.add_child(sl)
		audio_sliders[bus] = sl
	audio_mute = CheckBox.new()
	audio_mute.text = "Mute all [M]"
	audio_mute.focus_mode = Control.FOCUS_NONE
	audio_mute.add_theme_font_size_override("font_size", 12)
	audio_mute.toggled.connect(func(on): main.audio.set_muted(on))
	audio_box.add_child(audio_mute)
	sync_audio()

## Refreshes the sliders / mute box from the audio settings (no signals).
func sync_audio() -> void:
	if main.audio == null or audio_box == null: return
	for bus in audio_sliders:
		audio_sliders[bus].set_value_no_signal(main.audio.volumes.get(bus, 1.0))
	audio_mute.set_pressed_no_signal(main.audio.muted)
