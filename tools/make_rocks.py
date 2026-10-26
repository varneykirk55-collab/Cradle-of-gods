# Blender (bpy) generator for the environment rock set (original assets).
#   python3 tools/make_rocks.py -- assets/models        (pip install bpy==5.2.3)
#   blender -b --python tools/make_rocks.py -- assets/models
#
# Produces (decorative scatter used by scripts/terrain_decor.gd):
#   boulder_round.glb   weathered rounded granite boulder
#   boulder_split.glb   angular, fractured boulder (plane cuts + bevel)
#   boulder_slab.glb    flat, layered slab rock (strata displacement)
#   shore_rock.glb      low, water-worn shoreline stone
#   shore_pebbles.glb   cluster of rounded beach stones
#   stone_outcrop.glb   the harvestable stone resource (replaces milestone-1 rock.glb
#                       in game; same ~1.3 m footprint so gameplay scale is unchanged)
# Every rock: ~1 m reference size (scaled in game), origin at its base,
# vertex colours (COLOR_0) = baked cavity darkening + mineral variation +
# moss on top faces (boulders) or a dark wet/algae band (shore rocks).
import bpy, bmesh, sys, math, random
from mathutils import Vector, noise

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
random.seed(1026)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_bm(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    return ob


def ico(radius, subdiv):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return bm


def displace(bm, fn):
    for v in bm.verts:
        v.co = fn(v.co.copy())


def fbm(p, octaves=4, lac=2.0, gain=0.5):
    a, f, s = 1.0, 1.0, 0.0
    for _ in range(octaves):
        s += noise.noise(p * f) * a
        a *= gain
        f *= lac
    return s


def flatten_base(bm, z_cut):
    # squash everything below z_cut onto a slightly rounded base, so rocks sit on ground
    for v in bm.verts:
        if v.co.z < z_cut:
            v.co.z = z_cut + (v.co.z - z_cut) * 0.15


def decimate(ob, ratio):
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    bpy.ops.object.modifier_apply(modifier="dec")


def finish(ob, smooth_angle=50.0):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # origin at the base centre, rest on z=0
    me = ob.data
    zmin = min(v.co.z for v in me.vertices)
    cx = sum(v.co.x for v in me.vertices) / len(me.vertices)
    cy = sum(v.co.y for v in me.vertices) / len(me.vertices)
    for v in me.vertices:
        v.co -= Vector((cx, cy, zmin))
    bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))


def paint(ob, base, kind):
    """Vertex colours: base tone * mineral noise * cavity, + moss (boulders) or wet/algae band (shore)."""
    me = ob.data
    # cavity from local concavity: compare each vertex to its neighbours' average along the normal
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    cav = {}
    for v in bm.verts:
        if not v.link_edges:
            cav[v.index] = 0.0
            continue
        avg = sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges)
        cav[v.index] = (v.co - avg).dot(v.normal)
    bm.free()
    vals = sorted(cav.values())
    lo, hi = vals[int(len(vals) * 0.05)], vals[int(len(vals) * 0.95)]
    height = max(v.co.z for v in me.vertices) or 1.0
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            v = me.vertices[vi]
            c = (cav[vi] - lo) / (hi - lo + 1e-9)          # 0 crevice .. 1 ridge
            shade = 0.62 + 0.45 * min(max(c, 0.0), 1.0)
            p = v.co * 3.0
            mineral = 0.88 + 0.24 * (fbm(p, 3) * 0.5 + 0.5)
            speck = 1.0 + (0.12 if noise.noise(v.co * 23.0) > 0.45 else 0.0)
            col = [base[i] * shade * mineral * speck for i in range(3)]
            n = v.normal
            if kind == "boulder":
                moss = max(0.0, (n.z - 0.55) / 0.45) * max(0.0, min(1.0, fbm(v.co * 2.2, 3) * 1.6 + 0.35))
                moss_c = (0.20, 0.30, 0.10)
                col = [col[i] * (1 - moss * 0.85) + moss_c[i] * moss * 0.85 * shade for i in range(3)]
                lichen = 1.0 if noise.noise(v.co * 7.0 + Vector((5, 1, 2))) > 0.55 else 0.0
                col = [col[i] * (1 - lichen * 0.25) + (0.62, 0.60, 0.45)[i] * lichen * 0.25 for i in range(3)]
            elif kind == "shore":
                rel = v.co.z / height
                wet = max(0.0, min(1.0, (0.45 - rel) / 0.3))
                algae = wet * max(0.0, fbm(v.co * 3.0, 2) * 0.8 + 0.5)
                col = [col[i] * (1 - wet * 0.3) for i in range(3)]
                col = [col[i] * (1 - algae * 0.35) + (0.16, 0.22, 0.12)[i] * algae * 0.35 for i in range(3)]
            attr.data[li].color_srgb = (*[min(max(x, 0.0), 1.0) for x in col], 1.0)
    me.color_attributes.active_color = attr
    # base colour wired to the colour attribute, so the glTF material (and
    # Godot's importer) uses the vertex colours when no override is set
    m = bpy.data.materials.new("Rock")
    m.use_nodes = True
    nt = m.node_tree
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    bsdf = nt.nodes["Principled BSDF"]
    nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    ob.data.materials.append(m)


def export(name):
    path = f"{out}/{name}.glb"
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_vertex_color="ACTIVE", export_normals=True,
                              export_apply=True, export_yup=True)
    ob = bpy.context.active_object
    print(f"{name}: {len(ob.data.polygons)} faces -> {path}")


def build(name, make, kind, base, ratio, angle=50.0):
    reset()
    ob = make()
    decimate(ob, ratio)
    finish(ob, angle)
    paint(ob, base, kind)
    export(name)


def boulder_round():
    bm = ico(0.55, 4)
    off = Vector((random.random() * 50, random.random() * 50, 3.0))

    def f(co):
        d = 1.0 + fbm(co * 1.6 + off, 4) * 0.28 + noise.noise(co * 5 + off) * 0.05
        co = co * d
        co.x *= 1.15
        co.z *= 0.78
        return co
    displace(bm, f)
    flatten_base(bm, -0.22)
    return obj_from_bm(bm, "boulder_round")


def boulder_split():
    bm = ico(0.55, 3)
    off = Vector((11.0, 3.0, 7.0))
    displace(bm, lambda co: co * (1.0 + fbm(co * 1.3 + off, 3) * 0.18))
    # fracture planes
    for i in range(7):
        a = random.uniform(0, math.tau)
        el = random.uniform(-0.2, 0.9)
        nrm = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=nrm * random.uniform(0.32, 0.45),
                                     plane_no=nrm, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    displace(bm, lambda co: co + Vector(noise.noise_vector(co * 6 + off)) * 0.015)
    for v in bm.verts:
        v.co.z *= 0.9
    flatten_base(bm, -0.25)
    return obj_from_bm(bm, "boulder_split")


def boulder_slab():
    bm = ico(0.55, 4)
    off = Vector((2.0, 19.0, 5.0))

    def f(co):
        co = co * (1.0 + fbm(co * 1.4 + off, 3) * 0.2)
        co.x *= 1.35
        co.y *= 1.05
        co.z *= 0.42
        # stepped strata
        z = co.z
        band = 0.07
        co.z = z + (round(z / band) * band - z) * 0.55
        co.x += math.sin(co.z * 40.0) * 0.012
        return co
    displace(bm, f)
    flatten_base(bm, -0.16)
    return obj_from_bm(bm, "boulder_slab")


def stone_outcrop():
    # a fractured main block with a smaller split-off stone beside it
    bm = bmesh.new()
    for i, (x, y, r, sz) in enumerate([(0.0, 0.0, 0.5, 0.8), (0.55, 0.28, 0.27, 0.75)]):
        tmp = ico(r, 3)
        off = Vector((i * 5.0, 2.0, 1.0))
        for v in tmp.verts:
            v.co = v.co * (1.0 + fbm(v.co * 2.0 + off, 3) * 0.16)
        for k in range(5):
            a = random.uniform(0, math.tau)
            el = random.uniform(0.0, 0.8)
            nrm = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
            geom = tmp.verts[:] + tmp.edges[:] + tmp.faces[:]
            res = bmesh.ops.bisect_plane(tmp, geom=geom, plane_co=nrm * r * random.uniform(0.6, 0.8),
                                         plane_no=nrm, clear_outer=True)
            edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            if edges:
                bmesh.ops.holes_fill(tmp, edges=edges, sides=0)
        for v in tmp.verts:
            v.co.x *= 1.2
            v.co.z *= sz
            v.co += Vector((x, y, r * sz * 0.45))
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    flatten_base(bm, 0.02)
    return obj_from_bm(bm, "stone_outcrop")


def shore_rock():
    bm = ico(0.5, 4)
    off = Vector((7.0, 7.0, 1.0))

    def f(co):
        co = co * (1.0 + fbm(co * 1.1 + off, 3) * 0.16)
        co.x *= 1.3
        co.z *= 0.5
        return co
    displace(bm, f)
    flatten_base(bm, -0.12)
    return obj_from_bm(bm, "shore_rock")


def shore_pebbles():
    bm = bmesh.new()
    spots = [(0, 0, 0.30), (0.42, 0.18, 0.2), (-0.35, 0.28, 0.17), (0.12, -0.42, 0.22), (-0.3, -0.3, 0.13), (0.5, -0.3, 0.12)]
    for i, (x, y, r) in enumerate(spots):
        tmp = ico(r, 2)
        off = Vector((i * 3.1, i * 1.7, 0))
        for v in tmp.verts:
            co = v.co * (1.0 + fbm(v.co * 3 + off, 2) * 0.15)
            co.x *= 1.25
            co.z *= 0.6
            v.co = co + Vector((x, y, 0))
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
    flatten_base(bm, -0.04)
    return obj_from_bm(bm, "shore_pebbles")


build("boulder_round", boulder_round, "boulder", (0.56, 0.54, 0.50), 0.35)
build("boulder_split", boulder_split, "boulder", (0.52, 0.49, 0.45), 0.5, 35.0)
build("boulder_slab", boulder_slab, "boulder", (0.60, 0.55, 0.47), 0.35)
build("shore_rock", shore_rock, "shore", (0.50, 0.48, 0.45), 0.3)
build("shore_pebbles", shore_pebbles, "shore", (0.62, 0.58, 0.52), 0.6)
build("stone_outcrop", stone_outcrop, "stone", (0.60, 0.57, 0.52), 0.6, 35.0)
