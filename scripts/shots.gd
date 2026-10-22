class_name Shots
extends Node
## Rendered screenshot tour + synthetic OS-level input test:
##   godot --path . --rendering-driver opengl3 -- --shots
## With `-- --demo` it instead plays a scripted ~45 s gameplay sequence
## (meant for `--write-movie`), see tools/record_demo.sh.

var m
var sim: WorldSim
var hand: GodHand
var powers: Powers
var rig: CameraRig
var fails := 0

func _check(name: String, ok: bool, detail := "") -> bool:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok: fails += 1
	return ok

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await m.save_shot(name)

func run(p_main) -> void:
	m = p_main
	sim = m.sim
	hand = m.hand
	powers = m.powers
	rig = m.rig
	if "--demo" in m.args:
		await _demo()
		return
	m.set_speed(1)
	await _frames(8)
	await _shot("01_title_splash")
	m.hud.splash.visible = false
	sim.religion.sandbox = true
	m.hud.set_sandbox(true)
	sim.prewarm(420.0)
	terrain_flush()
	var tr := sim.live_tribes()
	var t0: WorldSim.Tribe = _biggest()
	# --- overview + village
	rig.set_view(Vector3(0, 0, 0), 200.0, 0.6, 1.0, true)
	hand.virtual_pointer = Vector3(500, 0, 500)
	await _frames(12)
	await _shot("02_world_overview")
	rig.set_view(t0.center, 24.0, 0.9, 0.6, true)
	_point_at(t0.center + Vector3(3, 0, -2))
	await _frames(20)
	await _shot("03_village_closeup")
	m.hud.toggle_help()
	await _frames(4)
	await _shot("04_help_overlay")
	m.hud.toggle_help()
	# --- God Hand: hover, grab, carry, throw
	var v: Villager = _adult(t0)
	v._reset(120.0)   # stand still for the photo shoot
	rig.set_view(v.position, 20.0, 0.9, 0.75, true)
	await _frames(4)
	_point_at(v.position)
	await _frames(14)
	await _shot("05_hand_hover_villager")
	hand.press()
	for i in 14:
		_point_at(v.position)
		await _frames(1)
	_point_at(v.position + Vector3(0, 0, 0))
	for i in 12:
		_point_at(v.position.lerp(t0.center + Vector3(-4, 0, 4), 0.1))
		await _frames(1)
	await _shot("06_hand_carrying_villager")
	var from := hand.hand_pos
	for i in 5:
		_point_at(from + Vector3(1.6 * (i + 1), 0, -0.6 * (i + 1)))
		await _frames(1)
	hand.release()
	await _frames(3)
	await _shot("07_villager_thrown")
	await _frames(30)
	hand.virtual_pointer = null
	# --- carry a deer
	var deer = _animal("deer", t0.center)
	if deer:
		deer._rest(120.0)
		rig.set_view(deer.position, 18.0, 1.6, 0.6, true)
		await _frames(3)
		_point_at(deer.position)
		await _frames(10)
		hand.press()
		for i in 18:
			_point_at(deer.position)
			await _frames(1)
		await _shot("08_hand_carrying_deer")
		hand.release()
		await _frames(30)
	# --- land creation: brush
	var sea := Vector3(-80, 0, -78)
	rig.set_view(sea, 80.0, 0.5, 0.95, true)
	powers.select(powers.index_of("land"))
	powers.land_mode = "brush"
	powers.set_brush(9.0)
	_point_at(sea)
	await _frames(6)
	await _shot("09_before_land_creation")
	for i in 90:
		var p := sea + Vector3(cos(i * 0.07) * 14.0, 0, sin(i * 0.09) * 10.0)
		powers.cast("land", p, 1.0 / 20.0)
		if i % 15 == 0:
			_point_at(p)
			await _frames(1)
	terrain_flush()
	await _frames(6)
	await _shot("10_land_brush_new_island")
	# --- tiles
	powers.toggle_land_mode()
	var tb := Vector3(70, 0, 82)
	rig.set_view(tb + Vector3(6, 0, 0), 60.0, 0.4, 0.9, true)
	var shape := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(2, 2), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(-2, -1)]
	for c in shape:
		powers._last_tile = Vector3(INF, 0, INF)
		powers.cast("land", tb + Vector3(c.x * Terrain.TILE, 0, c.y * Terrain.TILE), 0.0)
	_point_at(tb + Vector3(4 * Terrain.TILE, 0, 2 * Terrain.TILE))
	terrain_flush()
	await _frames(8)
	await _shot("11_land_tiles")
	powers.toggle_land_mode()
	# --- remove land: cut a channel through the brush island
	powers.select(powers.index_of("remove"))
	powers.set_brush(4.0)
	for i in 50:
		powers.cast("remove", sea + Vector3(-16 + i * 0.7, 0, 0), 1.0 / 20.0)
	terrain_flush()
	rig.set_view(sea, 80.0, 0.5, 0.95, true)
	_point_at(sea + Vector3(14, 0, 0))
	await _frames(8)
	await _shot("12_remove_land_channel")
	powers.select(powers.current)   # back to the hand
	# --- religion: a shrine/temple ceremony
	var holy = _holy_tribe()
	if holy != null:
		holy.ceremony = true
		holy.ceremony_t = 30.0
		for vv in holy.members:
			vv.faith = maxf(vv.faith, 40.0)
			if not vv.heretic and not vv.is_busy_with_god(): vv._reset(0.0)
		for i in 160: sim._step(0.1)
		rig.set_view(holy.shrine_pos(), 16.0, 0.7, 0.55, true)
		hand.virtual_pointer = Vector3(500, 0, 500)
		await _frames(20)
		await _shot("13_worship_ceremony")
	# --- heretics with the faith overlay
	var ht = _heretic_tribe()
	m.hud.set_faith_overlay(true)
	if ht != null:
		rig.set_view(ht.center, 26.0, 1.2, 0.7, true)
		m.hud.show_tribe(ht)
		var h = _a_heretic(ht)
		if h != null: _point_at(h.position)
		await _frames(16)
		await _shot("14_heretics_overlay")
	m.hud.set_faith_overlay(false)
	m.hud.show_tribe(null)
	# --- wildlife (paused so the subject stays in frame while llvmpipe renders)
	m.set_speed(0)
	for sp in ["deer", "wolf", "rabbit"]:
		var a = _animal(sp, Vector3.ZERO)
		if a != null:
			rig.set_view(a.position, 11.0 if sp == "rabbit" else 15.0, 0.4, 0.45, true)
			hand.virtual_pointer = Vector3(500, 0, 500)
			await _frames(10)
			await _shot("15_wildlife_%s" % sp)
	var bird = _animal("bird", Vector3.ZERO)
	if bird != null:
		rig.set_view(bird.position - Vector3(0, 6, 0), 22.0, 0.4, 0.35, true)
		await _frames(6)
		await _shot("15_wildlife_bird")
	m.set_speed(1)
	# --- settlement panel + temple
	var tt = _holy_tribe()
	if tt != null:
		rig.set_view(tt.shrine_pos(), 22.0, 2.4, 0.6, true)
		m.hud.show_tribe(tt)
		await _frames(10)
		await _shot("16_settlement_panel")
		m.hud.show_tribe(null)
	# --- divine powers FX
	var t1: WorldSim.Tribe = tr[1] if tr.size() > 1 else t0
	rig.set_view(t1.center, 45.0, 2.2, 0.55, true)
	powers.select(powers.index_of("rain"))
	_point_at(t1.center)
	powers.cast("rain", t1.center + Vector3(4, 0, 0), 0.0)
	await _frames(30)
	await _shot("17_blessed_rain")
	powers.select(powers.index_of("plenty"))
	rig.set_view(t0.center, 30.0, 0.9, 0.7, true)
	_point_at(t0.center)
	powers.cooldown = 0.0
	powers.cast("plenty", t0.center, 0.0)
	await _frames(8)
	await _shot("18_miracle_of_plenty")
	powers.select(powers.index_of("lightning"))
	var tree = sim.find_nearest(t0.center, WorldSim.RES_TREE, 40.0)
	var lp: Vector3 = tree.pos if tree != null else t0.center + Vector3(6, 0, 6)
	rig.set_view(lp, 30.0, 0.4, 0.6, true)
	_point_at(lp)
	powers.cooldown = 0.0
	powers.cast("lightning", lp, 0.0)
	await _frames(2)
	await _shot("19_lightning")
	for i in 3:
		sim.update(0.5)
		await _frames(1)
	await _shot("20_forest_fire")
	powers.select(powers.index_of("meteor"))
	var t2: WorldSim.Tribe = tr[tr.size() - 1]
	rig.set_view(t2.center, 55.0, 1.4, 0.65, true)
	_point_at(t2.center)
	powers.cooldown = 0.0
	powers.cast("meteor", t2.center, 0.0)
	await get_tree().create_timer(0.85).timeout
	await _shot("21_meteor_falling")
	await get_tree().create_timer(0.5).timeout
	await _shot("22_meteor_impact")
	powers.select(powers.current)
	hand.virtual_pointer = null
	await _input_test()
	print("SHOTS DONE fails=%d %s" % [fails, sim.stat_line()])
	get_tree().quit(0 if fails == 0 else 1)

func terrain_flush() -> void:
	m.terrain.rebuild_dirty(true)
	sim.nav.flush()

func _point_at(p: Vector3) -> void:
	hand.virtual_pointer = Vector3(p.x, maxf(m.terrain.height_at(p.x, p.z), Terrain.SEA), p.z)

func _biggest() -> WorldSim.Tribe:
	var best = null
	for t in sim.live_tribes():
		if best == null or t.members.size() > best.members.size(): best = t
	return best

func _adult(t) -> Villager:
	for v in t.members:
		if not v.is_child() and not v.is_busy_with_god() and not v.priest: return v
	return t.members[0]

func _animal(sp: String, near: Vector3):
	var best = null
	var bd := INF
	for a in sim.eco.animals:
		if a.species != sp or a.dead or a.is_busy_with_god(): continue
		var d: float = a.position.distance_to(near)
		if d < bd:
			bd = d
			best = a
	return best

func _holy_tribe():
	var best = null
	for t in sim.live_tribes():
		if t.has_shrine() and (best == null or (t.has_temple() and not best.has_temple()) or t.members.size() > best.members.size()):
			best = t
	return best

func _heretic_tribe():
	var best = null
	for t in sim.live_tribes():
		if t.heretics > 0 and (best == null or t.heretics > best.heretics): best = t
	if best == null:
		# stir up some dissent so the overlay has something to show
		var t := _biggest()
		for i in 3: sim.religion.on_hardship(t, "famine", 14.0)
		for v in t.members: v.last_miracle = sim.time - 500.0
		sim.religion._tick(1.0)
		best = t
	return best

func _a_heretic(t):
	for v in t.members:
		if v.heretic: return v
	return null

# ---------------------------------------------------------------- input test
## Drives the game through synthetic OS-level input events (keyboard + mouse),
## exercising the same code paths a player uses.
func _input_test() -> void:
	var t0: WorldSim.Tribe = _biggest()
	rig.set_view(t0.center, 40.0, 0.8, 0.8, true)
	await _frames(5)
	var center: Vector2 = m.get_viewport().get_visible_rect().size * 0.5
	var f0 := rig.focus
	_key(KEY_W, true)
	await _frames(15)
	_key(KEY_W, false)
	_check("input: W pans camera", rig.focus.distance_to(f0) > 2.0, "moved %.1f" % rig.focus.distance_to(f0))
	var d0 := rig.dist
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, center, true)
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, center, false)
	await _frames(2)
	_check("input: wheel zooms", rig.dist < d0, "%.1f -> %.1f" % [d0, rig.dist])
	var y0 := rig.yaw
	_mouse_button(MOUSE_BUTTON_RIGHT, center, true)
	_motion(center + Vector2(120, 0), Vector2(120, 0), MOUSE_BUTTON_MASK_RIGHT)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_RIGHT, center + Vector2(120, 0), false)
	_check("input: right-drag orbits", absf(rig.yaw - y0) > 0.3, "yaw %.2f -> %.2f" % [y0, rig.yaw])
	# --- God Hand via the real mouse: left-drag empty ground pans the world
	rig.set_view(t0.center + Vector3(20, 0, 20), 40.0, 0.8, 0.9, true)
	await _frames(6)
	var empty: Vector2 = center + Vector2(0, 120)
	Input.warp_mouse(empty)
	await _frames(4)
	var fpan := rig.focus
	_mouse_button(MOUSE_BUTTON_LEFT, empty, true)
	await _frames(2)
	for i in 6:
		_motion(empty + Vector2(-25 * (i + 1), 0), Vector2(-25, 0), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	_mouse_button(MOUSE_BUTTON_LEFT, empty + Vector2(-150, 0), false)
	await _frames(2)
	_check("input: hand drags the world (pan)", rig.focus.distance_to(fpan) > 3.0 and hand.stats["pans"] > 0, "moved %.1f" % rig.focus.distance_to(fpan))
	# --- grab a villager with the mouse, carry it, flick to throw
	var v := _adult(t0)
	v._reset(5.0)
	rig.set_view(v.position, 26.0, 0.8, 0.85, true)
	await _frames(6)
	var sp := rig.cam.unproject_position(v.position + Vector3(0, 0.6, 0))
	Input.warp_mouse(sp)
	_motion(sp, Vector2.ZERO, 0)
	await _frames(6)
	_check("input: mouse hover finds the villager", hand.hover != null and hand.hover["kind"] == "villager", "hover=%s" % [hand.hover["kind"] if hand.hover else "none"])
	_mouse_button(MOUSE_BUTTON_LEFT, sp, true)
	await _frames(10)
	_check("input: left-press grabs", hand.state == GodHand.H.HOLD, "state=%d" % hand.state)
	var p0 := v.position
	for i in 5:
		var q := sp + Vector2(70 * (i + 1), -20 * (i + 1))
		Input.warp_mouse(q)
		_motion(q, Vector2(70, -20), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	_mouse_button(MOUSE_BUTTON_LEFT, sp + Vector2(350, -100), false)
	await _frames(2)
	_check("input: flick + release throws", v.state == Villager.S.FLYING or v.dead or v.position.distance_to(p0) > 3.0, "state=%d" % v.state)
	await _frames(20)
	# --- powers through hotkeys and the toolbar
	_key(KEY_5, true)
	_key(KEY_5, false)
	await _frames(2)
	_check("input: key 5 selects Create Life", powers.current_id() == "villager", "current=%s" % powers.current_id())
	rig.set_view(t0.center + Vector3(3, 0, 3), 30.0, 0.8, 0.9, true)
	await _frames(10)
	var pop0 := sim.population()
	powers.cooldown = 0.0
	var ground = powers.pick(center)
	_mouse_button(MOUSE_BUTTON_LEFT, center, true)
	await _frames(1)
	_mouse_button(MOUSE_BUTTON_LEFT, center, false)
	await _frames(3)
	_check("input: click casts power", sim.population() >= pop0 + 3, "pop %d -> %d (ground=%s)" % [pop0, sim.population(), ground])
	await _shot("23_input_spawn")
	_key(KEY_1, true)
	_key(KEY_1, false)
	_key(KEY_B, true)
	_key(KEY_B, false)
	await _frames(2)
	_check("input: B toggles land mode", powers.land_mode == "tile", "mode=%s" % powers.land_mode)
	_key(KEY_B, true)
	_key(KEY_B, false)
	var b0 := powers.brush
	_key(KEY_BRACKETRIGHT, true)
	_key(KEY_BRACKETRIGHT, false)
	await _frames(1)
	_check("input: ] grows the brush", powers.brush > b0, "%.0f -> %.0f" % [b0, powers.brush])
	var btn: Button = m.hud.power_buttons[powers.index_of("meteor")]
	var bc := btn.get_global_rect().get_center()
	Input.warp_mouse(bc)
	_mouse_button(MOUSE_BUTTON_LEFT, bc, true)
	_mouse_button(MOUSE_BUTTON_LEFT, bc, false)
	await _frames(2)
	_check("input: clicking toolbar icon selects power", powers.current_id() == "meteor", "current=%s" % powers.current_id())
	Input.warp_mouse(center)
	_motion(center, Vector2.ZERO, 0)
	await _frames(2)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(1)
	_check("input: Esc returns to the God Hand", powers.current == -1, "")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames(2)
	_check("input: space pauses", m.speed_idx == 0, "speed=%s" % m.speed_name())
	_key(KEY_EQUAL, true)
	_key(KEY_EQUAL, false)
	await _frames(1)
	_check("input: + speeds up", m.speed_idx == 1, "speed=%s" % m.speed_name())
	print("INFO fps under this renderer: %.1f" % Engine.get_frames_per_second())

func _key(k: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)

func _motion(pos: Vector2, rel: Vector2, mask: int) -> void:
	Input.warp_mouse(pos)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.relative = rel
	mm.button_mask = mask
	Input.parse_input_event(mm)

func _mouse_button(b: MouseButton, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.position = pos
	e.global_position = pos
	e.pressed = pressed
	Input.warp_mouse(pos)
	Input.parse_input_event(e)

# ---------------------------------------------------------------- demo
## Scripted gameplay for a recording (`tools/record_demo.sh`).
func _demo() -> void:
	m.hud.splash.visible = false
	sim.religion.sandbox = true
	m.hud.set_sandbox(true)
	sim.prewarm(400.0)
	terrain_flush()
	var t0: WorldSim.Tribe = _biggest()
	m.set_speed(1)
	# 1. glide over the village, hand hovering
	rig.set_view(t0.center + Vector3(-10, 0, 8), 34.0, 0.6, 0.75, true)
	for i in 60:
		rig.focus = (t0.center + Vector3(-10, 0, 8)).lerp(t0.center, i / 60.0)
		_point_at(t0.center + Vector3(sin(i * 0.1) * 4.0, 0, cos(i * 0.1) * 3.0))
		await _frames(1)
	# 2. pick up a villager, carry, set down
	var v := _adult(t0)
	v._reset(8.0)
	for i in 20:
		_point_at(v.position)
		await _frames(1)
	hand.press()
	var dest := t0.center + Vector3(6, 0, -5)
	for i in 50:
		_point_at(v.position.lerp(dest, 0.08))
		await _frames(1)
	hand.release()
	await _frames(25)
	# 3. throw one
	var v2 := _adult(t0)
	for i in 15:
		_point_at(v2.position)
		await _frames(1)
	hand.press()
	await _frames(14)
	var from := hand.hand_pos
	for i in 5:
		_point_at(from + Vector3(1.8 * (i + 1), 0, 0.5 * (i + 1)))
		await _frames(1)
	hand.release()
	for i in 40:
		rig.focus = rig.focus.lerp(v2.position, 0.08)
		await _frames(1)
	# 4. paint new land out at sea
	var sea := Vector3(-80, 0, -78)
	rig.set_view(sea, 70.0, 0.5, 0.95, true)
	powers.select(powers.index_of("land"))
	powers.set_brush(8.0)
	for i in 90:
		var p := sea + Vector3(cos(i * 0.07) * 14.0, 0, sin(i * 0.09) * 10.0)
		_point_at(p)
		powers.cast("land", p, 1.0 / 30.0)
		await _frames(1)
	# 5. tiles
	powers.toggle_land_mode()
	var tb := Vector3(70, 0, 82)
	rig.set_view(tb + Vector3(6, 0, 0), 55.0, 0.4, 0.9, true)
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(-1, 0)]:
		var p: Vector3 = tb + Vector3(c.x * Terrain.TILE, 0, c.y * Terrain.TILE)
		_point_at(p)
		powers._last_tile = Vector3(INF, 0, INF)
		powers.cast("land", p, 0.0)
		await _frames(8)
	powers.toggle_land_mode()
	# 6. miracles and smiting
	powers.select(powers.index_of("rain"))
	rig.set_view(t0.center, 40.0, 1.0, 0.65, true)
	_point_at(t0.center)
	await _frames(6)
	powers.cast("rain", t0.center, 0.0)
	await _frames(45)
	powers.select(powers.index_of("lightning"))
	var tree = sim.find_nearest(t0.center + Vector3(10, 0, 0), WorldSim.RES_TREE, 40.0)
	if tree != null:
		_point_at(tree.pos)
		await _frames(8)
		powers.cast("lightning", tree.pos, 0.0)
		await _frames(30)
	powers.select(powers.index_of("meteor"))
	var t2: WorldSim.Tribe = sim.live_tribes()[sim.live_tribes().size() - 1]
	rig.set_view(t2.center, 55.0, 1.4, 0.65, true)
	_point_at(t2.center)
	await _frames(6)
	powers.cast("meteor", t2.center, 0.0)
	await _frames(70)
	print("DEMO DONE")
	get_tree().quit()
