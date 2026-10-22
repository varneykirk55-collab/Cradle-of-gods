class_name Terrain
extends Node3D
## Procedural heightmap terrain: chunked flat-shaded low-poly mesh with biome
## vertex colours, plus a HeightMapShape3D collider kept in sync with edits.
## The generated island sits in the middle of a wider ocean so the player can
## raise new islands, peninsulas and continents (paint_land / place_tile).

signal terrain_changed(center: Vector3, radius: float)

const SIZE := 224          # cells per side
const CHUNK := 32          # cells per chunk side
const SEA := 0.0
const HALF := 112.0
const W := SIZE + 1        # vertices per side
const MIN_H := -14.0
const MAX_H := 34.0
const ISLAND_R := 80.0     # radius of the procedurally generated starting island
const LAND_H := 1.7        # resting height of freshly created land
const SHELF_H := -2.6      # continental shelf height around created land
const TILE := 6            # cells per placement tile
const COLLISION_INTERVAL := 0.12

enum Biome { DEEP, SHALLOW, BEACH, DRY, GRASS, FOREST, ALPINE, ROCK, SNOW }

var heights := PackedFloat32Array()
var moisture := PackedFloat32Array()
var fertility := PackedFloat32Array()   # -1 scorched .. +1 lush
var chunk_nodes := {}
var dirty := {}
var collision_dirty := false
var _collision_t := 0.0
var version := 0           # bumped on every height edit (path caches compare against it)
var detail := FastNoiseLite.new()
var mat := StandardMaterial3D.new()
var body := StaticBody3D.new()
var shape := HeightMapShape3D.new()
var seed_value := 0

func _ready() -> void:
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

func generate(p_seed: int) -> void:
	seed_value = p_seed
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	var ridge := FastNoiseLite.new()
	ridge.seed = p_seed + 7
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.frequency = 0.018
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = p_seed + 31
	mn.frequency = 0.02
	mn.fractal_octaves = 3
	detail.seed = p_seed + 57
	detail.frequency = 0.09
	detail.fractal_octaves = 2
	heights.resize(W * W)
	moisture.resize(W * W)
	fertility.resize(W * W)
	var off := HALF - ISLAND_R   # keep the same island shape per seed as the original 160-cell world
	for z in W:
		for x in W:
			var nx := (float(x) - HALF) / ISLAND_R
			var nz := (float(z) - HALF) / ISLAND_R
			var d := sqrt(nx * nx + nz * nz)
			var e := n.get_noise_2d(x - off, z - off) * 0.5 + 0.5
			var mask := 1.0 - pow(clampf(d * 1.08, 0.0, 1.5), 2.4)
			var v := e * 0.85 + mask * 0.75 - 0.78
			var h := v * 26.0
			if h > 2.5:
				var r := ridge.get_noise_2d(x - off, z - off) * 0.5 + 0.5
				h += pow(r, 2.2) * (h - 2.5) * 2.2
			if h < SEA:
				h = h * 1.4
			var i := z * W + x
			heights[i] = clampf(h, MIN_H, MAX_H)
			moisture[i] = clampf(mn.get_noise_2d(x - off, z - off) * 0.75 + 0.5, 0.0, 1.0)
			fertility[i] = 0.0
	for cz in SIZE / CHUNK:
		for cx in SIZE / CHUNK:
			_build_chunk(Vector2i(cx, cz))
	_update_collision()

# ---------------------------------------------------------------- queries
func grid_h(x: int, z: int) -> float:
	return heights[clampi(z, 0, SIZE) * W + clampi(x, 0, SIZE)]

func height_at(wx: float, wz: float) -> float:
	var gx := clampf(wx + HALF, 0.0, SIZE - 0.001)
	var gz := clampf(wz + HALF, 0.0, SIZE - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var a := heights[z0 * W + x0]
	var b := heights[z0 * W + x0 + 1]
	var c := heights[(z0 + 1) * W + x0]
	var d := heights[(z0 + 1) * W + x0 + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func moisture_at(wx: float, wz: float) -> float:
	var x := clampi(int(round(wx + HALF)), 0, SIZE)
	var z := clampi(int(round(wz + HALF)), 0, SIZE)
	return moisture[z * W + x]

func fertility_at(wx: float, wz: float) -> float:
	var x := clampi(int(round(wx + HALF)), 0, SIZE)
	var z := clampi(int(round(wz + HALF)), 0, SIZE)
	return fertility[z * W + x]

func slope_at(wx: float, wz: float) -> float:
	var hx := height_at(wx + 0.5, wz) - height_at(wx - 0.5, wz)
	var hz := height_at(wx, wz + 0.5) - height_at(wx, wz - 0.5)
	return sqrt(hx * hx + hz * hz)

func in_bounds(wx: float, wz: float, margin := 2.0) -> bool:
	return absf(wx) < HALF - margin and absf(wz) < HALF - margin

func is_land(wx: float, wz: float) -> bool:
	return height_at(wx, wz) > SEA + 0.35

func biome_at(wx: float, wz: float) -> int:
	var h := height_at(wx, wz)
	return _biome(h, slope_at(wx, wz), moisture_at(wx, wz))

func _biome(h: float, slope: float, m: float) -> int:
	if h < SEA - 3.0: return Biome.DEEP
	if h < SEA: return Biome.SHALLOW
	if h < SEA + 0.8: return Biome.BEACH
	if h > 17.0 and slope < 2.2: return Biome.SNOW
	if slope > 1.35 or h > 12.0: return Biome.ROCK
	if h > 8.0: return Biome.ALPINE
	if m < 0.33: return Biome.DRY
	if m > 0.6: return Biome.FOREST
	return Biome.GRASS

func biome_color(h: float, slope: float, m: float, fert: float, rnd: float) -> Color:
	var c: Color
	var b := _biome(h, slope, m)
	match b:
		Biome.DEEP, Biome.SHALLOW:
			var depth := clampf((SEA - h) / 9.0, 0.0, 1.0)
			c = Color(0.86, 0.80, 0.56).lerp(Color(0.08, 0.30, 0.40), depth)
		Biome.BEACH:
			c = Color(0.93, 0.85, 0.60)
		Biome.SNOW:
			c = Color(0.95, 0.96, 0.99)
		Biome.ROCK:
			c = Color(0.47, 0.44, 0.41).lerp(Color(0.38, 0.36, 0.38), clampf((h - 6.0) / 14.0, 0.0, 1.0))
			if h > 15.0:
				c = c.lerp(Color(0.92, 0.93, 0.96), clampf((h - 15.0) / 6.0, 0.0, 0.8))
		Biome.ALPINE:
			c = Color(0.38, 0.50, 0.28).lerp(Color(0.47, 0.48, 0.36), clampf((h - 8.0) / 4.0, 0.0, 1.0))
		Biome.DRY:
			c = Color(0.72, 0.68, 0.40).lerp(Color(0.50, 0.60, 0.30), m / 0.33)
		Biome.GRASS:
			c = Color(0.45, 0.58, 0.29).lerp(Color(0.35, 0.52, 0.25), (m - 0.33) / 0.27)
		_:
			c = Color(0.27, 0.47, 0.22).lerp(Color(0.21, 0.40, 0.19), clampf((m - 0.6) / 0.4, 0.0, 1.0))
	if b != Biome.DEEP and b != Biome.SHALLOW and b != Biome.SNOW:
		if fert > 0.0:
			c = c.lerp(Color(0.22, 0.58, 0.20), fert * 0.55)
		elif fert < 0.0:
			c = c.lerp(Color(0.16, 0.12, 0.10), -fert * 0.9)
	return c * (0.93 + rnd * 0.12)

# ---------------------------------------------------------------- mesh
func _build_chunk(key: Vector2i) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var n_tris := CHUNK * CHUNK * 2
	verts.resize(n_tris * 3)
	norms.resize(n_tris * 3)
	cols.resize(n_tris * 3)
	var k := 0
	for z in range(key.y * CHUNK, (key.y + 1) * CHUNK):
		for x in range(key.x * CHUNK, (key.x + 1) * CHUNK):
			var pa := Vector3(x - HALF, heights[z * W + x], z - HALF)
			var pb := Vector3(x + 1 - HALF, heights[z * W + x + 1], z - HALF)
			var pc := Vector3(x - HALF, heights[(z + 1) * W + x], z + 1 - HALF)
			var pd := Vector3(x + 1 - HALF, heights[(z + 1) * W + x + 1], z + 1 - HALF)
			var mo := (moisture[z * W + x] + moisture[(z + 1) * W + x + 1]) * 0.5
			var fe := (fertility[z * W + x] + fertility[(z + 1) * W + x + 1]) * 0.5
			if (x + z) % 2 == 0:
				k = _tri(verts, norms, cols, k, pa, pb, pd, mo, fe, x * 7 + z * 13)
				k = _tri(verts, norms, cols, k, pa, pd, pc, mo, fe, x * 11 + z * 5 + 3)
			else:
				k = _tri(verts, norms, cols, k, pa, pb, pc, mo, fe, x * 7 + z * 13)
				k = _tri(verts, norms, cols, k, pb, pd, pc, mo, fe, x * 11 + z * 5 + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	var mi: MeshInstance3D = chunk_nodes.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(mi)
		chunk_nodes[key] = mi
	mi.mesh = am

func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, k: int,
		p0: Vector3, p1: Vector3, p2: Vector3, mo: float, fe: float, hseed: int) -> int:
	var nrm := (p1 - p0).cross(p2 - p0)
	if nrm.y > 0.0:
		# Godot uses clockwise front faces: swap to keep the top face facing up.
		var t := p1
		p1 = p2
		p2 = t
	else:
		nrm = -nrm
	nrm = nrm.normalized()
	var h := (p0.y + p1.y + p2.y) / 3.0
	var slope := sqrt(maxf(0.0, 1.0 - nrm.y * nrm.y)) / maxf(nrm.y, 0.05)
	var rnd := float((hseed * 2654435761) & 1023) / 1023.0
	var c := biome_color(h, slope, mo, fe, rnd)
	verts[k] = p0; verts[k + 1] = p1; verts[k + 2] = p2
	norms[k] = nrm; norms[k + 1] = nrm; norms[k + 2] = nrm
	cols[k] = c; cols[k + 1] = c; cols[k + 2] = c
	return k + 3

func _update_collision() -> void:
	shape.map_width = W
	shape.map_depth = W
	shape.map_data = heights
	collision_dirty = false
	_collision_t = COLLISION_INTERVAL

func _mark(x: int, z: int) -> void:
	var cxs := [mini(x / CHUNK, SIZE / CHUNK - 1)]
	var czs := [mini(z / CHUNK, SIZE / CHUNK - 1)]
	if x % CHUNK == 0 and x > 0: cxs.append(x / CHUNK - 1)
	if z % CHUNK == 0 and z > 0: czs.append(z / CHUNK - 1)
	for cx in cxs:
		for cz in czs:
			dirty[Vector2i(cx, cz)] = true

## Rebuilds the dirty chunk meshes; the collider is refreshed at most every
## COLLISION_INTERVAL seconds while the player keeps painting (force = now).
func rebuild_dirty(force := true) -> void:
	for key in dirty.keys():
		_build_chunk(key)
	dirty.clear()
	if collision_dirty and (force or _collision_t <= 0.0):
		_update_collision()

func _process(dt: float) -> void:
	_collision_t -= dt
	if not dirty.is_empty() or collision_dirty:
		rebuild_dirty(false)

# ---------------------------------------------------------------- edits
func modify(center: Vector3, radius: float, amount: float) -> void:
	var gx := center.x + HALF
	var gz := center.z + HALF
	var r := int(ceil(radius))
	for z in range(maxi(0, int(gz) - r), mini(W, int(gz) + r + 2)):
		for x in range(maxi(0, int(gx) - r), mini(W, int(gx) + r + 2)):
			var d := Vector2(x - gx, z - gz).length()
			if d > radius: continue
			var f := 1.0 - d / radius
			f = f * f * (3.0 - 2.0 * f)
			var i := z * W + x
			heights[i] = clampf(heights[i] + amount * f, MIN_H, MAX_H)
			_mark(x, z)
	_edited(center, radius)

func _edited(center: Vector3, radius: float) -> void:
	collision_dirty = true
	version += 1
	terrain_changed.emit(center, radius)

## Natural coastline wobble in world units (continuous, so neighbouring strokes match).
func _coast_noise(wx: float, wz: float) -> float:
	return detail.get_noise_2d(wx, wz)

## Pull every cell in the brush toward `target`, never past it (rate is per second).
func _approach(i: int, target: float, k: float) -> void:
	heights[i] = clampf(lerpf(heights[i], target, clampf(k, 0.0, 1.0)), MIN_H, MAX_H)

## Mode A: paint land up out of the sea. Cells inside the (noise-wobbled) brush
## rise toward LAND_H (+ gentle hills); a wider ring is lifted to a shallow
## shelf so the new coast gets a beach instead of a cliff into deep water.
func paint_land(center: Vector3, radius: float, dt: float) -> void:
	var gx := center.x + HALF
	var gz := center.z + HALF
	var outer := radius * 1.7
	var r := int(ceil(outer))
	var k := 1.0 - exp(-dt * 6.0)
	for z in range(maxi(1, int(gz) - r), mini(W - 1, int(gz) + r + 2)):
		for x in range(maxi(1, int(gx) - r), mini(W - 1, int(gx) + r + 2)):
			var wx := x - HALF
			var wz := z - HALF
			var d := Vector2(x - gx, z - gz).length() + _coast_noise(wx * 1.3, wz * 1.3) * radius * 0.35
			if d > outer: continue
			var i := z * W + x
			if d <= radius:
				var f := 1.0 - d / radius
				var target := LAND_H + (_coast_noise(wx * 0.6 + 40.0, wz * 0.6) * 0.5 + 0.5) * 1.6 * f
				if heights[i] < target:
					_approach(i, target, k * (0.35 + 0.65 * smoothstep(0.0, 0.35, f)))
			else:
				var f2 := 1.0 - (d - radius) / (outer - radius)
				var shelf := lerpf(SHELF_H - 2.0, SEA - 0.4, f2 * f2)
				if heights[i] < shelf:
					_approach(i, shelf, k * 0.8)
			_mark(x, z)
	_edited(center, outer)

## Mode B: place one square tile of land snapped to the TILE grid. Tiles share
## the same height function, so neighbours join without seams; each tile also
## lifts a shelf skirt around itself.
func place_tile(center: Vector3) -> Vector3:
	var cx := int(floor((center.x + HALF) / TILE)) * TILE
	var cz := int(floor((center.z + HALF) / TILE)) * TILE
	var skirt := 3
	for z in range(maxi(1, cz - skirt), mini(W - 1, cz + TILE + skirt + 1)):
		for x in range(maxi(1, cx - skirt), mini(W - 1, cx + TILE + skirt + 1)):
			var wx := x - HALF
			var wz := z - HALF
			var i := z * W + x
			var dx := maxi(maxi(cx - x, x - (cx + TILE)), 0)
			var dz := maxi(maxi(cz - z, z - (cz + TILE)), 0)
			var out := sqrt(float(dx * dx + dz * dz))
			if out <= 0.0:
				var target := LAND_H + (_coast_noise(wx * 0.6 + 40.0, wz * 0.6) * 0.5 + 0.5) * 0.9
				heights[i] = maxf(heights[i], target)
			else:
				var f := 1.0 - out / float(skirt + 1)
				var shelf := lerpf(SHELF_H - 1.5, SEA - 0.25, f)
				heights[i] = maxf(heights[i], shelf)
			_mark(x, z)
	var c := Vector3(cx + TILE * 0.5 - HALF, 0, cz + TILE * 0.5 - HALF)
	c.y = height_at(c.x, c.z)
	_edited(c, TILE + skirt)
	return c

## Return land to the ocean: cells sink toward a shallow sea bed.
func remove_land(center: Vector3, radius: float, dt: float) -> void:
	var gx := center.x + HALF
	var gz := center.z + HALF
	var r := int(ceil(radius))
	var k := 1.0 - exp(-dt * 5.0)
	for z in range(maxi(0, int(gz) - r), mini(W, int(gz) + r + 2)):
		for x in range(maxi(0, int(gx) - r), mini(W, int(gx) + r + 2)):
			var d := Vector2(x - gx, z - gz).length()
			if d > radius: continue
			var f := 1.0 - d / radius
			f = f * f * (3.0 - 2.0 * f)
			var i := z * W + x
			var target := SHELF_H - 1.5 * f
			if heights[i] > target:
				_approach(i, target, k * (0.3 + 0.7 * f))
			_mark(x, z)
	_edited(center, radius)

## Level the ground under a building toward its average height.
func flatten(center: Vector3, radius: float, strength := 0.7) -> void:
	var gx := center.x + HALF
	var gz := center.z + HALF
	var r := int(ceil(radius))
	var sum := 0.0
	var cnt := 0
	for z in range(maxi(0, int(gz) - r), mini(W, int(gz) + r + 2)):
		for x in range(maxi(0, int(gx) - r), mini(W, int(gx) + r + 2)):
			if Vector2(x - gx, z - gz).length() <= radius:
				sum += heights[z * W + x]
				cnt += 1
	if cnt == 0: return
	var avg := maxf(sum / cnt, SEA + 0.9)
	for z in range(maxi(0, int(gz) - r), mini(W, int(gz) + r + 2)):
		for x in range(maxi(0, int(gx) - r), mini(W, int(gx) + r + 2)):
			var d := Vector2(x - gx, z - gz).length()
			if d > radius: continue
			var f := strength * clampf(1.2 - d / radius, 0.0, 1.0)
			var i := z * W + x
			heights[i] = lerpf(heights[i], avg, f)
			_mark(x, z)
	_edited(center, radius)

func land_area() -> int:
	var n := 0
	for h in heights:
		if h > SEA + 0.35: n += 1
	return n

func add_fertility(center: Vector3, radius: float, amount: float) -> void:
	var gx := center.x + HALF
	var gz := center.z + HALF
	var r := int(ceil(radius))
	for z in range(maxi(0, int(gz) - r), mini(W, int(gz) + r + 2)):
		for x in range(maxi(0, int(gx) - r), mini(W, int(gx) + r + 2)):
			var d := Vector2(x - gx, z - gz).length()
			if d > radius: continue
			var f := 1.0 - d / radius
			var i := z * W + x
			fertility[i] = clampf(fertility[i] + amount * f, -1.0, 1.0)
			_mark(x, z)

## Ray-march fallback for picking (used if physics ray misses).
func raycast(from: Vector3, dir: Vector3, max_dist := 600.0) -> Variant:
	var t := 0.0
	var step := 0.5
	while t < max_dist:
		var p := from + dir * t
		if absf(p.x) <= HALF and absf(p.z) <= HALF and p.y <= height_at(p.x, p.z):
			return p
		t += step
	return null
