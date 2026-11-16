# /// script
# requires-python = "==3.13.*"
# dependencies = ["bpy==5.2.*"]
# ///
"""Blender as a library: build the dragon kit, art/dragon_kit.glb.

deno task art      uses Blender 5.2 (the header above)
deno task art:lts  uses Blender 4.5 LTS, for Intel Macs, which Blender 5 dropped

Every object is built in code around its own origin and fills one grid cell:
x and y in [-0.5, 0.5], standing on the ground at z = 0. Blender's +Y is the
direction of travel (Godot's forward after the glTF export turns Y up).
Openings must match Kit.OPENINGS in core/kit.gd: head and tail join the body
at the back and front; the turn joins the back and the right side.

The body is one idea used everywhere: sweep an ellipse along a path. Where two
pieces meet, the ellipse is the same circle at the same height, so a chain of
pieces reads as one dragon. Materials are glTF PBR (base color, metallic,
roughness, emission); vertex colors add cheap shading the exporter keeps.
"""

import math
import random

import bpy  # first: importing bpy is what makes bmesh and mathutils available
import bmesh
from mathutils import Matrix, Vector

bpy.ops.wm.read_factory_settings(use_empty=True)  # an empty scene, before making materials

BODY_Z = 0.32  # height of the body's centerline
BODY_R = 0.2  # body radius where pieces meet
RING = 24  # vertices around the body; even, so every ring is mirror symmetric
PLATE = 0.07  # how far each scale plate bulges, as a fraction of the radius
BELLY = math.radians(60)  # half the angle of underside that gets belly plates
SPIKE = (0.2, 0.07, 0.16)  # dorsal spike height, width, length
SMOOTH_ANGLE = math.radians(46)  # sharper edges than this stay crisp
UP = Vector((0, 0, 1))
FORWARD = Vector((0, 1, 0))


# Materials ----------------------------------------------------------------------------------


def srgb(hex_code: str) -> tuple:
    """A '#rrggbb' color as linear RGBA, the space Blender's shader sockets use."""
    rgb = [int(hex_code[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb) + (1.0,)


MATERIALS = []  # every material, in order; a face's material_index points into this list
VERTEX_COLORED = set()  # indices of materials that multiply by vertex colors


def pbr_material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=1.0, vertex_color=False):
    """A Principled BSDF using only inputs glTF keeps. Returns its index in MATERIALS."""
    material = bpy.data.materials.new(name)
    if not material.use_nodes:  # Blender 4.x starts without nodes; 5.x always has them
        material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:  # glTF keeps a color up to 1 plus a strength (KHR_materials_emissive_strength)
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    if vertex_color:  # base color times the mesh's "Col" attribute, exported as glTF COLOR_0
        attribute = nodes.new("ShaderNodeVertexColor")
        attribute.layer_name = "Col"
        multiply = nodes.new("ShaderNodeMix")
        multiply.data_type, multiply.blend_type = "RGBA", "MULTIPLY"
        multiply.inputs["Factor"].default_value = 1.0
        multiply.inputs[7].default_value = srgb(color)  # the color B input
        links.new(attribute.outputs["Color"], multiply.inputs[6])  # the color A input
        links.new(multiply.outputs[2], bsdf.inputs["Base Color"])  # the color result
    material.diffuse_color = srgb(color)  # the viewport's solid color, for the GUI
    material.use_backface_culling = True  # exported as single-sided, cheaper to draw
    MATERIALS.append(material)
    if vertex_color:
        VERTEX_COLORED.add(len(MATERIALS) - 1)
    return len(MATERIALS) - 1


SCALES = pbr_material("Scales", "#17836c", metallic=0.2, roughness=0.45, vertex_color=True)
BELLY_PLATES = pbr_material("Belly", "#ead49a", metallic=0.1, roughness=0.55, vertex_color=True)
GOLD = pbr_material("Gold", "#f7c64f", metallic=1.0, roughness=0.3)
HORN = pbr_material("Horn", "#f3e7cf", roughness=0.4, vertex_color=True)
EYE = pbr_material("Eye", "#ffb22e", roughness=0.2, emission="#ffa21a", strength=6.0)
PUPIL = pbr_material("Pupil", "#120a08", roughness=0.25)
FLAME = pbr_material("TailFlame", "#ff6a1a", roughness=0.35, emission="#ff4a08", strength=1.5)
EMBER = pbr_material("Ember", "#ff7a22", roughness=0.25, emission="#ff5a0e", strength=5.0)
CHARCOAL = pbr_material("Charcoal", "#2c2422", roughness=0.9, emission="#ff3c0a", strength=0.25)
ARCANE = pbr_material("Arcane", "#6a34d6", roughness=0.12, emission="#8a4dff", strength=1.2)
ARCANE_GLOW = pbr_material("ArcaneGlow", "#d2a8ff", roughness=0.2, emission="#b77bff", strength=6.0)
STONE = pbr_material("Stone", "#8f8777", roughness=0.85, vertex_color=True)
WALL_STONE = pbr_material("WallStone", "#5a5049", roughness=0.9, vertex_color=True)
# Godot finds "Lava" and "Water" by name and animates them with a small shader
# (app/stage.gd), reading these colors as its starting point.
LAVA = pbr_material("Lava", "#ff6418", roughness=0.6, emission="#ff4a0a", strength=2.2)
CRUST = pbr_material("LavaCrust", "#33241e", roughness=0.95, emission="#ff3c0a", strength=0.12, vertex_color=True)
WATER = pbr_material("Water", "#123f52", roughness=0.05)
WOOD = pbr_material("Wood", "#9a6a3e", roughness=0.72, vertex_color=True)
ROPE = pbr_material("Rope", "#c9a66b", roughness=0.9)


# Small math helpers ---------------------------------------------------------------------------


def spline(*keys):
    """A smooth curve through (x, value) keys, x ascending, flat at both ends."""
    xs, vs = [k[0] for k in keys], [k[1] for k in keys]
    slopes = [0.0] + [(vs[i + 1] - vs[i - 1]) / (xs[i + 1] - xs[i - 1]) for i in range(1, len(keys) - 1)] + [0.0]

    def curve(x):
        x = min(max(x, xs[0]), xs[-1])
        i = max(j for j in range(len(xs) - 1) if xs[j] <= x)
        h = xs[i + 1] - xs[i]
        u = (x - xs[i]) / h
        return (  # cubic Hermite: matches the value and slope at both keys
            (2 * u**3 - 3 * u**2 + 1) * vs[i]
            + (u**3 - 2 * u**2 + u) * h * slopes[i]
            + (-2 * u**3 + 3 * u**2) * vs[i + 1]
            + (u**3 - u**2) * h * slopes[i + 1]
        )

    return curve


def plates(s, count):
    """0 in the grooves between scale plates, near 1 across each plate; s runs 0 to 1."""
    return abs(math.sin(math.pi * count * s)) ** 0.5


def bezier(p0, p1, p2):
    """A quadratic Bezier path from p0 to p2, pulled toward p1."""
    p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
    return lambda t: (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t**2 * p2


def frame(path, t, up=UP):
    """The path's direction at t, plus the side and up axes of its cross-section."""
    tangent = (path(t + 1e-4) - path(t - 1e-4)).normalized()
    side = tangent.cross(up).normalized()
    return tangent, side, side.cross(tangent)


def basis(origin, x, y, z):
    """A matrix that moves the unit axes to x, y, z and the origin to origin."""
    m = Matrix.Identity(4)
    for row in range(3):
        m[row][0], m[row][1], m[row][2], m[row][3] = x[row], y[row], z[row], origin[row]
    return m


def surface(path, size, t, phi):
    """A point on a swept surface and its outward direction. phi 0 is the top, +90 degrees the right."""
    tangent, side, up = frame(path, t)
    w, h = size(t)
    point = path(t) + side * (w * math.sin(phi)) + up * (h * math.cos(phi))
    normal = (side * (math.sin(phi) / w) + up * (math.cos(phi) / h)).normalized()
    return point, normal


# Geometry builders: each adds faces to a bmesh, sets their material, and paints them ---------


def paint(bm, faces, shade=1.0):
    """Set the vertex color (a gray that darkens the base color) on every corner of these faces."""
    layer = bm.loops.layers.float_color.verify()
    for face in faces:
        for loop in face.loops:
            loop[layer] = (shade, shade, shade, 1.0)


def faces_of(verts):
    return {f for v in verts for f in v.link_faces}


def sweep(bm, path, size, steps, material, ring=RING, shade=None, close_end=False, closed=False, up=UP):
    """Sweep an ellipse along path(t), t from 0 to 1, and return its rings of vertices.

    size(t) is the ellipse's (half width, half height). material is an index or a
    function (t, phi) -> index, where phi is the angle around the ring (0 on top).
    shade(t, phi) darkens vertices through vertex colors. close_end ends in a
    point; closed joins the last ring back to the first (a torus).
    """
    pick = material if callable(material) else lambda t, phi: material
    rings, grays = [], {}
    count = steps if closed else steps + 1
    for i in range(count):
        t = i / steps
        if close_end and i == steps:
            tip = bm.verts.new(path(t))
            grays[tip] = shade(t, 0.0) if shade else 1.0
            rings.append([tip])
            continue
        _, side, ring_up = frame(path, t, up)
        w, h = size(t)
        rings.append([])
        for k in range(ring):
            phi = 2 * math.pi * k / ring
            v = bm.verts.new(path(t) + side * (w * math.sin(phi)) + ring_up * (h * math.cos(phi)))
            grays[v] = shade(t, phi) if shade else 1.0
            rings[-1].append(v)
    layer = bm.loops.layers.float_color.verify()
    for i in range(steps):
        a, b = rings[i], rings[(i + 1) % count]
        for k in range(ring):
            k1 = (k + 1) % ring
            face = bm.faces.new((a[k], a[k1], b[0]) if len(b) == 1 else (a[k], a[k1], b[k1], b[k]))
            face.material_index = pick((i + 0.5) / steps, 2 * math.pi * (k + 0.5) / ring)
            for loop in face.loops:
                g = grays[loop.vert]
                loop[layer] = (g, g, g, 1.0)
    return rings


def spike(bm, base, up, forward, size=SPIKE, scale=1.0, material=GOLD):
    """A flattened cone standing on base, pointing along up; size is (height, width, length)."""
    height, width, length = (d * scale for d in size)
    side = forward.cross(up).normalized()
    forward = up.cross(side)  # square to up, in case the caller's forward leaned
    m = basis(base + up * (height / 2), side * (width / 2), forward * (length / 2), up * height)
    cone = bmesh.ops.create_cone(bm, cap_ends=False, segments=6, radius1=1, radius2=0, depth=1, matrix=m)
    faces = faces_of(cone["verts"])
    for f in faces:
        f.material_index = material
    paint(bm, faces)


def ellipsoid(bm, center, radii, material, axes=None, segments=12, rings=8, shade=1.0):
    """A squashed sphere; axes, if given, are its three (unit) directions."""
    x, y, z = axes or (Vector((1, 0, 0)), FORWARD, UP)
    m = basis(Vector(center), x * radii[0], y * radii[1], z * radii[2])
    sphere = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1, matrix=m)
    faces = faces_of(sphere["verts"])
    for f in faces:
        f.material_index = material
    paint(bm, faces, shade)
    return faces


def rounded_box(bm, low, high, bevel, material, segments=3):
    """A box from corner low to corner high with rounded edges. Returns its faces."""
    low, high = Vector(low), Vector(high)
    m = Matrix.Translation((low + high) / 2) @ Matrix.Diagonal((*(high - low), 1))
    cube = bmesh.ops.create_cube(bm, size=1, matrix=m)
    edges = list({e for v in cube["verts"] for e in v.link_edges})
    result = bmesh.ops.bevel(
        bm, geom=cube["verts"] + edges, offset=bevel, segments=segments, profile=0.5, affect="EDGES"
    )
    faces, stack = set(), list(result["verts"])  # walk outward to collect the whole box
    while stack:
        for f in stack.pop().link_faces:
            if f not in faces:
                faces.add(f)
                stack.extend(f.verts)
    for f in faces:
        f.material_index = material
    return faces


def mottle(bm, faces, low, high, seed, rim=None):
    """Vary vertex grays between low and high so stone looks worn, not plastic.
    rim, if given, darkens vertices below the top face (the beveled edge reads as a groove)."""
    layer = bm.loops.layers.float_color.verify()
    rng = random.Random(seed)  # a fixed seed: the same stone on every run
    top = max(v.co.z for f in faces for v in f.verts)
    grays = {}
    for f in faces:
        for loop in f.loops:
            v = loop.vert
            if v not in grays:
                grays[v] = rng.uniform(low, high) * (rim if rim and v.co.z < top - 0.005 else 1.0)
            g = grays[v]
            loop[layer] = (g, g, g, 1.0)


# The body: a tube of scale plates, a pale belly, and gold spikes along the spine -------------


def body_material(t, phi):
    return BELLY_PLATES if abs(phi - math.pi) < BELLY else SCALES


def countershade(phi):
    """Darker along the back, lighter down the flanks, so the spine and its spikes stand out."""
    return 0.7 + 0.3 * math.sin(phi / 2) ** 2


def body_tube(bm, path, steps, count=2):
    """The standard body: radius BODY_R at both ends, `count` scale plates between."""
    size = lambda t: (BODY_R * (1 + PLATE * plates(t, count)),) * 2
    shade = lambda t, phi: (0.55 + 0.45 * plates(t, count)) * countershade(phi)
    rings = sweep(bm, path, size, steps, body_material, shade=shade)
    for t in [(i + 0.5) / count for i in range(count)]:  # one spike on each plate
        tangent, _, up = frame(path, t)
        spike(bm, path(t) + up * (size(t)[1] - 0.03), up, tangent)
    return [(rings[0], path(0)), (rings[-1], path(1))]


def build_straight(bm):
    return body_tube(bm, lambda t: Vector((0, t - 0.5, BODY_Z)), steps=28)


def build_turn(bm):
    corner = Vector((0.5, -0.5, BODY_Z))  # a quarter circle around the corner the turn hugs

    def arc(t):
        a = math.pi - t * math.pi / 2  # from the back edge (180 degrees) to the right edge (90)
        return corner + Vector((math.cos(a), math.sin(a), 0)) * 0.5

    return body_tube(bm, arc, steps=24)


# The head: neck, skull and snout are one sweep; the features are placed on its surface -------


HEAD_TIP = 0.6  # the snout pokes a little past the front of the cell
head_width = spline((-0.5, 0.2), (-0.32, 0.2), (-0.08, 0.33), (0.1, 0.31), (0.26, 0.22), (0.44, 0.2), (0.6, 0.18))
head_height = spline((-0.5, 0.2), (-0.32, 0.2), (-0.08, 0.26), (0.1, 0.23), (0.26, 0.15), (0.44, 0.13), (0.6, 0.11))
head_z = spline((-0.5, BODY_Z), (-0.32, BODY_Z), (-0.05, 0.38), (0.12, 0.38), (0.3, 0.35), (0.6, 0.34))


def head_y(t):
    return -0.5 + t * (HEAD_TIP + 0.5)


def head_t(y):
    return (y + 0.5) / (HEAD_TIP + 0.5)


def head_path(t):
    return Vector((0, head_y(t), head_z(head_y(t))))


def head_size(t):
    y = head_y(t)
    neck = 1 + PLATE * plates(y + 0.5, 2) if y < 0 else 1  # one plate on the neck, like the body's
    nose = math.sqrt(max(0.0, 1 - ((y - 0.46) / (HEAD_TIP - 0.46)) ** 2)) if y > 0.46 else 1  # round tip
    return head_width(y) * neck * nose, head_height(y) * neck * nose


def head_shade(t, phi):
    y = head_y(t)
    groove = 0.55 + 0.45 * (plates(y + 0.5, 2) if y < 0 else min(1.0, y / 0.06))
    return groove * countershade(phi)


def build_head(bm):
    rings = sweep(bm, head_path, head_size, 60, body_material, shade=head_shade, close_end=True)

    def on_head(y, degrees, sink=0.0):
        """A point sunk into the head's surface at (y, angle), and the surface's outward direction."""
        point, normal = surface(head_path, head_size, head_t(y), math.radians(degrees))
        return point - normal * sink, normal

    for y, scale in ((-0.25, 1.0), (-0.04, 0.7)):  # the neck spike lines up with the body's spikes
        point, normal = on_head(y, 0, sink=0.03)
        spike(bm, point, UP, FORWARD, scale=scale)

    def eye(sign):
        center, normal = on_head(0.1, sign * 62, sink=0.035)
        ellipsoid(bm, center, (0.085, 0.085, 0.085), EYE, segments=14, rings=10)
        # A slit pupil: thin along the gaze, tall along the head's up axis.
        gaze = (normal + FORWARD * 0.6).normalized()
        tall = (UP - gaze * gaze.dot(UP)).normalized()
        ellipsoid(bm, center + gaze * 0.078, (0.012, 0.02, 0.055), PUPIL, (gaze, gaze.cross(tall), tall), 8, 6)

    def horn(sign):
        root, _ = on_head(-0.06, sign * 34, sink=0.03)
        tip = root + Vector((sign * 0.24, -0.3, 0.2))
        path = bezier(root, root + Vector((sign * 0.12, -0.2, 0.04)), tip)  # out and back, curling up
        size = lambda t: (0.06 * (1 - t) ** 0.7,) * 2
        sweep(bm, path, size, 14, HORN, ring=12, shade=lambda t, phi: 0.6 + 0.4 * t, close_end=True)

    def frill(sign):  # three gold fins fanning back from each cheek widen the silhouette
        for y, degrees, scale in ((-0.14, 85, 0.75), (-0.02, 100, 1.0)):
            base, normal = on_head(y, sign * degrees, sink=0.03)
            out = (normal - FORWARD * 1.1).normalized()
            spike(bm, base, out, UP, size=(0.2, 0.025, 0.12), scale=scale)

    def whisker(sign):
        root, _ = on_head(0.47, sign * 95)
        path = bezier(root, root + Vector((sign * 0.2, -0.02, -0.05)), root + Vector((sign * 0.3, -0.3, 0.04)))
        sweep(bm, path, lambda t: (0.02 * (1 - 0.6 * t),) * 2, 10, GOLD, ring=8, close_end=True)

    def nostril(sign):
        point, _ = on_head(0.53, sign * 28, sink=0.006)
        ellipsoid(bm, point, (0.024, 0.032, 0.015), PUPIL, segments=8, rings=6)

    def fang(sign):
        point, _ = on_head(0.47, sign * 140)
        spike(bm, point + UP * 0.02, -UP, FORWARD, size=(0.08, 0.03, 0.03), material=HORN)

    for feature in (eye, horn, frill, whisker, nostril, fang):
        for sign in (1, -1):  # the right side, then the mirror image on the left
            feature(sign)
    return [(rings[0], head_path(0))]


# The tail: the body tapers, then flattens into a glowing spade --------------------------------


TAIL_TIP = -0.56
tail_width = spline(
    (-0.56, 0.0), (-0.5, 0.07), (-0.43, 0.15), (-0.36, 0.19), (-0.3, 0.15), (-0.24, 0.06), (0.0, 0.11), (0.25, 0.17), (0.5, 0.2)
)
tail_height = spline((-0.56, 0.01), (-0.36, 0.025), (-0.2, 0.04), (-0.12, 0.06), (0.0, 0.11), (0.25, 0.17), (0.5, 0.2))
tail_x = spline((-0.56, 0.06), (-0.2, 0.06), (0.15, 0.0), (0.5, 0.0))  # a slight flick to one side
tail_z = spline((-0.56, 0.24), (0.0, 0.29), (0.5, BODY_Z))


def tail_y(t):
    return 0.5 - t * (0.5 - TAIL_TIP)


def tail_path(t):
    y = tail_y(t)
    return Vector((tail_x(y), y, tail_z(y)))


def tail_size(t):
    y = tail_y(t)
    plate = 1 + PLATE * plates(y, 2) if y > 0 else 1
    return tail_width(y) * plate, tail_height(y) * plate


def build_tail(bm):
    def material(t, phi):
        return FLAME if tail_y(t) < -0.21 else body_material(t, phi)

    def shade(t, phi):
        y = tail_y(t)
        groove = 0.55 + 0.45 * (plates(y, 2) if y > 0 else min(1.0, -y / 0.06))
        return groove * countershade(phi) if y > -0.2 else 1.0

    rings = sweep(bm, tail_path, tail_size, 44, material, shade=shade, close_end=True)
    for y, scale in ((0.25, 1.0), (0.0, 0.65), (-0.13, 0.4)):
        t = (0.5 - y) / (0.5 - TAIL_TIP)
        tangent, _, up = frame(tail_path, t)
        spike(bm, tail_path(t) + up * (tail_size(t)[1] - 0.03 * scale), up, tangent, scale=scale)
    return [(rings[0], tail_path(0))]


# Food and pickup ------------------------------------------------------------------------------


def crystal(bm, base, direction, length, radius, material):
    """A six-sided crystal growing from base; its edges are sharp enough to stay faceted."""
    direction = Vector(direction).normalized()
    path = lambda t: Vector(base) + direction * (length * t)
    size = lambda t: (radius * (0.75 + 0.25 * min(1.0, t * 3)),) * 2
    sweep(bm, path, size, 3, material, ring=6, close_end=True)


def build_food(bm):
    """A glowing ember: hot crystals sprouting from a lump of charcoal."""
    m = basis(Vector((0, 0, 0.05)), Vector((0.19, 0, 0)), Vector((0, 0.16, 0)), Vector((0, 0, 0.09)))
    rock = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1, matrix=m)
    rng = random.Random(4)
    for v in rock["verts"]:
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.5, 0.5))) * 0.025
        v.co.z = max(v.co.z, 0.0)  # a flat bottom resting on the ground
    faces = faces_of(rock["verts"])
    for f in faces:
        f.material_index = CHARCOAL
    paint(bm, faces)
    crystal(bm, (0.0, 0.01, 0.06), (0.05, 0.1, 1), 0.34, 0.07, EMBER)
    crystal(bm, (0.08, -0.05, 0.05), (0.6, -0.3, 1), 0.22, 0.05, EMBER)
    crystal(bm, (-0.08, -0.02, 0.05), (-0.7, -0.1, 1), 0.2, 0.048, EMBER)
    crystal(bm, (-0.02, 0.09, 0.05), (-0.2, 0.8, 1), 0.15, 0.04, EMBER)
    return []


def build_pickup(bm):
    """An arcane orb inside a glowing ring and a gold ring, hovering above the ground."""
    center = Vector((0, 0, 0.4))
    ellipsoid(bm, center, (0.15, 0.15, 0.15), ARCANE, segments=24, rings=14)

    def ring(radius, thickness, tilt_axis, tilt, material):
        spin = Matrix.Rotation(tilt, 3, tilt_axis)
        circle = lambda t: center + spin @ Vector((math.cos(2 * math.pi * t), math.sin(2 * math.pi * t), 0)) * radius
        sweep(bm, circle, lambda t: (thickness, thickness), 40, material, ring=8, closed=True, up=spin @ UP)

    ring(0.23, 0.022, "X", math.radians(40), ARCANE_GLOW)
    ring(0.2, 0.012, "Y", math.radians(-35), GOLD)
    return []


# Tiles: one small function per kind of ground, registered in TILES ----------------------------


def build_floor(bm):
    """Flagstone: top flush with the ground (z = 0), 0.15 thick, a grid on top to carry mottling."""
    faces = rounded_box(bm, (-0.5, -0.5, -0.15), (0.5, 0.5, 0.0), 0.035, STONE)
    top = next(f for f in faces if f.normal.z > 0.99 and f.calc_center_median().z > -0.001)
    grid = bmesh.ops.subdivide_edges(bm, edges=top.edges[:], cuts=4, use_grid_fill=True)
    faces |= faces_of([v for v in grid["geom"] if isinstance(v, bmesh.types.BMVert)])
    mottle(bm, faces, 0.78, 1.0, seed=7, rim=0.75)
    return []


def build_wall(bm):
    """A 0.7 high block: one big stone below, two smaller ones above, like brickwork.
    Its foot reaches as deep as a flagstone, so no gap shows beside a sunken pool."""
    mottle(bm, rounded_box(bm, (-0.5, -0.5, -0.15), (0.5, 0.5, 0.4), 0.04, WALL_STONE), 0.6, 0.8, seed=11)
    for seed, (x0, x1) in enumerate(((-0.5, 0.0), (0.0, 0.5))):
        mottle(bm, rounded_box(bm, (x0, -0.5, 0.4), (x1, 0.5, 0.7), 0.04, WALL_STONE), 0.85, 1.0, seed=seed)
    return []


def sheet(bm, z, material, cuts=6):
    """A flat square filling the cell at height z, cut into a grid a shader can ripple."""
    grid = bmesh.ops.create_grid(bm, x_segments=cuts, y_segments=cuts, size=0.5, matrix=Matrix.Translation((0, 0, z)))
    faces = faces_of(grid["verts"])
    for f in faces:
        f.material_index = material
    paint(bm, faces)
    return faces


def build_lava(bm):
    """A sunken pool of molten rock: the glow sits 0.1 below the floor, so the edges of
    the flagstones around it read as banks. Two cooling crusts float on top."""
    sheet(bm, -0.1, LAVA)
    for seed, (x, y, r) in enumerate(((-0.2, 0.18, 0.13), (0.22, -0.15, 0.09))):
        rng = random.Random(seed + 30)
        faces = ellipsoid(bm, (x, y, -0.1), (r, r * 0.8, 0.03), CRUST, segments=9, rings=5)
        for v in {v for f in faces for v in f.verts}:  # break the outline so it reads as rock
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * r * 0.18
        mottle(bm, faces, 0.6, 1.0, seed=seed)
    return []


def build_water(bm):
    """Still water a little below the floor: smooth enough to mirror the dusk sky.
    The ripples come from Godot's water shader, which moves this grid."""
    sheet(bm, -0.07, WATER)
    return []


def build_bridge(bm):
    """Planks across two beams, running along +Y (the direction of travel), with the
    river showing between them. Godot turns each bridge to follow its crossing."""
    sheet(bm, -0.07, WATER)
    for x in (-0.36, 0.36):
        mottle(bm, rounded_box(bm, (x - 0.05, -0.5, -0.07), (x + 0.05, 0.5, -0.005), 0.015, WOOD), 0.45, 0.6, seed=3)
    rng = random.Random(5)
    for i in range(6):  # each plank a little crooked, like hand-laid boards
        y, lift, shift = -0.5 + (i + 0.5) / 6, rng.uniform(-0.006, 0.006), rng.uniform(-0.02, 0.02)
        plank = rounded_box(bm, (-0.43 + shift, y - 0.075, -0.005 + lift), (0.43 + shift, y + 0.075, 0.035 + lift), 0.012, WOOD)
        mottle(bm, plank, 0.7, 1.0, seed=i, rim=0.8)
    for x in (-0.46, 0.46):
        for y in (-0.38, 0.38):
            mottle(bm, rounded_box(bm, (x - 0.035, y - 0.035, -0.1), (x + 0.035, y + 0.035, 0.24), 0.01, WOOD), 0.4, 0.55, seed=9)
        rope = bezier((x, -0.38, 0.2), (x, 0.0, 0.08), (x, 0.38, 0.2))  # sags between its posts
        sweep(bm, rope, lambda t: (0.012, 0.012), 16, ROPE, ring=6)
    return []


# Turning a bmesh into an exportable object ----------------------------------------------------


def smooth_by_angle(bm, angle=SMOOTH_ANGLE):
    """Smooth shading, except across edges sharper than angle (like Shade Auto Smooth)."""
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if e.is_manifold and e.calc_face_angle() > angle:
            e.smooth = False


def weld_seams(mesh, seams):
    """Point the normals of open tube ends straight out from the centerline.

    Neighboring pieces then agree exactly on the shading where they meet, even
    when one of them bends (the turn) or swells (the head).
    """
    normals = [Vector(c.vector) for c in mesh.corner_normals]
    for loop in mesh.loops:
        center = seams.get(loop.vertex_index)
        if center is not None:
            normals[loop.index] = (mesh.vertices[loop.vertex_index].co - center).normalized()
    mesh.normals_split_custom_set(normals)


def make_object(name, build):
    """Run a builder on a fresh bmesh and turn the result into a mesh object called name.
    A builder returns the open ends of its tubes as (ring of vertices, center) pairs."""
    bm = bmesh.new()
    bm.loops.layers.float_color.new("Col")
    seams = build(bm)
    smooth_by_angle(bm)
    bm.verts.index_update()
    seam_centers = {v.index: center for ring, center in seams for v in ring}
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    # Keep only the materials this object uses, renumbering faces to match.
    used = sorted({p.material_index for p in mesh.polygons})
    mesh.polygons.foreach_set("material_index", [used.index(p.material_index) for p in mesh.polygons])
    for index in used:
        mesh.materials.append(MATERIALS[index])
    if VERTEX_COLORED.isdisjoint(used):  # nothing here shows vertex colors, so don't export them
        mesh.color_attributes.remove(mesh.color_attributes["Col"])
    else:
        mesh.color_attributes.active_color_index = 0
        mesh.color_attributes.render_color_index = 0
    weld_seams(mesh, seam_centers)
    bpy.context.scene.collection.objects.link(bpy.data.objects.new(name, mesh))


# The rival: the same shapes in obsidian and crimson ----------------------------------------

# Each of the hero's materials and the rival's stand-in. A builder paints faces with the
# hero's materials; rival() repaints them afterward, so the shapes are never copied.
RIVAL_PALETTE = {
    SCALES: pbr_material("RivalScales", "#26222c", metallic=0.5, roughness=0.22, vertex_color=True),
    BELLY_PLATES: pbr_material("RivalBelly", "#8c1f26", metallic=0.1, roughness=0.5, vertex_color=True),
    GOLD: pbr_material("RivalSpikes", "#d02a2a", metallic=0.9, roughness=0.28),
    HORN: pbr_material("RivalHorn", "#3a3036", roughness=0.35, vertex_color=True),
    EYE: pbr_material("RivalEye", "#ff2e3a", roughness=0.2, emission="#ff1a2a", strength=6.0),
    FLAME: pbr_material("RivalFlame", "#c0182a", roughness=0.35, emission="#ff1030", strength=1.8),
}


def rival(build):
    """A builder for the rival's version of a piece: build it, then swap the palette."""

    def build_rival(bm):
        seams = build(bm)
        for face in bm.faces:
            face.material_index = RIVAL_PALETTE.get(face.material_index, face.material_index)
        return seams

    return build_rival


PIECES = {  # the dragon kit; the Godot side finds each mesh by these names
    "head": build_head,
    "straight": build_straight,
    "turn": build_turn,
    "tail": build_tail,
    "food": build_food,
    "pickup": build_pickup,
}
for piece in ("head", "straight", "turn", "tail"):  # rival_head, rival_straight, ...
    PIECES["rival_" + piece] = rival(PIECES[piece])
TILES = {  # one entry per kind of ground; a new kind is one build_ function and one line here
    "floor": build_floor,
    "wall": build_wall,
    "lava": build_lava,
    "water": build_water,
    "bridge": build_bridge,
}

for name, build in (PIECES | TILES).items():
    make_object(name, build)

bpy.ops.export_scene.gltf(
    filepath="art/dragon_kit.glb", export_apply=True, export_cameras=False, export_lights=False
)
print(f"Built art/dragon_kit.glb with Blender {bpy.app.version_string}")
