class_name TerrainDecor
extends Node3D
## Decorative rocks scattered over the terrain: Blender boulders on steep and
## high ground, water-worn stones and pebbles along shorelines
## (tools/make_rocks.py). One MultiMesh per model per terrain chunk, rebuilt
## whenever Terrain rebuilds that chunk, so sculpted and newly created land
## gets rocks by the same rules. Placement is a pure function of the cell,
## the world seed and the local terrain, so unrelated edits never reshuffle it.
## Purely visual: no collision and no effect on navigation or resources (the
## harvestable stone resource is separate, see world_sim.gd). Boulders only
## appear on slopes steeper than villagers build on, and shore rocks sit at
## or below the waterline.

const BOULDERS := ["boulder_round", "boulder_split", "boulder_slab"]
const SHORE := ["shore_rock", "shore_pebbles"]
const STEP := 2           # candidate spacing in cells

var terrain: Terrain
var _mat: ShaderMaterial
var _meshes := {}
var _nodes := {}          # chunk key -> Array[MultiMeshInstance3D]

func _ready() -> void:
	_mat = Assets.rock_material()
	for m in BOULDERS + SHORE:
		_meshes[m] = Assets.mesh(m)

static func _hash(x: int, z: int, s: int) -> int:
	var h := (x * 374761393 + z * 668265263 + s * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)

static func _rnd(h: int, k: int) -> float:
	return float(_hash(h, k, 91) & 0xffff) / 65535.0

func rebuild_chunk(key: Vector2i) -> void:
	var lists := {}
	for m in BOULDERS + SHORE:
		lists[m] = []
	var x0 := key.x * Terrain.CHUNK
	var z0 := key.y * Terrain.CHUNK
	var t := terrain
	for gz in range(z0, z0 + Terrain.CHUNK, STEP):
		for gx in range(x0, x0 + Terrain.CHUNK, STEP):
			var h := _hash(gx, gz, t.seed_value)
			var wx := gx - Terrain.HALF + 0.3 + _rnd(h, 1) * (STEP - 0.6)
			var wz := gz - Terrain.HALF + 0.3 + _rnd(h, 2) * (STEP - 0.6)
			if not t.in_bounds(wx, wz, 1.0): continue
			var y := t.height_at(wx, wz)
			var n := t._normal(clampi(int(round(wx + Terrain.HALF)), 0, Terrain.SIZE), clampi(int(round(wz + Terrain.HALF)), 0, Terrain.SIZE))
			var steep := 1.0 - n.y
			var cluster := t.detail.get_noise_2d(wx * 2.3, wz * 2.3) * 0.5 + 0.5
			var roll := _rnd(h, 3)
			if y > 0.6:
				# boulders: steep slopes (above the build / farm range) and high scree
				var p := smoothstep(0.3, 0.46, steep) * 0.24 + smoothstep(12.0, 16.0, y) * 0.07
				p *= 0.4 + cluster * 1.2
				if roll < p:
					var sc := lerpf(0.6, 1.7, pow(_rnd(h, 4), 1.6)) * (1.25 if y > 12.0 else 1.0)
					lists[BOULDERS[_hash(gx, gz, 5) % BOULDERS.size()]].append(_xf(wx, y, wz, n, sc, h, 0.6))
			elif y > -1.4 and y < 0.35:
				# shoreline: around the waterline, clustered
				var p2 := 0.05 + smoothstep(0.55, 0.85, cluster) * 0.3
				if roll < p2:
					var shore_i := 0 if _rnd(h, 6) < 0.45 else 1
					var sc2 := lerpf(0.55, 1.35, _rnd(h, 4)) * (1.0 if shore_i == 0 else 1.2)
					lists[SHORE[shore_i]].append(_xf(wx, y, wz, n, sc2, h, 0.85))
	for mi in _nodes.get(key, []):
		mi.queue_free()
	var made := []
	for m in lists:
		var xfs: Array = lists[m]
		if xfs.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[m]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.name = "%s_%d_%d" % [m, key.x, key.y]
		var shore: bool = m in SHORE
		mi.visibility_range_end = 150.0 if shore else 240.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if m == "shore_pebbles" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		made.append(mi)
	_nodes[key] = made

## Random yaw, partly tilted to the ground normal, sunk a little into the ground.
func _xf(wx: float, y: float, wz: float, n: Vector3, sc: float, h: int, tilt: float) -> Transform3D:
	var up := Vector3.UP.lerp(n, tilt).normalized()
	var yaw := _rnd(h, 7) * TAU
	var fwd := Vector3(cos(yaw), 0, sin(yaw))
	var right := up.cross(fwd).normalized()
	fwd = right.cross(up).normalized()
	var stretch := Vector3(lerpf(0.85, 1.2, _rnd(h, 8)), lerpf(0.8, 1.15, _rnd(h, 9)), lerpf(0.85, 1.2, _rnd(h, 10)))
	var basis := Basis(right * stretch.x * sc, up * stretch.y * sc, fwd * stretch.z * sc)
	return Transform3D(basis, Vector3(wx, y - sc * 0.18, wz))

func instance_count() -> int:
	var c := 0
	for k in _nodes:
		for mi in _nodes[k]:
			if is_instance_valid(mi) and not mi.is_queued_for_deletion():
				c += mi.multimesh.instance_count
	return c
