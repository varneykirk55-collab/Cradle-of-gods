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
var mode_label: Label
var cost_labels: Array = []
var save_button: Button
var load_button: Button
var load_confirm: ConfirmationDialog
var _bar_tw: Tween
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
	b.custom_minimum_size = Vector2(76, 40)   # MOBILE (desktop 56x26)
	b.add_theme_font_size_override("font_size", 16)
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
	prayer_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	mode_label = _label("", 12, Color(0.85, 0.82, 0.72))
	sv.add_child(mode_label)
	var opts := HBoxContainer.new()
	sv.add_child(opts)
	sandbox_box = CheckBox.new()
	sandbox_box.text = "Infinite prayer"
	sandbox_box.focus_mode = Control.FOCUS_NONE
	sandbox_box.add_theme_font_size_override("font_size", 15)   # MOBILE (desktop 12)
	sandbox_box.tooltip_text = "Infinite prayer: every power is free.\nOff: miracles cost the prayer your followers generate."
	sandbox_box.toggled.connect(func(on): set_sandbox(on))
	opts.add_child(sandbox_box)
	faith_box = CheckBox.new()
	faith_box.text = "Faith overlay"
	faith_box.focus_mode = Control.FOCUS_NONE
	faith_box.add_theme_font_size_override("font_size", 15)   # MOBILE (desktop 12)
	faith_box.toggled.connect(func(on): set_faith_overlay(on))
	opts.add_child(faith_box)
	var snd := Button.new()
	snd.text = "Sound"
	snd.tooltip_text = "Music, ambience and effects volume. M mutes everything."
	snd.add_theme_font_size_override("font_size", 15)
	snd.custom_minimum_size = Vector2(60, 36)   # MOBILE
	_style_button(snd)
	snd.pressed.connect(func(): audio_box.visible = not audio_box.visible)
	opts.add_child(snd)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.tooltip_text = "Save the world [K or F5]. One save slot, kept in this browser; saving again replaces it."
	save_button.add_theme_font_size_override("font_size", 15)
	save_button.custom_minimum_size = Vector2(60, 36)   # MOBILE
	_style_button(save_button)
	save_button.pressed.connect(func(): main.save_game())
	opts.add_child(save_button)
	load_button = Button.new()
	load_button.text = "Load"
	load_button.add_theme_font_size_override("font_size", 15)
	load_button.custom_minimum_size = Vector2(60, 36)   # MOBILE
	_style_button(load_button)
	load_button.pressed.connect(_on_load_pressed)
	opts.add_child(load_button)
	load_confirm = ConfirmationDialog.new()
	load_confirm.title = "Load saved world"
	load_confirm.ok_button_text = "Load"
	load_confirm.confirmed.connect(func(): main.load_game())
	add_child(load_confirm)
	refresh_save_info()
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
	fold.tooltip_text = "Collapse / expand the list. Tap a settlement to visit it."
	fold.custom_minimum_size = Vector2(44, 36)   # MOBILE (desktop 26x22)
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
	close.custom_minimum_size = Vector2(44, 36)
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
	hand_button.tooltip_text = "God Hand\nGrab, carry, place and throw villagers, animals, trees and rocks.\nDrag empty ground to pull the world. Click a building for settlement info."
	_style_button(hand_button)
	hand_button.pressed.connect(func(): if powers.current >= 0: powers.select(powers.current))
	hand_button.mouse_entered.connect(_set_hover.bind(-2))
	hand_button.mouse_exited.connect(_set_hover.bind(-1))
	hv.add_child(hand_button)
	var hl := _label("Hand", 11)
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
		b.tooltip_text = "%s\n%s%s" % [d["name"], d["desc"], cost]
		_style_button(b)
		b.pressed.connect(func(): _on_power_button(i))
		b.mouse_entered.connect(_set_hover.bind(i))
		b.mouse_exited.connect(_set_hover.bind(-1))
		vb.add_child(b)
		# prayer cost badge in the button's corner (red when you can't afford it)
		var cl := _label("", 12, GOLD)
		cl.add_theme_constant_override("outline_size", 4)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		cl.offset_right = -3
		cl.offset_bottom = 0
		b.add_child(cl)
		cost_labels.append(cl)
		var l := _label(d["short"], 11)
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
		b.custom_minimum_size = Vector2(52, 40)   # MOBILE (desktop 38x26)
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
		var b := _small_button(m.capitalize(), "Land creation mode: %s" % ("paint land continuously" if m == "brush" else "place connected square tiles"))
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
	brush_slider.custom_minimum_size = Vector2(160, 36)   # MOBILE (desktop 160x20)
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.value_changed.connect(func(v): powers.set_brush(v))
	brush_row.add_child(brush_slider)
	brush_label = _label("", 13)
	brush_row.add_child(brush_label)
	life_row = HBoxContainer.new()
	options_row.add_child(life_row)
	life_row.add_child(_label("Create", 13, GOLD))
	life_option = OptionButton.new()
	life_option.focus_mode = Control.FOCUS_NONE
	life_option.custom_minimum_size = Vector2(150, 40)   # MOBILE
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
	log_box.visible = false   # MOBILE: no room beside the toolbar
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
	powers.insufficient.connect(_on_insufficient)

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
	hvb.add_child(_label("Tap ? at the top to close", 13, GOLD))
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
	var sub := _label("Shape the land. Shepherd the faithful. Punish the heretic.\n\nTap to begin", 24, Color(1, 1, 1))
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

GOD HAND (no power selected - tap the hand icon to return to it)
  Touch and hold a villager / animal / tree / rock / bush   pick it up and carry it
  Lift your finger slowly   set it down gently      Flick and lift   throw it
  Drop a tree, rock or bush in a village   a gift of wood, stone or food (faith!)
  Drag empty ground with one finger   pull the world      Tap a building   settlement info

CAMERA   Two fingers: drag to move, pinch to zoom, twist to rotate

POWERS   Tap an icon in the bottom bar, then tap or drag on the world
  Miracles cost prayer (shown on each icon); ceremonies and private prayer at
  shrines produce it. Infinite prayer turns costs off.

OTHER    Faith overlay and Infinite prayer boxes (top left)   Save / Load (one slot,
         kept in this browser)   Sound button   Full = fullscreen   Time buttons (bottom right)"""

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
	_on_event("Welcome, god. Tap ? for help.", GOLD)

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
	_update_stats()
	_refresh_info()

## Not enough prayer: the prayer bar flashes red (the toast explains why).
func _on_insufficient(_idx: int, _cost: float) -> void:
	if _bar_tw != null and _bar_tw.is_running(): return
	prayer_bar.modulate = Color(1.0, 0.3, 0.25)
	_bar_tw = create_tween()
	_bar_tw.tween_property(prayer_bar, "modulate", Color.WHITE, 0.7)

func _on_load_pressed() -> void:
	var info := SaveGame.peek()
	if not info["ok"]:
		show_toast(info["msg"])
		return
	load_confirm.dialog_text = "Load the world saved %s?\n%s\n\nThe current world will be replaced." % [info["when"], info["summary"]]
	load_confirm.popup_centered()

## Tooltip on the Load button: what the save slot holds.
func refresh_save_info() -> void:
	if load_button == null: return
	var info := SaveGame.peek()
	load_button.tooltip_text = "Load the saved world [L or F9].\n" + ("Saved %s: %s" % [info["when"], info["summary"]] if info["ok"] else "No saved world yet.")

## After a saved world replaces the current one.
func after_load() -> void:
	settle_tribe = null
	settle_panel.visible = false
	_hover_text = ""
	sandbox_box.set_pressed_no_signal(sim.religion.sandbox)
	set_faith_overlay(sim.show_faith)
	_on_power_changed(powers.current)
	_update_stats()

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
		var cost := powers.cost_of(i)
		if cost > 0.0:
			if sim.religion.sandbox:
				extra += "  Cost %s prayer (free while Infinite prayer is on)." % Powers.fmt_cost(cost)
			elif sim.religion.can_afford(cost):
				extra += "  Cost %s prayer (you have %d)." % [Powers.fmt_cost(cost), int(sim.religion.prayer)]
			else:
				extra += "  Cost %s prayer - NOT ENOUGH: you have %d, need %s more." % [Powers.fmt_cost(cost), int(sim.religion.prayer), Powers.fmt_cost(ceilf((cost - sim.religion.prayer) * 10.0) / 10.0)]
		info_title.text = "%s%s" % [d["name"], "  - selected" if i == powers.current else ""]
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
	var rel := sim.religion
	prayer_bar.value = rel.prayer
	var rate := "+%.1f/s" % rel.income
	if rel.prayer >= Religion.PRAYER_CAP - 0.5: rate += " (full)"
	prayer_label.text = ("infinite  " if rel.sandbox else "%d / %d  " % [int(rel.prayer), int(Religion.PRAYER_CAP)]) + rate
	mode_label.text = "Infinite powers: every miracle is free" if rel.sandbox else "Belief-based powers: miracles cost prayer"
	mode_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0) if rel.sandbox else Color(1.0, 0.85, 0.55))
	prayer_bar.tooltip_text = "Prayer power %d of %d, generated +%.2f per second:\n  ceremonies at shrines  +%.2f/s\n  private prayer  +%.2f/s\n  believers' everyday faith  +%.2f/s\nMiracles spend it; terrain tools are free." % [
		int(rel.prayer), int(Religion.PRAYER_CAP), rel.income, rel.income_src["worship"], rel.income_src["prayer"], rel.income_src["quiet"]]
	for i in power_buttons.size():
		var c := powers.cost_of(i)
		var ok := powers.affordable(i)
		cost_labels[i].text = "" if c <= 0.0 else Powers.fmt_cost(c)
		cost_labels[i].add_theme_color_override("font_color", (Color(0.75, 0.85, 1.0) if rel.sandbox else GOLD.lightened(0.25)) if ok else Color(1.0, 0.35, 0.3))
		power_buttons[i].modulate = Color.WHITE if ok else Color(1.0, 0.62, 0.62)
	if info_panel.visible: _refresh_info()
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
		row.tooltip_text = "%s (%s, %s): %d worshippers, %d heretics, tension %d%%\nwood %d  stone %d  food %d   prayer +%.2f/s\nClick to visit." % [
			t.name, t.culture, sim.religion.tribe_label(t), t.worshippers, t.heretics, int(t.tension * 100), t.wood, t.stone, t.food, t.prayer_rate]

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
	var resting := 0
	var praying := 0
	for v in t.members:
		if v.priest: priests += 1
		if v.is_child(): children += 1
		if v.state == Villager.S.HUNT: hunters += 1
		if v.state == Villager.S.WORSHIP: worshipping += 1
		if v.state == Villager.S.REST or v.state == Villager.S.TO_REST: resting += 1
		if v.state == Villager.S.PRAY: praying += 1
	var status: Array = []
	if t.starving: status.append("famine")
	if t.blessed > 0.0: status.append("blessed")
	if t.ceremony: status.append("ceremony in progress (%d worshipping)" % worshipping)
	if t.meal: status.append("sharing a communal meal")
	if praying > 0: status.append("%d praying" % praying)
	if resting > 0: status.append("%d resting" % resting)
	if t.inspired > 0.0: status.append("inspired by worship")
	if t.tension >= 0.25: status.append("religious tension")
	if t.heretical: status.append("heretic settlement")
	settle_title.text = "%s - %s" % [t.name, t.stage]
	settle_label.text = "Culture: %s (%s)\nPopulation %d (%d children)   Housing %d\nWood %d   Stone %d   Food %d\nBuildings: %s\n\nReligion: %s, devotion %d%%\nWorshippers %d   Heretics %d   Priests %d\nHoly site: %s\nPrayer generated: +%.2f per second\nHunters out: %d\nStatus: %s" % [
		t.culture, sim.culture_desc(t),
		t.members.size(), children, sim.housing(t), t.wood, t.stone, t.food, blist.trim_suffix(", "),
		sim.religion.tribe_label(t), int(t.devotion), t.worshippers, t.heretics, priests,
		("Temple" if t.has_temple() else ("Shrine" if t.has_shrine() else ("under construction" if t.shrine != null else "none yet (needs 3 believers, 12 wood and 4 stone)"))),
		t.prayer_rate, hunters, ", ".join(status) if not status.is_empty() else "content"]

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
	audio_mute.text = "Mute all"
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
