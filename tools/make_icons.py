# Renders the expansion's toolbar icons with Blender Cycles (CPU), matching the
# round, gold-framed look of the original power icons.
#   python tools/make_icons.py -- assets/icons      (bpy module)
#   blender -b --python tools/make_icons.py -- assets/icons
import bpy, sys, math, os
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/icons"
HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "assets", "models")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, emit=0.0, metal=0.0, rough=0.6, flat=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1) if flat else (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def obj(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def frame_scene(bg_top, bg_bottom):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.render.resolution_x = 128
    sc.render.resolution_y = 128
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.33, 0.4, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.1
    cam.location = (0, 0, 10)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(35), math.radians(-25), 0)
    sc.collection.objects.link(sun)
    # backdrop disc with a vertical gradient (two stacked discs)
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.93, depth=0.05, location=(0, 0, -1.0))
    obj(bpy.context.active_object, mat("bg", bg_bottom, emit=1.0, flat=True))
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.6, depth=0.05, location=(0, 0.25, -0.97))
    d = bpy.context.active_object
    d.scale = (1.3, 1.0, 1)
    obj(d, mat("bg2", bg_top, emit=0.7, flat=True))
    # gold frame
    bpy.ops.mesh.primitive_torus_add(major_radius=0.95, minor_radius=0.065, major_segments=64, minor_segments=12, location=(0, 0, -0.5))
    obj(bpy.context.active_object, mat("gold", (0.85, 0.62, 0.22), metal=0.9, rough=0.3))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.02, major_segments=64, minor_segments=8, location=(0, 0, -0.45))
    obj(bpy.context.active_object, mat("gold2", (0.55, 0.38, 0.12), metal=0.9, rough=0.4))


def render(name):
    bpy.context.scene.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("ICON", name)


def island(z, grass=(0.3, 0.6, 0.22)):
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.62, radius2=0.42, depth=0.28, location=(0, -0.05, z))
    i = bpy.context.active_object
    i.rotation_euler = (math.radians(-55), 0, 0)
    obj(i, mat("sand", (0.92, 0.82, 0.55)))
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.46, radius2=0.2, depth=0.3, location=(0, 0.05, z + 0.18))
    g = bpy.context.active_object
    g.rotation_euler = (math.radians(-55), 0, 0)
    obj(g, mat("grass", grass))
    return i, g


def water(z=-0.6):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.86, depth=0.05, location=(0, -0.35, z))
    w = bpy.context.active_object
    w.scale = (1.0, 0.45, 1)
    obj(w, mat("water", (0.15, 0.55, 0.85), emit=0.3, rough=0.1))


def tree(x, y, z, s=1.0):
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=0.12 * s, radius2=0, depth=0.35 * s, location=(x, y, z))
    t = bpy.context.active_object
    t.rotation_euler = (math.radians(-90), 0, 0)
    obj(t, mat("pine", (0.15, 0.45, 0.22)))


def arrow(up, color, y0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.07, depth=0.42, location=(0.48, y0, 0.2))
    a = bpy.context.active_object
    a.rotation_euler = (math.radians(90), 0, 0)
    obj(a, mat("arr", color, emit=2.0))
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.16, radius2=0, depth=0.22,
                                    location=(0.48, y0 + (0.3 if up else -0.3), 0.2))
    h = bpy.context.active_object
    h.rotation_euler = (math.radians(-90 if up else 90), 0, 0)
    obj(h, mat("arrh", color, emit=2.0))


os.makedirs(out, exist_ok=True)

# --- Create Land: an island rising from the sea, golden up-arrow
reset(); frame_scene((0.06, 0.16, 0.42), (0.01, 0.04, 0.14))
water(); island(-0.2); tree(-0.1, 0.18, 0.2); tree(0.12, 0.12, 0.15, 0.8)
arrow(True, (1.0, 0.85, 0.3), 0.05)
render("land")

# --- Remove Land: an island sinking, blue down-arrow
reset(); frame_scene((0.05, 0.12, 0.3), (0.01, 0.03, 0.1))
island(-0.45, (0.35, 0.5, 0.3))
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.86, depth=0.05, location=(0, -0.2, -0.2))
w = bpy.context.active_object
w.scale = (1.0, 0.6, 1)
obj(w, mat("water2", (0.15, 0.5, 0.85), emit=0.4, rough=0.1))
arrow(False, (0.45, 0.8, 1.0), 0.1)
render("remove")

# --- Miracle of Plenty: a basket of bread and fruit with a golden glow
reset(); frame_scene((0.35, 0.18, 0.05), (0.08, 0.03, 0.02))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, -0.2, 0))
glow = bpy.context.active_object
glow.scale = (1.4, 1.0, 0.1)
glow.location = (0, 0.05, -0.8)
obj(glow, mat("halo", (1.0, 0.8, 0.35), emit=3.0))
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.5, depth=0.36, location=(0, -0.25, 0))
b = bpy.context.active_object
b.rotation_euler = (math.radians(-60), 0, 0)
b.scale = (1.0, 1.0, 1.0)
obj(b, mat("basket", (0.62, 0.38, 0.16)))
for (x, y, r, c) in [(-0.22, 0.02, 0.16, (0.85, 0.15, 0.15)), (0.05, 0.1, 0.2, (0.95, 0.75, 0.35)),
                     (0.28, 0.0, 0.15, (0.95, 0.6, 0.1)), (-0.05, -0.05, 0.13, (0.5, 0.2, 0.6)),
                     (0.15, 0.22, 0.12, (0.4, 0.75, 0.2))]:
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y + 0.02, 0.3))
    obj(bpy.context.active_object, mat("f", c, rough=0.35))
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(-0.05, 0.3, 0.25))
loaf = bpy.context.active_object
loaf.scale = (1.6, 0.8, 0.7)
obj(loaf, mat("bread", (0.85, 0.58, 0.28)))
render("plenty")

# --- God Hand: the actual hand model, palm open, with a golden aura
reset(); frame_scene((0.2, 0.12, 0.38), (0.04, 0.02, 0.12))
bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "god_hand.glb"))
root = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
root.rotation_euler = (math.radians(90), 0, math.radians(200))
root.scale = (0.95, 0.95, 0.95)
root.location = (-0.02, -0.08, 0)
render("hand")
print("ALL ICONS DONE")
