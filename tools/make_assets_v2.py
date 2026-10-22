# Blender 5.2 headless asset generator for the god-sim expansion (original assets).
# Run with Blender:   blender -b --python tools/make_assets_v2.py -- assets/models
# or with the bpy module:  python tools/make_assets_v2.py -- assets/models
#
# Produces:
#   god_hand.glb       skinned right hand (armature: hand + 3 bones per finger/thumb)
#   villager_rig.glb   rigid villager parts (torso, head, arms, legs, priest/heretic extras)
#   deer/wolf/rabbit/bird.glb   rigid animal parts, each object's origin is its joint pivot
#   shrine.glb, temple.glb, hut_b.glb, house_b.glb
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
random.seed(4711)


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)


MATS = {}


def mat(name, rgb, rough=0.85, emit=None, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    MATS[name] = m
    return m


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def active():
    return bpy.context.active_object


def jitter(obj, amt):
    for v in obj.data.vertices:
        v.co += Vector((random.uniform(-amt, amt), random.uniform(-amt, amt), random.uniform(-amt, amt)))


def cyl(r1, r2, h, verts=6, z=0.0, m=None, loc=(0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=h, location=(loc[0], loc[1], z + h / 2))
    o = active()
    if m: assign(o, m)
    return o


def seg(a, b, r1, r2, verts=6, m=None):
    """Tapered cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=d.length, location=(a + b) / 2)
    o = active()
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    if m: assign(o, m)
    return o


def ico(r, sub=1, loc=(0, 0, 0), m=None, scale=(1, 1, 1), jit=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = active()
    o.scale = scale
    if jit: jitter(o, jit)
    if m: assign(o, m)
    return o


def uvs(r, loc=(0, 0, 0), m=None, scale=(1, 1, 1), seg_=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg_, ring_count=rings, radius=r, location=loc)
    o = active()
    o.scale = scale
    if m: assign(o, m)
    return o


def box(sx, sy, sz, loc, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = active()
    o.scale = (sx, sy, sz)
    if m: assign(o, m)
    return o


def prism(w, d, h, z, m, x=0.0, y=0.0):
    me = bpy.data.meshes.new("roof")
    hw, hd = w / 2, d / 2
    verts = [(-hw + x, -hd + y, z), (hw + x, -hd + y, z), (hw + x, hd + y, z), (-hw + x, hd + y, z),
             (-hw + x, y, z + h), (hw + x, y, z + h)]
    faces = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("roof", me)
    bpy.context.collection.objects.link(o)
    assign(o, m)
    return o


def join(objs, name, pivot=(0, 0, 0), flat=True):
    """Join objects into one mesh object named `name` whose origin sits at `pivot`."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = active()
    o.name = name
    o.data.name = name
    # move geometry so the pivot is the origin, then place the object at the pivot
    pv = Vector(pivot)
    o.data.transform(Matrix.Translation(-pv))
    o.location = pv
    if flat:
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth()
    o.select_set(False)
    return o


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}.glb", export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True, export_animations=False)
    print("EXPORTED", name, [o.name for o in bpy.context.scene.objects])
    reset()


def finish(name):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    join(objs, name)
    export(name)


# --------------------------------------------------------------- materials
BARK = mat("Bark", srgb("#6b4a2f")); WOOD = mat("Wood", srgb("#8b5a35")); DARK = mat("Dark", srgb("#3a2a1e"))
STONE = mat("Stone", srgb("#9b968c")); MARBLE = mat("Marble", srgb("#ece6da"), 0.55); TRIBE = mat("Tribe", srgb("#ffffff"))
SKIN = mat("Skin", srgb("#e7b48f")); HAIR = mat("Hair", srgb("#5a3a22")); THATCH = mat("Thatch", srgb("#d1a85a"))
PLASTER = mat("Plaster", srgb("#e8dcc4")); ROOF2 = mat("RoofSlate", srgb("#4f6274")); ROOF = mat("Roof", srgb("#a0473a"))
GOLD = mat("Gold", srgb("#e2b34a"), 0.35, metal=0.8); GLOW = mat("HolyGlow", srgb("#fff2b0"), 0.4, emit=srgb("#ffd76a"))
PANTS = mat("Pants", srgb("#5b4632")); BOOT = mat("Boot", srgb("#3b2a1c")); ROBE = mat("Robe", srgb("#f1ece0"))
HOOD = mat("Hood", srgb("#3a2b45")); EYE = mat("Eye", srgb("#151515"))
HAND = mat("HandSkin", srgb("#f0c49c"), 0.55); NAIL = mat("Nail", srgb("#f6dccb"), 0.3)
DEER = mat("DeerFur", srgb("#9a6438")); DEER2 = mat("DeerBelly", srgb("#e8d2b0")); ANTLER = mat("Antler", srgb("#d8c7a0"))
WOLF = mat("WolfFur", srgb("#7d7f86")); WOLF2 = mat("WolfBelly", srgb("#c9c6c0")); NOSE = mat("Nose", srgb("#202020"))
RABBIT = mat("RabbitFur", srgb("#b08b68")); RABBIT2 = mat("RabbitTail", srgb("#f4efe6")); EARPINK = mat("EarPink", srgb("#e7a7a0"))
BIRD = mat("BirdFeather", srgb("#3f6fb5")); BIRD2 = mat("BirdBreast", srgb("#e9833a")); BEAK = mat("Beak", srgb("#f0c040"))
HOOF = mat("Hoof", srgb("#2c2420"))

reset()

# =============================================================== GOD HAND
# Right hand, palm facing -Z, fingers along +Y, thumb on -X. (glTF/Godot: fingers -Z, palm -Y.)
FINGERS = {
    "index": [(-0.165, 0.40, 0.0), (-0.18, 0.57, 0.0), (-0.188, 0.68, -0.005), (-0.192, 0.77, -0.012)],
    "middle": [(-0.055, 0.43, 0.01), (-0.058, 0.62, 0.01), (-0.06, 0.745, 0.0), (-0.061, 0.84, -0.01)],
    "ring": [(0.055, 0.41, 0.0), (0.062, 0.585, 0.0), (0.066, 0.70, -0.005), (0.068, 0.79, -0.012)],
    "pinky": [(0.155, 0.36, -0.01), (0.172, 0.50, -0.01), (0.18, 0.585, -0.015), (0.185, 0.66, -0.02)],
    "thumb": [(-0.13, 0.06, -0.04), (-0.26, 0.20, -0.07), (-0.335, 0.31, -0.085), (-0.385, 0.40, -0.09)],
}
RADII = {"index": (0.055, 0.047, 0.041, 0.036), "middle": (0.058, 0.05, 0.043, 0.037),
         "ring": (0.054, 0.046, 0.04, 0.035), "pinky": (0.046, 0.04, 0.035, 0.031), "thumb": (0.075, 0.062, 0.054, 0.046)}

parts = []
# palm: a rounded slab
bpy.ops.mesh.primitive_cube_add(size=1, location=(0.0, 0.2, 0.0))
palm = active()
palm.scale = (0.40, 0.44, 0.13)
bpy.ops.object.transform_apply(scale=True)
bev = palm.modifiers.new("bev", "BEVEL"); bev.width = 0.055; bev.segments = 4
bpy.ops.object.modifier_apply(modifier="bev")
for v in palm.data.vertices:   # taper toward the wrist and arch the back of the hand
    t = (v.co.y + 0.02) / 0.44
    v.co.x *= 0.82 + 0.2 * max(0.0, min(1.0, t))
    v.co.z += 0.03 * math.cos(v.co.x * 4.0) - 0.02
parts.append(palm)
# wrist / forearm
parts.append(seg((0, 0.02, 0.0), (0, -1.0, 0.04), 0.15, 0.2, 16))
for v in parts[-1].data.vertices:
    v.co.z *= 0.75
for name, pts in FINGERS.items():
    rr = RADII[name]
    for i in range(3):
        parts.append(seg(pts[i], pts[i + 1], rr[i], rr[i + 1], 12))
    for i in range(4):
        parts.append(uvs(rr[i] * 1.02, pts[i], seg_=12, rings=8))
# thenar (thumb muscle) bulge
parts.append(uvs(0.13, (-0.12, 0.12, -0.04), scale=(1.0, 1.2, 0.7)))
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
hand = active()
hand.name = "GodHand"
rm = hand.modifiers.new("rm", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = 0.014
bpy.ops.object.modifier_apply(modifier="rm")
sm = hand.modifiers.new("sm", "SMOOTH"); sm.factor = 0.8; sm.iterations = 6
bpy.ops.object.modifier_apply(modifier="sm")
dec = hand.modifiers.new("dec", "DECIMATE"); dec.ratio = 0.22
bpy.ops.object.modifier_apply(modifier="dec")
assign(hand, HAND)
hand.data.materials.append(NAIL)
hand.data.materials.append(GOLD)
# nails on the dorsal side of each fingertip
extra = []
for name, pts in FINGERS.items():
    tip, prev = Vector(pts[3]), Vector(pts[2])
    d = (tip - prev).normalized()
    r = RADII[name][3]
    c = tip - d * r * 0.6 + Vector((0, 0, r * 0.78 if name != "thumb" else r * 0.7))
    n = uvs(r * 0.82, c, NAIL, scale=(0.85, 1.15, 0.32), seg_=10, rings=6)
    n.rotation_mode = "QUATERNION"
    n.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(d)
    extra.append(n)
# golden bracer hides the cut of the forearm
for (y0, y1, grow) in ((-0.34, -0.52, 0.035), (-0.30, -0.335, 0.045), (-0.525, -0.56, 0.045)):
    r0 = 0.15 + 0.05 * (-y0 / 1.02) + grow
    r1 = 0.15 + 0.05 * (-y1 / 1.02) + grow
    br = seg((0, y0, 0.02), (0, y1, 0.02), r0, r1, 28, GOLD)
    for v in br.data.vertices:
        v.co.z = 0.02 + (v.co.z - 0.02) * 0.78
    extra.append(br)
gem = uvs(0.05, (0, -0.43, 0.17), GLOW, scale=(1, 1.3, 0.5)); extra.append(gem)
bpy.ops.object.select_all(action="DESELECT")
for o in extra:
    o.select_set(True)
bpy.context.view_layer.objects.active = extra[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
hand.select_set(True)
bpy.context.view_layer.objects.active = hand
bpy.ops.object.join()
bpy.ops.object.shade_smooth()
hand = active()
hand.name = "GodHand"
hand.data.name = "GodHand"

# armature
arm_data = bpy.data.armatures.new("HandRig")
rig = bpy.data.objects.new("HandRig", arm_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
root = eb.new("hand")
root.head = (0, -0.3, 0.02)
root.tail = (0, 0.25, 0.0)
root.roll = 0
BONES = [("hand", Vector((0, -0.3, 0.02)), Vector((0, 0.25, 0.0)))]
for name, pts in FINGERS.items():
    parent = root
    for i in range(3):
        b = eb.new("%s_%d" % (name, i + 1))
        b.head = pts[i]
        b.tail = pts[i + 1]
        # roll so local +X points across the hand -> curl is a rotation about local X
        b.align_roll(Vector((0, 0, 1)))
        b.parent = parent
        b.use_connect = i > 0
        parent = b
        BONES.append((b.name, Vector(pts[i]), Vector(pts[i + 1])))
bpy.ops.object.mode_set(mode="OBJECT")


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length, (p - a).dot(ab) / ab.length_squared


# manual, deterministic skin weights: nearest bone segments, with finger bones
# only influencing geometry past their knuckle.
groups = {n: hand.vertex_groups.new(name=n) for n, _, _ in BONES}
for v in hand.data.vertices:
    p = v.co
    cands = []
    for n, a, b in BONES:
        d, t = seg_dist(p, a, b)
        if n != "hand" and n.endswith("_1") and t < -0.05:
            d += 0.2   # palm geometry behind a knuckle belongs to the hand bone
        cands.append((d, n))
    cands.sort()
    best = cands[:2]
    w = [1.0 / max(d, 0.004) ** 4 for d, _ in best]
    s = sum(w)
    for (d, n), wi in zip(best, w):
        if wi / s > 0.02:
            groups[n].add([v.index], wi / s, "REPLACE")
mod = hand.modifiers.new("Armature", "ARMATURE")
mod.object = rig
hand.parent = rig
export("god_hand")

# =============================================================== VILLAGER RIG
# Parts are separate objects whose origins are their joints (hip, neck, shoulders).
HIP = 0.30
SH = 0.57
legs = []
for side, x in (("leg_l", 0.075), ("leg_r", -0.075)):
    l1 = seg((x, 0, HIP), (x, 0.0, 0.06), 0.058, 0.045, 6, PANTS)
    l2 = box(0.085, 0.13, 0.07, (x, 0.025, 0.035), BOOT)
    join([l1, l2], side, (x, 0, HIP))
t1 = cyl(0.165, 0.125, 0.29, 7, HIP - 0.02, TRIBE)
t2 = cyl(0.172, 0.172, 0.04, 7, HIP + 0.03, BOOT)       # belt
t3 = cyl(0.13, 0.1, 0.05, 7, HIP + 0.27, TRIBE)         # collar
t4 = box(0.04, 0.02, 0.03, (0, -0.172, HIP + 0.05), GOLD)  # buckle
join([t1, t2, t3, t4], "torso", (0, 0, HIP))
h1 = ico(0.135, 2, (0, 0, SH + 0.15), SKIN)
h2 = ico(0.142, 1, (0, 0.025, SH + 0.2), HAIR, (1, 1, 0.62))
h3 = box(0.04, 0.05, 0.06, (0, -0.135, SH + 0.14), SKIN)   # nose
h4 = ico(0.02, 1, (0.05, -0.122, SH + 0.17), EYE)
h5 = ico(0.02, 1, (-0.05, -0.122, SH + 0.17), EYE)
join([h1, h2, h3, h4, h5], "head", (0, 0, SH + 0.04))
for side, x in (("arm_l", 0.19), ("arm_r", -0.19)):
    a1 = seg((x, 0, SH), (x * 1.05, 0, SH - 0.14), 0.05, 0.045, 6, TRIBE)
    a2 = seg((x * 1.05, 0, SH - 0.14), (x * 1.08, 0, SH - 0.27), 0.04, 0.036, 6, SKIN)
    a3 = ico(0.045, 1, (x * 1.08, 0, SH - 0.29), SKIN)
    join([a1, a2, a3], side, (x, 0, SH))
# priest regalia (shown only on priests): long robe over the legs, mitre, stole
r1 = cyl(0.2, 0.16, 0.33, 8, 0.0, ROBE)
r2 = box(0.06, 0.02, 0.3, (0, -0.172, HIP + 0.1), GOLD)
join([r1, r2], "robe", (0, 0, HIP))
m1 = cyl(0.1, 0.05, 0.2, 6, SH + 0.26, ROBE)
m2 = cyl(0.105, 0.105, 0.035, 6, SH + 0.25, GOLD)
m3 = ico(0.03, 1, (0, 0, SH + 0.47), GLOW)
join([m1, m2, m3], "mitre", (0, 0, SH + 0.04))
# heretic hood
hh = ico(0.165, 1, (0, 0.03, SH + 0.17), HOOD, (1.0, 1.08, 1.0))
hh2 = cyl(0.16, 0.12, 0.06, 7, SH + 0.0, HOOD)
join([hh, hh2], "hood", (0, 0, SH + 0.04))
# tools held in the right hand (pivot at the hand)
tl1 = seg((-0.205, 0, SH - 0.29), (-0.205, -0.32, SH - 0.29), 0.015, 0.015, 5, WOOD)
tl2 = box(0.03, 0.08, 0.1, (-0.205, -0.31, SH - 0.27), STONE)
join([tl1, tl2], "tool", (-0.205, 0, SH - 0.29))
sp1 = seg((-0.205, 0.25, SH - 0.29), (-0.205, -0.55, SH - 0.29), 0.013, 0.013, 5, WOOD)
sp2 = cyl(0.03, 0.0, 0.1, 4, 0, STONE)
sp2.location = (-0.205, -0.6, SH - 0.29); sp2.rotation_euler = (math.pi / 2, 0, 0)
join([sp1, sp2], "spear", (-0.205, 0, SH - 0.29))
export("villager_rig")


# =============================================================== ANIMALS
def quad_legs(prefix_m, hoof_m, hx, fz, bz, hip_z, r_top, r_bot, foot=None):
    for nm, x, y in (("leg_fl", hx, fz), ("leg_fr", -hx, fz), ("leg_bl", hx, bz), ("leg_br", -hx, bz)):
        objs = [seg((x, y, hip_z), (x, y + 0.01, 0.05), r_top, r_bot, 6, prefix_m)]
        objs.append(cyl(r_bot * 1.1, r_bot * 0.9, 0.06, 6, 0.0, foot or hoof_m, (x, y + 0.01)))
        join(objs, nm, (x, y, hip_z))


# Deer: faces -Y (glTF -> Godot +Z forward). Size ~1.3 long, 1.2 tall at the head.
b = ico(0.3, 2, (0, 0, 0.72), DEER, (0.75, 1.45, 0.78))
bb = ico(0.24, 1, (0, 0.02, 0.62), DEER2, (0.7, 1.25, 0.55))
join([b, bb], "body", (0, 0, 0.72))
n1 = seg((0, -0.32, 0.82), (0, -0.48, 1.12), 0.11, 0.08, 7, DEER)
hd = ico(0.12, 1, (0, -0.56, 1.16), DEER, (0.85, 1.4, 0.9))
sn = ico(0.06, 1, (0, -0.7, 1.12), DEER2, (1, 1.2, 0.8))
nz = ico(0.025, 1, (0, -0.76, 1.13), NOSE)
e1 = ico(0.06, 1, (0.1, -0.5, 1.26), DEER, (0.5, 0.3, 1.2)); e2 = ico(0.06, 1, (-0.1, -0.5, 1.26), DEER, (0.5, 0.3, 1.2))
ey1 = ico(0.018, 1, (0.07, -0.63, 1.2), EYE); ey2 = ico(0.018, 1, (-0.07, -0.63, 1.2), EYE)
ants = []
for s in (1, -1):
    ants.append(seg((0.05 * s, -0.52, 1.25), (0.14 * s, -0.48, 1.5), 0.016, 0.01, 4, ANTLER))
    ants.append(seg((0.11 * s, -0.49, 1.42), (0.2 * s, -0.56, 1.52), 0.012, 0.008, 4, ANTLER))
    ants.append(seg((0.08 * s, -0.5, 1.33), (0.04 * s, -0.62, 1.42), 0.012, 0.008, 4, ANTLER))
join([n1, hd, sn, nz, e1, e2, ey1, ey2] + ants, "head", (0, -0.32, 0.82))
tl = ico(0.06, 1, (0, 0.46, 0.84), DEER2, (0.8, 0.6, 1.2))
join([tl], "tail", (0, 0.42, 0.84))
quad_legs(DEER, HOOF, 0.12, -0.28, 0.3, 0.62, 0.05, 0.03)
export("deer")

# Wolf
b = ico(0.28, 2, (0, 0, 0.5), WOLF, (0.72, 1.45, 0.72))
bb = ico(0.22, 1, (0, -0.05, 0.43), WOLF2, (0.65, 1.2, 0.55))
mane = ico(0.24, 1, (0, -0.25, 0.56), WOLF, (0.85, 0.8, 0.85), 0.02)
join([b, bb, mane], "body", (0, 0, 0.5))
hd = ico(0.14, 1, (0, -0.5, 0.64), WOLF, (0.9, 1.0, 0.85))
sn = ico(0.08, 1, (0, -0.65, 0.6), WOLF2, (0.8, 1.5, 0.7))
nz = ico(0.03, 1, (0, -0.76, 0.62), NOSE)
e1 = cyl(0.05, 0.0, 0.12, 4, 0.72, WOLF, (0.08, -0.46)); e2 = cyl(0.05, 0.0, 0.12, 4, 0.72, WOLF, (-0.08, -0.46))
ey1 = ico(0.018, 1, (0.06, -0.6, 0.68), BEAK); ey2 = ico(0.018, 1, (-0.06, -0.6, 0.68), BEAK)
join([hd, sn, nz, e1, e2, ey1, ey2], "head", (0, -0.36, 0.6))
t1 = seg((0, 0.38, 0.55), (0, 0.72, 0.4), 0.07, 0.05, 6, WOLF)
t2 = ico(0.06, 1, (0, 0.74, 0.39), WOLF2)
join([t1, t2], "tail", (0, 0.38, 0.55))
quad_legs(WOLF, NOSE, 0.11, -0.25, 0.28, 0.42, 0.05, 0.035)
export("wolf")

# Rabbit (small: ~0.35 long)
b = ico(0.12, 2, (0, 0.03, 0.14), RABBIT, (0.85, 1.15, 0.9))
tl = ico(0.045, 1, (0, 0.17, 0.16), RABBIT2)
join([b, tl], "body", (0, 0, 0.14))
hd = ico(0.075, 1, (0, -0.11, 0.24), RABBIT, (0.9, 1.05, 0.9))
nz = ico(0.015, 1, (0, -0.18, 0.24), EARPINK)
ey1 = ico(0.014, 1, (0.04, -0.15, 0.27), EYE); ey2 = ico(0.014, 1, (-0.04, -0.15, 0.27), EYE)
join([hd, nz, ey1, ey2], "head", (0, -0.08, 0.2))
for nm, x in (("ear_l", 0.03), ("ear_r", -0.03)):
    e = ico(0.03, 1, (x, -0.09, 0.37), RABBIT, (0.6, 0.35, 2.4))
    ei = ico(0.02, 1, (x, -0.1, 0.37), EARPINK, (0.5, 0.2, 2.0))
    join([e, ei], nm, (x, -0.09, 0.3))
for nm, x in (("leg_bl", 0.07), ("leg_br", -0.07)):
    l = ico(0.05, 1, (x, 0.06, 0.05), RABBIT, (0.7, 1.7, 0.8))
    join([l], nm, (x, 0.06, 0.1))
for nm, x in (("leg_fl", 0.05), ("leg_fr", -0.05)):
    l = seg((x, -0.07, 0.1), (x, -0.08, 0.0), 0.02, 0.018, 5, RABBIT)
    join([l], nm, (x, -0.07, 0.1))
export("rabbit")

# Bird (songbird / gull sized ~0.35 wingspan 0.7)
b = ico(0.08, 2, (0, 0, 0), BIRD, (0.85, 1.6, 0.85))
br_ = ico(0.065, 1, (0, -0.04, -0.02), BIRD2, (0.8, 1.2, 0.8))
hd = ico(0.06, 1, (0, -0.14, 0.05), BIRD)
bk = cyl(0.025, 0.0, 0.07, 4, 0, BEAK)
bk.location = (0, -0.2, 0.045); bk.rotation_euler = (math.pi / 2, 0, 0)
ey1 = ico(0.012, 1, (0.035, -0.17, 0.07), EYE); ey2 = ico(0.012, 1, (-0.035, -0.17, 0.07), EYE)
tl = box(0.08, 0.14, 0.015, (0, 0.17, 0.01), BIRD)
join([b, br_, hd, bk, ey1, ey2, tl], "body", (0, 0, 0))
for nm, s in (("wing_l", 1), ("wing_r", -1)):
    me = bpy.data.meshes.new(nm)
    verts = [(0.04 * s, -0.06, 0.02), (0.04 * s, 0.07, 0.02), (0.36 * s, 0.1, 0.0), (0.3 * s, -0.02, 0.01)]
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    me.update()
    w = bpy.data.objects.new(nm, me)
    bpy.context.collection.objects.link(w)
    sol = w.modifiers.new("sol", "SOLIDIFY"); sol.thickness = 0.015
    bpy.context.view_layer.objects.active = w
    bpy.ops.object.select_all(action="DESELECT")
    w.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sol")
    assign(w, BIRD)
    join([w], nm, (0.04 * s, 0, 0.02))
export("bird")

# =============================================================== BUILDINGS
# Shrine: stepped stone plinth, carved obelisk with a glowing orb, braziers.
cyl(1.05, 1.05, 0.16, 8, 0, STONE)
cyl(0.8, 0.8, 0.14, 8, 0.16, STONE)
box(0.32, 0.32, 1.2, (0, 0, 0.9), MARBLE)
cyl(0.24, 0.0, 0.3, 4, 1.5, GOLD).rotation_euler = (0, 0, math.pi / 4)
ico(0.16, 2, (0, 0, 2.0), GLOW)
for a in range(4):
    ang = a * math.pi / 2 + math.pi / 4
    x, y = math.cos(ang) * 0.72, math.sin(ang) * 0.72
    cyl(0.05, 0.05, 0.45, 5, 0.3, WOOD, (x, y))
    cyl(0.09, 0.06, 0.08, 6, 0.75, GOLD, (x, y))
    ico(0.05, 1, (x, y, 0.88), GLOW)
box(0.5, 0.05, 0.3, (0, -0.85, 0.12), TRIBE)
finish("shrine")

# Temple: raised marble platform, columns, pediment roof, golden dome and steps.
box(4.0, 3.0, 0.3, (0, 0, 0.15), STONE)
box(3.6, 2.6, 0.25, (0, 0, 0.42), MARBLE)
for i in range(4):
    box(1.4, 0.3, 0.12 * (i + 1), (0, -1.65 - 0.1 * (3 - i), 0.06 * (i + 1)), STONE)
for x in (-1.5, -0.75, 0.0, 0.75, 1.5):
    for y in (-1.1, 1.1):
        cyl(0.13, 0.11, 1.9, 8, 0.55, MARBLE, (x, y))
        box(0.32, 0.32, 0.1, (x, y, 2.5), MARBLE)
for y in (-0.4, 0.4):
    cyl(0.13, 0.11, 1.9, 8, 0.55, MARBLE, (-1.5, y)); cyl(0.13, 0.11, 1.9, 8, 0.55, MARBLE, (1.5, y))
box(1.9, 1.3, 1.6, (0, 0.2, 1.35), PLASTER)   # inner cella
box(0.5, 0.05, 1.0, (0, -0.46, 1.05), DARK)
box(3.9, 2.8, 0.18, (0, 0, 2.64), MARBLE)
prism(3.9, 2.8, 0.75, 2.73, ROOF)
box(0.06, 2.5, 0.06, (1.96, 0, 2.75), GOLD); box(0.06, 2.5, 0.06, (-1.96, 0, 2.75), GOLD)
uvs(0.55, (0, 0, 3.35), GOLD, (1, 1, 0.8), 16, 8)
ico(0.18, 2, (0, 0, 4.0), GLOW)
box(0.9, 0.04, 0.45, (0, -1.42, 2.4), TRIBE)
for x in (-1.85, 1.85):
    cyl(0.12, 0.08, 0.12, 6, 0.67, GOLD, (x, -1.35)); ico(0.07, 1, (x, -1.35, 0.85), GLOW)
finish("temple")

# Hut variant: square log cabin with a lean-to
box(1.5, 1.3, 0.8, (0, 0, 0.4), WOOD)
for z in (0.15, 0.35, 0.55, 0.75):
    box(1.58, 0.06, 0.06, (0, -0.66, z), BARK); box(1.58, 0.06, 0.06, (0, 0.66, z), BARK)
prism(1.75, 1.6, 0.75, 0.8, THATCH)
box(0.32, 0.06, 0.55, (0, -0.66, 0.28), DARK)
box(0.7, 0.6, 0.45, (1.05, 0.2, 0.22), WOOD)
box(0.8, 0.7, 0.05, (1.05, 0.2, 0.5), THATCH, (0, 0.25, 0))
cyl(0.04, 0.04, 1.2, 4, 0.8, WOOD, (-0.6, 0.5)); box(0.06, 0.28, 0.2, (-0.6, 0.64, 1.88), TRIBE)
finish("hut_b")

# House variant: two storey, slate roof, side annex and chimney
box(1.9, 1.5, 0.3, (0, 0, 0.15), STONE)
box(1.8, 1.4, 1.5, (0, 0, 1.05), PLASTER)
for x in (-0.9, 0.0, 0.9):
    box(0.1, 0.1, 1.55, (x, -0.71, 1.05), WOOD)
box(1.85, 0.08, 0.1, (0, -0.72, 1.05), WOOD)
box(1.85, 0.08, 0.1, (0, -0.72, 1.8), WOOD)
prism(2.15, 1.75, 0.95, 1.8, ROOF2)
box(0.32, 0.06, 0.6, (-0.45, -0.72, 0.6), DARK)
for x in (0.45, -0.45, 0.45):
    box(0.28, 0.06, 0.28, (x, -0.72, 1.4), DARK)
box(0.28, 0.06, 0.28, (0.45, -0.72, 0.7), DARK)
box(0.9, 1.0, 0.9, (1.3, 0.1, 0.45), STONE)
prism(1.0, 1.1, 0.4, 0.9, ROOF2, 1.3, 0.1)
box(0.3, 0.3, 1.0, (-0.6, 0.45, 2.4), STONE)
box(0.5, 0.06, 0.3, (0.0, -0.9, 2.0), TRIBE)
finish("house_b")
print("ALL DONE")
