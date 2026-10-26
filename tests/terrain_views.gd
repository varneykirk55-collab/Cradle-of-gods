extends Node
## Fixed-camera terrain / coastline views for before-and-after comparisons:
##   godot --path . --rendering-driver opengl3 -- --views [--outdir=screenshots/views]
## Uses world seed 4242 and a short prewarm, so the same viewpoints render
## the same world on every build. Picks the mountain / coast spots from the
## heightmap itself so it does not depend on hand-tuned coordinates.

var m
var outdir := "res://screenshots/views"

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	var path := ProjectSettings.globalize_path("%s/%s.png" % [outdir, name])
	img.save_png(path)
	print("SCREENSHOT ", path)

func run(p_main) -> void:
	m = p_main
	for a in m.args:
		if a.begins_with("--outdir="): outdir = "res://" + a.substr(9)
	m.hud.splash.visible = false
	m.hud.visible = false
	for c in m.hud.get_children():
		if c is CanvasItem: c.visible = false
	m.hand.visible = false
	m.set_speed(0)
	m.sim.prewarm(240.0)
	_flush()
	var t: Terrain = m.terrain
	var rig: CameraRig = m.rig
	# highest peak, and the land cell nearest the island edge toward +z / +x
	var peak := Vector3.ZERO
	var peak_h := -INF
	for z in range(0, Terrain.SIZE, 2):
		for x in range(0, Terrain.SIZE, 2):
			var h := t.grid_h(x, z)
			if h > peak_h:
				peak_h = h
				peak = Vector3(x - Terrain.HALF, h, z - Terrain.HALF)
	var coast := _coast_toward(Vector2(0.55, 0.83))
	var coast2 := _coast_toward(Vector2(-0.9, 0.1))
	var tribe = m.sim.live_tribes()[0] if not m.sim.live_tribes().is_empty() else null
	var views := [
		["01_overview", Vector3.ZERO, 200.0, 0.6, 1.0],
		["02_overview_oblique", Vector3(0, 0, 10), 150.0, 0.6, 0.55],
		["03_mountain", peak, 70.0, 2.4, 0.5],
		["04_mountain_low", peak + Vector3(10, 0, 10), 50.0, 0.9, 0.32],
		["05_coast", coast, 40.0, atan2(coast.x, coast.z) + 0.6, 0.45],
		["06_coast_low", coast2, 30.0, atan2(coast2.x, coast2.z) + 0.3, 0.3],
		["07_meadow", _meadow(), 35.0, 1.3, 0.55],
	]
	if tribe:
		views.append(["08_village_above", tribe.center, 45.0, 0.7, 1.05])
	m.hud.visible = false
	for v in views:
		rig.set_view(v[1], v[2], v[3], v[4], true)
		await _frames(10)
		await _shot(v[0])
	# runtime-created land: brush island + tiles out at sea
	var sea := Vector3(-80, 0, -78)
	for i in 90:
		var p := sea + Vector3(cos(i * 0.07) * 14.0, 0, sin(i * 0.09) * 10.0)
		t.paint_land(p, 9.0, 1.0 / 20.0)
	var tb := Vector3(70, 0, 82)
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(2, 2), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(-2, -1)]:
		t.place_tile(tb + Vector3(c.x * Terrain.TILE, 0, c.y * Terrain.TILE))
	for i in 40:
		t.modify(sea + Vector3(-4, 0, 2), 5.0, 0.35)
	_flush()
	rig.set_view(sea, 60.0, 0.5, 0.6, true)
	await _frames(10)
	await _shot("09_created_island")
	rig.set_view(sea + Vector3(10, 0, 8), 28.0, 0.5, 0.35, true)
	await _frames(10)
	await _shot("10_created_island_low")
	rig.set_view(tb + Vector3(6, 0, 0), 50.0, 0.4, 0.7, true)
	await _frames(10)
	await _shot("11_created_tiles")
	if "--bench" in m.args:
		await _bench("overview", Vector3.ZERO, 200.0, 0.6, 1.0)
		if tribe: await _bench("village", tribe.center, 35.0, 0.7, 0.8)
		await _bench("coast", coast, 40.0, atan2(coast.x, coast.z) + 0.6, 0.45)
	print("VIEWS DONE")
	get_tree().quit(0)

func _flush() -> void:
	m.terrain.rebuild_dirty(true)
	m.sim.nav.flush()

func _coast_toward(dir: Vector2) -> Vector3:
	var d := dir.normalized()
	var last := Vector3.ZERO
	for i in 220:
		var p := Vector3(d.x * i * 0.5, 0, d.y * i * 0.5)
		if not m.terrain.in_bounds(p.x, p.z): break
		if m.terrain.is_land(p.x, p.z):
			last = p
	last.y = maxf(m.terrain.height_at(last.x, last.z), 0.0)
	return last

func _meadow() -> Vector3:
	var best := Vector3.ZERO
	var best_s := INF
	for z in range(-60, 60, 6):
		for x in range(-60, 60, 6):
			var h: float = m.terrain.height_at(x, z)
			if h < 1.5 or h > 7.0: continue
			var s: float = m.terrain.slope_at(x, z) + absf(h - 3.5) * 0.1 + Vector2(x, z).length() * 0.004
			if s < best_s:
				best_s = s
				best = Vector3(x, h, z)
	return best

## Average real frame time over 60 frames at a fixed view (after 10 warm-up frames).
func _bench(name: String, focus: Vector3, dist: float, yaw: float, pitch: float) -> void:
	m.rig.set_view(focus, dist, yaw, pitch, true)
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	await _frames(60)
	var ms := (Time.get_ticks_usec() - t0) / 60000.0
	print("BENCH %s %.1f ms/frame (%.1f fps)" % [name, ms, 1000.0 / ms])
