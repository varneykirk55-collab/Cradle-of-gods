# Blender 4.2 headless asset generator for God Sim (clean-room, original assets).
# Run: blender -b --python tools/make_assets.py -- <output_dir>
import bpy, bmesh, sys, math, random
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
random.seed(1337)

def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)

MATS = {}
def mat(name, rgb, rough=0.85, emit=None):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    MATS[name] = m
    return m

def srgb(h):
    h = h.lstrip("#"); c = [int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

def assign(obj, m):
    obj.data.materials.clear(); obj.data.materials.append(m)

def jitter(obj, amt):
    for v in obj.data.vertices:
        v.co += Vector((random.uniform(-amt, amt), random.uniform(-amt, amt), random.uniform(-amt, amt)))

def cyl(r1, r2, h, verts=6, z=0.0, m=None, loc=(0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=h, location=(loc[0], loc[1], z + h / 2))
    o = bpy.context.active_object
    if m: assign(o, m)
    return o

def ico(r, sub=1, loc=(0, 0, 0), m=None, scale=(1, 1, 1), jit=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    if jit: jitter(o, jit)
    if m: assign(o, m)
    return o

def box(sx, sy, sz, loc, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    if m: assign(o, m)
    return o

def prism(w, d, h, z, m):
    # triangular roof along X
    me = bpy.data.meshes.new("roof")
    hw, hd = w / 2, d / 2
    verts = [(-hw, -hd, z), (hw, -hd, z), (hw, hd, z), (-hw, hd, z), (-hw, 0, z + h), (hw, 0, z + h)]
    faces = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new("roof", me); bpy.context.collection.objects.link(o)
    assign(o, m)
    return o

def finish(name):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if len(objs) > 1: bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_flat()
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}.glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_normals=True)
    print("EXPORTED", name, len(o.data.polygons), "faces")
    reset()

BARK = mat("Bark", srgb("#6b4a2f")); LEAF = mat("Leaf", srgb("#4f9a3a")); PINE = mat("Pine", srgb("#2f6e3f"))
LEAF2 = mat("LeafLight", srgb("#7cbf4a")); ROCK = mat("Rock", srgb("#8a8d91")); ROCK2 = mat("RockDark", srgb("#6c6f75"))
THATCH = mat("Thatch", srgb("#d1a85a")); WOOD = mat("Wood", srgb("#8b5a35")); PLASTER = mat("Plaster", srgb("#e8dcc4"))
ROOF = mat("Roof", srgb("#a0473a")); STONE = mat("Stone", srgb("#9b968c")); TRIBE = mat("Tribe", srgb("#ffffff"))
SKIN = mat("Skin", srgb("#e7b48f")); BERRY = mat("Berry", srgb("#c8324a")); DARK = mat("Dark", srgb("#3a2a1e"))
EMBER = mat("Ember", srgb("#3a2520"), emit=srgb("#ff6a1a")); HAIR = mat("Hair", srgb("#5a3a22"))

reset()
# --- Pine tree
cyl(0.16, 0.12, 0.8, 6, 0, BARK)
for i, (r, h, z) in enumerate([(1.0, 1.3, 0.6), (0.8, 1.1, 1.3), (0.55, 1.0, 1.95)]):
    o = cyl(r, 0.0, h, 7, z, PINE); jitter(o, 0.05)
finish("tree_pine")
# --- Oak / broadleaf tree
cyl(0.18, 0.12, 1.2, 6, 0, BARK)
cyl(0.06, 0.04, 0.6, 5, 0.9, BARK, (0.25, 0.0))
ico(0.85, 1, (0, 0, 1.9), LEAF, (1, 1, 0.85), 0.08)
ico(0.55, 1, (0.55, 0.2, 1.65), LEAF2, jit=0.06)
ico(0.5, 1, (-0.45, -0.3, 1.75), LEAF, jit=0.06)
ico(0.45, 1, (0.0, 0.5, 2.35), LEAF2, jit=0.05)
finish("tree_oak")
# --- Rock
ico(0.55, 1, (0, 0, 0.25), ROCK, (1.2, 1.0, 0.75), 0.12)
ico(0.3, 1, (0.55, 0.25, 0.12), ROCK2, (1, 1, 0.8), 0.07)
finish("rock")
# --- Berry bush
ico(0.45, 1, (0, 0, 0.32), LEAF, (1.1, 1.1, 0.8), 0.06)
ico(0.3, 1, (0.3, 0.15, 0.25), LEAF2, jit=0.04)
for i in range(7):
    a = i * 2.4; ico(0.07, 1, (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.3 + (i % 3) * 0.1), BERRY)
finish("bush")
# --- Hut (round, thatched)
cyl(0.85, 0.85, 0.75, 8, 0, WOOD)
cyl(1.15, 0.0, 1.0, 8, 0.7, THATCH)
box(0.32, 0.12, 0.5, (0, -0.84, 0.25), DARK)
cyl(0.05, 0.05, 1.0, 4, 0.9, WOOD)   # roof pole
box(0.12, 0.3, 0.2, (0.0, 0.15, 1.85), TRIBE)  # little tribe flag
finish("hut")
# --- House (timber + stone base, gabled roof, chimney)
box(2.0, 1.5, 0.35, (0, 0, 0.175), STONE)
box(1.9, 1.4, 0.9, (0, 0, 0.8), PLASTER)
for x in (-0.95, 0.95):
    for y in (-0.7, 0.7): box(0.12, 0.12, 0.95, (x, y, 0.8), WOOD)
box(2.0, 0.08, 0.1, (0, -0.71, 1.2), WOOD)
prism(2.3, 1.75, 0.9, 1.25, ROOF)
box(0.35, 0.06, 0.6, (0, -0.72, 0.55), DARK)
for x in (-0.6, 0.6): box(0.3, 0.06, 0.25, (x, -0.72, 0.85), DARK)
box(0.28, 0.28, 0.8, (0.6, 0.35, 1.9), STONE)
box(0.5, 0.06, 0.3, (-0.6, -0.9, 1.6), TRIBE)
finish("house")
# --- Town hall / tribe center (longhouse with banner)
box(3.2, 2.0, 0.3, (0, 0, 0.15), STONE)
box(3.0, 1.8, 1.2, (0, 0, 0.9), WOOD)
prism(3.5, 2.4, 1.4, 1.45, THATCH)
box(0.5, 0.06, 0.8, (0, -0.92, 0.7), DARK)
cyl(0.06, 0.06, 3.6, 5, 0, WOOD, (1.9, -1.2))
box(0.04, 0.8, 0.55, (1.9, -0.8, 3.25), TRIBE)
for x in (-1.2, 1.2): cyl(0.12, 0.12, 1.3, 6, 0, BARK, (x, -1.0))
finish("townhall")
# --- Villager (body uses Tribe material for recoloring)
cyl(0.2, 0.13, 0.42, 6, 0.12, TRIBE)
cyl(0.06, 0.06, 0.14, 4, 0, DARK, (0.08, 0)); cyl(0.06, 0.06, 0.14, 4, 0, DARK, (-0.08, 0))
ico(0.14, 1, (0, 0, 0.66), SKIN)
ico(0.145, 1, (0, 0.03, 0.71), HAIR, (1, 1, 0.6))
box(0.24, 0.05, 0.05, (0, 0, 0.45), SKIN)  # arms
finish("villager")
# --- Meteor
ico(0.9, 2, (0, 0, 0), EMBER, jit=0.15)
finish("meteor")
# --- Burnt stump
cyl(0.18, 0.12, 0.45, 6, 0, DARK)
finish("stump")
