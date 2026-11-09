class_name Assets
extends RefCounted
## Loads the Blender-generated .glb models (assets/models) and caches meshes and
## per-tribe recoloured materials.

static var _meshes := {}
static var _tribe_mats := {}
static var _soft_tex: Texture2D = null
static var _rock_mat: ShaderMaterial = null

## Blender rock set (tools/make_rocks.py): vertex-coloured, drawn with shaders/rock.gdshader.
const ROCK_MODELS := ["boulder_round", "boulder_split", "boulder_slab", "shore_rock", "shore_pebbles", "stone_outcrop"]

static func rock_material() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://shaders/rock.gdshader")
		_rock_mat.set_shader_parameter("detail_tex", load("res://assets/textures/terrain_detail.png"))
	return _rock_mat

static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var ps: PackedScene = load("res://assets/models/%s.glb" % model)
	var inst := ps.instantiate()
	var mi := _find_mesh(inst)
	var m: Mesh = mi.mesh if mi else BoxMesh.new()
	inst.free()
	if model in ROCK_MODELS:
		m.surface_set_material(0, rock_material())
	_meshes[model] = m
	return m

static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r: return r
	return null

## Index of the surface whose material is named "Tribe" (recoloured per tribe).
static func tribe_surface(m: Mesh) -> int:
	for i in m.get_surface_count():
		var sm := m.surface_get_material(i)
		if sm and sm.resource_name == "Tribe":
			return i
	return -1

static func tribe_material(m: Mesh, color: Color) -> Material:
	var key := "%d_%s" % [m.get_instance_id(), color.to_html()]
	if _tribe_mats.has(key):
		return _tribe_mats[key]
	var idx := tribe_surface(m)
	var base: Material = m.surface_get_material(idx) if idx >= 0 else null
	var mat: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	mat.albedo_color = color
	_tribe_mats[key] = mat
	return mat

static func apply_tribe(mi: MeshInstance3D, color: Color) -> void:
	var idx := tribe_surface(mi.mesh)
	if idx >= 0:
		mi.set_surface_override_material(idx, tribe_material(mi.mesh, color))

static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex

static var _parts := {}

## Rigid multi-part models (villager_rig, deer, wolf, rabbit, bird): returns
## {part_name: {"mesh": Mesh, "xform": Transform3D}} where xform is the part's
## joint pivot relative to the model root.
static func parts(model: String) -> Dictionary:
	if _parts.has(model):
		return _parts[model]
	var ps: PackedScene = load("res://assets/models/%s.glb" % model)
	var inst := ps.instantiate()
	var out := {}
	_collect(inst, inst, out)
	inst.free()
	_parts[model] = out
	return out

static func _collect(root: Node, n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D:
		var xf := Transform3D.IDENTITY
		var p := n as Node3D
		while p != null and p != root:
			xf = p.transform * xf
			p = p.get_parent() as Node3D
		out[n.name] = {"mesh": (n as MeshInstance3D).mesh, "xform": xf}
	for c in n.get_children():
		_collect(root, c, out)

## Builds MeshInstance3D children for every part under `parent`; returns name -> node.
static func build_parts(model: String, parent: Node3D, vis_range := 0.0) -> Dictionary:
	var nodes := {}
	var p := parts(model)
	for k in p:
		var mi := MeshInstance3D.new()
		mi.name = k
		mi.mesh = p[k]["mesh"]
		mi.transform = p[k]["xform"]
		if vis_range > 0.0:
			mi.visibility_range_end = vis_range
		parent.add_child(mi)
		nodes[k] = mi
	return nodes
