class_name Terrain
extends Node3D
## Procedural heightmap terrain: chunked flat-shaded low-poly mesh with biome
## vertex colours, plus a HeightMapShape3D collider kept in sync with edits.

signal terrain_changed(center: Vector3, radius: float)

const SIZE := 160          # cells per side
const CHUNK := 32          # cells per chunk side
const SEA := 0.0
const HALF := 80.0
const W := SIZE + 1        # vertices per side
const MIN_H := -14.0
const MAX_H := 34.0

enum Biome { DEEP, SHALLOW, BEACH, DRY, GRASS, FOREST, ALPINE, ROCK, SNOW }

var heights := PackedFloat32Array()
var moisture := PackedFloat32Array()
var fertility := PackedFloat32Array()   # -1 scorched .. +1 lush
var chunk_nodes := {}
var dirty := {}
var collision_dirty := false
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
	heights.resize(W * W)
	moisture.resize(W * W)
	fertility.resize(W * W)
	for z in W:
		for x in W:
			var nx := float(x) / SIZE * 2.0 - 1.0
			var nz := float(z) / SIZE * 2.0 - 1.0
			var d := sqrt(nx * nx + nz * nz)
			var e := n.get_noise_2d(x, z) * 0.5 + 0.5
			var mask := 1.0 - pow(clampf(d * 1.08, 0.0, 1.5), 2.4)
			var v := e * 0.85 + mask * 0.75 - 0.78
			var h := v * 26.0
			if h > 2.5:
				var r := ridge.get_noise_2d(x, z) * 0.5 + 0.5
				h += pow(r, 2.2) * (h - 2.5) * 2.2
			if h < SEA:
				h = h * 1.4
			var i := z * W + x
			heights[i] = clampf(h, MIN_H, MAX_H)
			moisture[i] = clampf(mn.get_noise_2d(x, z) * 0.75 + 0.5, 0.0, 1.0)
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
			c = Color(0.56, 0.53, 0.50).lerp(Color(0.43, 0.41, 0.42), clampf((h - 6.0) / 14.0, 0.0, 1.0))
			if h > 15.0:
				c = c.lerp(Color(0.92, 0.93, 0.96), clampf((h - 15.0) / 6.0, 0.0, 0.8))
		Biome.ALPINE:
			c = Color(0.44, 0.56, 0.32).lerp(Color(0.55, 0.55, 0.42), clampf((h - 8.0) / 4.0, 0.0, 1.0))
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

func _mark(x: int, z: int) -> void:
	var cxs := [mini(x / CHUNK, SIZE / CHUNK - 1)]
	var czs := [mini(z / CHUNK, SIZE / CHUNK - 1)]
	if x % CHUNK == 0 and x > 0: cxs.append(x / CHUNK - 1)
	if z % CHUNK == 0 and z > 0: czs.append(z / CHUNK - 1)
	for cx in cxs:
		for cz in czs:
			dirty[Vector2i(cx, cz)] = true

func rebuild_dirty() -> void:
	for key in dirty.keys():
		_build_chunk(key)
	dirty.clear()
	if collision_dirty:
		_update_collision()

func _process(_dt: float) -> void:
	if not dirty.is_empty() or collision_dirty:
		rebuild_dirty()

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
	collision_dirty = true
	terrain_changed.emit(center, radius)

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
