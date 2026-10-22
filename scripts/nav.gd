class_name NavGrid
extends RefCounted
## Walkability grid over the terrain vertices, backed by Godot's native
## AStarGrid2D. Water and cliffs are solid, slopes and building footprints cost
## more. Terrain edits only refresh the touched rectangle. A flood-filled
## "island id" per cell gives O(1) reachability checks, so villagers never
## chase targets across open sea.

const STEEP := 2.2           # max height step between neighbouring cells
const ISLAND_INTERVAL := 0.8

var terrain: Terrain
var astar := AStarGrid2D.new()
var island := PackedInt32Array()
var island_sizes := {}
var _dirty_rect := Rect2i()
var _has_dirty := false
var _island_dirty := true
var _island_t := 0.0
var _footprints := {}        # cell -> extra weight from buildings
var paths_this_step := 0
var stats := {"paths": 0, "partial": 0, "updates": 0}
const PATH_BUDGET := 8       # path queries per simulation step

func setup(p_terrain: Terrain) -> void:
	terrain = p_terrain
	astar.region = Rect2i(0, 0, Terrain.W, Terrain.W)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	island.resize(Terrain.W * Terrain.W)
	_refresh(Rect2i(0, 0, Terrain.W, Terrain.W))
	_flood_islands()
	terrain.terrain_changed.connect(_on_terrain_changed)

static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(round(p.x + Terrain.HALF)), 0, Terrain.SIZE), clampi(int(round(p.z + Terrain.HALF)), 0, Terrain.SIZE))

static func world_of(c: Vector2i) -> Vector3:
	return Vector3(c.x - Terrain.HALF, 0.0, c.y - Terrain.HALF)

func walkable_cell(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)

func walkable(p: Vector3) -> bool:
	return walkable_cell(cell_of(p))

func island_of(p: Vector3) -> int:
	var c := cell_of(p)
	return island[c.y * Terrain.W + c.x]

## True when both points are on the same connected landmass.
func connected(a: Vector3, b: Vector3) -> bool:
	var ia := island_of(a)
	return ia > 0 and ia == _island_near(b)

## Island of p, or of a walkable neighbour (targets like halls sit on costly cells).
func _island_near(p: Vector3) -> int:
	var c := cell_of(p)
	var id := island[c.y * Terrain.W + c.x]
	if id > 0: return id
	for r in [1, 2, 3]:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if astar.is_in_boundsv(n):
					var j := island[n.y * Terrain.W + n.x]
					if j > 0: return j
	return 0

func _cell_solid(x: int, z: int) -> bool:
	var h := terrain.grid_h(x, z)
	if h <= Terrain.SEA + 0.35: return true   # same threshold as Terrain.is_land
	if x <= 1 or z <= 1 or x >= Terrain.SIZE - 1 or z >= Terrain.SIZE - 1: return true
	var m := 0.0
	m = maxf(m, absf(terrain.grid_h(x + 1, z) - h))
	m = maxf(m, absf(terrain.grid_h(x - 1, z) - h))
	m = maxf(m, absf(terrain.grid_h(x, z + 1) - h))
	m = maxf(m, absf(terrain.grid_h(x, z - 1) - h))
	return m > STEEP

func _cell_weight(x: int, z: int) -> float:
	var h := terrain.grid_h(x, z)
	var s := absf(terrain.grid_h(x + 1, z) - terrain.grid_h(x - 1, z)) + absf(terrain.grid_h(x, z + 1) - terrain.grid_h(x, z - 1))
	var w := 1.0 + s * 0.9
	if h < Terrain.SEA + 0.6: w += 0.6   # prefer not to hug the shoreline
	return w + _footprints.get(Vector2i(x, z), 0.0)

func _refresh(r: Rect2i) -> void:
	r = r.intersection(Rect2i(0, 0, Terrain.W, Terrain.W))
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, z)
			var solid := _cell_solid(x, z)
			astar.set_point_solid(c, solid)
			if not solid:
				astar.set_point_weight_scale(c, _cell_weight(x, z))
	stats["updates"] += 1

func _on_terrain_changed(center: Vector3, radius: float) -> void:
	var c := cell_of(center)
	var r := int(ceil(radius)) + 2
	var rect := Rect2i(c.x - r, c.y - r, r * 2 + 1, r * 2 + 1)
	_dirty_rect = rect if not _has_dirty else _dirty_rect.merge(rect)
	_has_dirty = true

## Buildings make their footprint expensive (not solid, so their own door stays reachable).
func set_footprint(center: Vector3, radius: float, on: bool) -> void:
	var c := cell_of(center)
	var r := int(ceil(radius))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() > radius: continue
			var k := c + Vector2i(dx, dz)
			if not astar.is_in_boundsv(k): continue
			if on: _footprints[k] = 6.0
			else: _footprints.erase(k)
			if not astar.is_point_solid(k):
				astar.set_point_weight_scale(k, _cell_weight(k.x, k.y))

## Call once per frame/step: applies pending terrain edits, re-floods islands.
func tick(dt: float) -> void:
	paths_this_step = 0
	if _has_dirty:
		_refresh(_dirty_rect)
		_has_dirty = false
		_island_dirty = true
	_island_t -= dt
	if _island_dirty and _island_t <= 0.0:
		_flood_islands()

func flush() -> void:
	if _has_dirty:
		_refresh(_dirty_rect)
		_has_dirty = false
	_flood_islands()

func _flood_islands() -> void:
	_island_dirty = false
	_island_t = ISLAND_INTERVAL
	island.fill(0)
	island_sizes.clear()
	var next := 1
	var Wd := Terrain.W
	var queue := PackedInt32Array()
	for start in Wd * Wd:
		if island[start] != 0: continue
		var sx := start % Wd
		var sz := start / Wd
		if astar.is_point_solid(Vector2i(sx, sz)):
			island[start] = -1
			continue
		island[start] = next
		queue.resize(0)
		queue.append(start)
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			var x := i % Wd
			var z := i / Wd
			for n in [i - 1, i + 1, i - Wd, i + Wd]:
				if n < 0 or n >= Wd * Wd: continue
				if island[n] != 0: continue
				var nx: int = n % Wd
				if absi(nx - x) > 1: continue
				if astar.is_point_solid(Vector2i(nx, n / Wd)):
					island[n] = -1
				else:
					island[n] = next
					queue.append(n)
		island_sizes[next] = queue.size()
		next += 1

func can_path() -> bool:
	return paths_this_step < PATH_BUDGET

## World-space waypoints from a to b (simplified), or [] if unreachable.
## The last point is the closest reachable spot when b itself is blocked.
func find_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	paths_this_step += 1
	stats["paths"] += 1
	var out := PackedVector3Array()
	var ca := _nearest_open(cell_of(a))
	var cb := _nearest_open(cell_of(b))
	if ca.x < 0 or cb.x < 0: return out
	var ids := astar.get_id_path(ca, cb, true)
	if ids.is_empty(): return out
	if ids[ids.size() - 1] != cb: stats["partial"] += 1
	# keep only the cells where the direction changes
	var prev_dir := Vector2i.ZERO
	for i in ids.size():
		if i > 0 and i < ids.size() - 1:
			var d: Vector2i = ids[i + 1] - ids[i]
			if d == prev_dir:
				continue
			prev_dir = d
		elif i == 0 and ids.size() > 1:
			prev_dir = ids[1] - ids[0]
		out.append(world_of(ids[i]))
	return out

func _nearest_open(c: Vector2i) -> Vector2i:
	if walkable_cell(c): return c
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r: continue
				var n := c + Vector2i(dx, dz)
				if walkable_cell(n): return n
	return Vector2i(-1, -1)

## Quick straight-line check (sampled every metre) used before asking A*.
func line_clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length())
	for i in range(1, n + 1):
		var t := float(i) / float(n + 1)
		if not walkable(a.lerp(b, t)): return false
	return true

func nearest_walkable(p: Vector3, max_r := 6) -> Variant:
	var c := _nearest_open(cell_of(p))
	if c.x < 0:
		return null
	var w := world_of(c)
	if Vector2(w.x - p.x, w.z - p.z).length() > max_r: return null
	return w
