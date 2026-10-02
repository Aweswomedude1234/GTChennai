#!/usr/bin/env python3
"""Vehicle models for GTIndian, built procedurally in Blender (run with a Python that has `bpy`):

    /path/to/python-with-bpy tools/vehicles/build_vehicles.py [--only auto,bike,...]

Bodies are lofted from cross-sections (so panels are smooth and curved, not boxes), subdivided,
then given materials by region (paint, glass, black trim, chrome, lamps, plates, rubber). Wheel
arches are cut with booleans. Wheels are lathed (tyre with tread blocks, rim, hub) and exported as
separate nodes named `wheel_<i>` with their origin at the hub, so the game can spin and steer them.

Front of every vehicle faces Blender +Y (→ Godot −Z after glTF export). Units are metres; real
dimensions of the Indian vehicles they're based on (fictional makes, no logos).

Output: godot/assets/vehicles/<id>.glb. Materials are named so the game can re-colour:
  paint (body colour), paint2 (second livery colour), glass, trim (black plastic), chrome, rubber,
  rim, lamp_head, lamp_tail, lamp_ind, plate, canvas, seat, interior, metal.
"""
import argparse, math, os, sys
import bpy, bmesh
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "vehicles")

# ------------------------------------------------------------------------------------- materials
MATS = {}

def mat(name, color, metallic=0.0, rough=0.5, emission=None, alpha=1.0, coat=0.0, trans=0.0):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.05
    if emission:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = 1.0
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    MATS[name] = m
    return m


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def std_mats(paint="#f2b705", paint2="#1f5e2e"):
    MATS.clear()
    return {
        "paint": mat("paint", lin(paint), 0.15, 0.32, coat=0.6),
        "paint2": mat("paint2", lin(paint2), 0.1, 0.4, coat=0.4),
        "glass": mat("glass", (0.03, 0.04, 0.045), 0.0, 0.04, alpha=0.55),
        "trim": mat("trim", (0.025, 0.025, 0.025), 0.0, 0.55),
        "chrome": mat("chrome", (0.9, 0.9, 0.9), 1.0, 0.12),
        "rubber": mat("rubber", (0.018, 0.018, 0.018), 0.0, 0.85),
        "rim": mat("rim", (0.55, 0.56, 0.58), 0.8, 0.3),
        "lamp_head": mat("lamp_head", (0.9, 0.9, 0.88), 0.0, 0.05, emission=(0.0, 0.0, 0.0)),
        "lamp_tail": mat("lamp_tail", (0.55, 0.02, 0.02), 0.0, 0.1),
        "lamp_ind": mat("lamp_ind", (0.9, 0.42, 0.02), 0.0, 0.1),
        "plate": mat("plate", lin("#f4f1e6"), 0.0, 0.4),
        "plate_y": mat("plate_y", lin("#f2c811"), 0.0, 0.4),
        "canvas": mat("canvas", lin("#1a1c1a"), 0.0, 0.9),
        "seat": mat("seat", lin("#3a2418"), 0.0, 0.55),
        "interior": mat("interior", lin("#2a2724"), 0.0, 0.8),
        "metal": mat("metal", lin("#4a4c4e"), 0.7, 0.45),
        "engine": mat("engine", lin("#6e6f70"), 0.6, 0.5),
    }


# ------------------------------------------------------------------------------------ mesh utils
def new_obj(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats: me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_mods(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def subsurf(ob, levels=2, crease_edges=None):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    apply_mods(ob)


def smooth(ob):
    for p in ob.data.polygons: p.use_smooth = True


def loft(name, rings, mats, cap=True):
    """rings: list of lists of Vector (equal length, closed loops). Quads between rings, n-gon caps."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(vr[:-1], vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(vr[0][::-1])
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, mats)


def rbox(name, c, size, mats, bevel=0.03, segments=3):
    """rounded box (bevel modifier) centred at c"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(c)
    ob = new_obj(name, bm, mats)
    if bevel > 0:
        m = ob.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = segments
        m.limit_method = "NONE"
        apply_mods(ob)
    smooth(ob)
    return ob


def tube(name, pts, r, mats, seg=10, closed=False):
    """sweep a circle along a polyline (pipes, frames, handlebars)"""
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        a = t.cross(up).normalized(); b = t.cross(a).normalized()
        rings.append([p + (a * math.cos(k / seg * 2 * math.pi) + b * math.sin(k / seg * 2 * math.pi)) * r for k in range(seg)])
    ob = loft(name, rings, mats, cap=True)
    smooth(ob)
    return ob


def lathe(name, profile, mats, seg=32, axis="X", mat_idx=None):
    """surface of revolution around the X axis from profile [(x, r), …]"""
    bm = bmesh.new()
    rings = []
    for (x, r) in profile:
        rings.append([bm.verts.new((x, r * math.cos(k / seg * 2 * math.pi), r * math.sin(k / seg * 2 * math.pi))) for k in range(seg)])
    for ri, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        for k in range(seg):
            f = bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
            if mat_idx: f.material_index = mat_idx[ri]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, mats)
    smooth(ob)
    return ob


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def assign(ob, rule, mats_by_name):
    """rule(centroid, normal) -> material name or None (keep)"""
    names = [m.name for m in ob.data.materials]
    for mname in set(mats_by_name):
        if mname not in names:
            ob.data.materials.append(mats_by_name[mname]); names.append(mname)
    for p in ob.data.polygons:
        r = rule(p.center, p.normal)
        if r: p.material_index = names.index(r)


def boolean_cut(ob, cutter):
    m = ob.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.solver = "EXACT"
    m.use_self = True      # needed: without it the exact solver can drop most of a dense loft
    m.object = cutter
    apply_mods(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)


def cylinder_x(name, c, r, w, seg=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=w)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(c))
    return new_obj(name, bm, [])



# ------------------------------------------------------------------------- parametric shells
def cr_chain(pts, subs):
    """Catmull-Rom through control tuples; segment k gets subs[k] samples. Returns samples and, per
    sample, (segment, substep)."""
    n = len(pts)
    out, tags = [], []
    P = [tuple(p) for p in pts]
    for k in range(n - 1):
        p0 = P[k - 1] if k > 0 else tuple(2 * a - b for a, b in zip(P[0], P[1]))
        p1, p2 = P[k], P[k + 1]
        p3 = P[k + 2] if k + 2 < n else tuple(2 * a - b for a, b in zip(P[-1], P[-2]))
        for s in range(subs[k]):
            t = s / subs[k]
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3) for a, b, c, d in zip(p0, p1, p2, p3)))
            tags.append((k, s))
    out.append(P[-1]); tags.append((n - 1, 0))
    return out, tags


def param_shell(name, stations, profile, region, mats, step_y=0.045, prof_subs=None, cap_mat="trim"):
    """Smooth closed body from control stations. stations: list of parameter tuples whose first
    element is y; they are Catmull-Rom interpolated along the length (≈step_y spacing). profile(st)
    returns the right-half cross-section control points [(x, z)] from bottom centre to top centre.
    region(y, seg, sub, centre, normal) -> material name. Window and pillar edges fall exactly on
    station / profile rows, so material boundaries are clean lines, not stair-steps."""
    subs_y = [max(2, round(abs(b[0] - a[0]) / step_y)) for a, b in zip(stations[:-1], stations[1:])]
    sts, _ = cr_chain(stations, subs_y)
    bm = bmesh.new()
    rings, half_tags = [], None
    for st in sts:
        cps = profile(st)
        ps = prof_subs or [3] * (len(cps) - 1)
        half, tags = cr_chain(cps, ps)
        half_tags = tags
        y = st[0]
        ring = [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[1:-1])]
        rings.append([bm.verts.new(p) for p in ring])
    R = len(half_tags) - 1          # half rows
    nr = len(rings[0])
    info = {}
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(nr):
            j = (k + 1) % nr
            f = bm.faces.new((a[k], a[j], b[j], b[k]))
            hr = k if k < R else nr - 1 - k   # half-row index of this face band (mirrored on the left)
            info[f] = ((sts[i][0] + sts[i + 1][0]) / 2, half_tags[min(hr, R - 1)])
    cap0 = bm.faces.new(rings[0][::-1]); cap1 = bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    names = list(mats.keys())
    for f, (y, (seg, sub)) in info.items():
        m = region(y, seg, sub, f.calc_center_median(), f.normal)
        f.material_index = names.index(m) if m else 0
    for c in (cap0, cap1): c.material_index = names.index(cap_mat)
    ob = new_obj(name, bm, [mats[n] for n in names])
    smooth(ob)
    return ob

# ------------------------------------------------------------------------------------------ wheels
def wheel(name, R, width, rim_r, M, spokes=5, style="alloy", tread=True):
    """tyre (with tread blocks) + rim + hub, axle along X, origin at the hub"""
    seg = 40
    w = width / 2
    prof = [(-w * 0.92, rim_r * 1.02), (-w, rim_r + (R - rim_r) * 0.45), (-w * 0.9, R - 0.012), (-w * 0.55, R), (w * 0.55, R), (w * 0.9, R - 0.012), (w, rim_r + (R - rim_r) * 0.45), (w * 0.92, rim_r * 1.02)]
    tyre = lathe(name + "_tyre", prof, [M["rubber"]], seg=seg)
    if tread:
        # tread blocks: push alternate outer verts out a few mm
        for v in tyre.data.vertices:
            r = math.hypot(v.co.y, v.co.z)
            if r > R - 0.004:
                ang = math.atan2(v.co.z, v.co.y)
                if int((ang + math.pi) / (2 * math.pi) * seg) % 2 == 0:
                    k = (r + 0.004) / r
                    v.co.y *= k; v.co.z *= k
    parts = [tyre]
    if style == "wire":
        rim = lathe(name + "_rim", [(-w * 0.6, rim_r * 0.96), (-w * 0.6, rim_r * 1.04), (w * 0.6, rim_r * 1.04), (w * 0.6, rim_r * 0.96)], [M["chrome"]], seg=seg)
        hub = lathe(name + "_hub", [(-0.06, 0.0), (-0.06, 0.055), (0.06, 0.055), (0.06, 0.0)], [M["chrome"]], seg=16)
        parts += [rim, hub]
        for k in range(36):
            a = k / 36 * 2 * math.pi
            side = -0.05 if k % 2 else 0.05
            p0 = Vector((side, 0.05 * math.cos(a + 0.3), 0.05 * math.sin(a + 0.3)))
            p1 = Vector((0, rim_r * 0.97 * math.cos(a), rim_r * 0.97 * math.sin(a)))
            parts.append(tube(name + f"_sp{k}", [p0, p1], 0.0022, [M["chrome"]], seg=4))
    else:
        # dished rim face with spokes
        rim = lathe(name + "_rim", [(-w * 0.7, rim_r * 1.0), (-w * 0.7, rim_r * 0.93), (-w * 0.2, rim_r * 0.88), (w * 0.35, rim_r * 0.86), (w * 0.6, rim_r * 0.93), (w * 0.6, rim_r * 1.0)], [M["rim"]], seg=seg)
        hub = lathe(name + "_hub", [(w * 0.1, 0.0), (w * 0.1, rim_r * 0.28), (w * 0.35, rim_r * 0.26), (w * 0.4, rim_r * 0.12), (w * 0.42, 0.0)], [M["rim"]], seg=24)
        parts += [rim, hub]
        for k in range(spokes):
            a = k / spokes * 2 * math.pi
            for da in (-0.09, 0.09):
                p0 = Vector((w * 0.3, rim_r * 0.25 * math.cos(a + da), rim_r * 0.25 * math.sin(a + da)))
                p1 = Vector((w * 0.15, rim_r * 0.9 * math.cos(a + da * 0.6), rim_r * 0.9 * math.sin(a + da * 0.6)))
                parts.append(tube(name + f"_sp{k}{da}", [p0, p1], rim_r * 0.045, [M["rim"]], seg=6))
        if style == "steel":  # hubcap-less steel wheel: holes ring
            pass
    ob = join(parts, name)
    return ob


def place(ob, loc, mirror=False):
    if mirror:
        ob.scale.x = -1
        apply_scale(ob)
    ob.location = Vector(loc)


def apply_scale(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.flip_normals() if hasattr(ob.data, "flip_normals") else None


# ------------------------------------------------------------------------------- shared helpers
def lamp(name, c, r, depth, M, kind="lamp_head", facing=1, seg=20):
    """round lamp: chrome bezel + lens facing ±Y"""
    prof = [(0.0, r * 1.18), (depth * 0.6, r * 1.18), (depth * 0.7, r * 1.02), (depth, r * 0.9), (depth * 1.05, 0.0)]
    ob = lathe(name, prof, [M["chrome"], M[kind]], seg=seg, mat_idx=[0, 0, 1, 1])
    # lathe is around X; rotate to face Y
    ob.rotation_euler = (0, 0, math.pi / 2 if facing > 0 else -math.pi / 2)
    ob.location = Vector(c)
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return ob


def mirror_x(ob):
    m = ob.modifiers.new("mir", "MIRROR")
    m.use_axis[0] = True
    m.use_clip = True
    apply_mods(ob)
    return ob


def plate_text_board(name, c, size, M, mname="plate", facing=1):
    ob = rbox(name, c, size, [M[mname]], bevel=0.004, segments=1)
    return ob


# ===================================================================================== AUTO RICKSHAW
def build_auto(variant=0):
    """Chennai auto-rickshaw (Bajaj RE class, fictional 'Bajrang'): 2.63 × 1.30 × 1.71 m"""
    pal = [("#f2b705", "#1f5e2e"), ("#f4c20d", "#111111"), ("#efb50a", "#1b4f8a")][variant % 3]
    M = std_mats(*pal)
    parts = []
    # --- front cowl: lofted from the nose (narrow) to the dashboard (wide); headlamp sits on the nose
    def cowl_ring(y, w, z0, z1, round_top=0.6):
        ring = []
        n = 16
        for k in range(n):
            t = k / n * 2 * math.pi
            x = math.cos(t) * w
            zz = math.sin(t)
            z = (z0 + z1) / 2 + zz * (z1 - z0) / 2
            if zz > 0: x *= 1 - round_top * zz ** 3 * 0.35
            ring.append(Vector((x, y, z)))
        return ring
    rings = [cowl_ring(1.31, 0.14, 0.62, 0.96, 0.8), cowl_ring(1.27, 0.22, 0.48, 1.02), cowl_ring(1.15, 0.3, 0.42, 1.08), cowl_ring(0.95, 0.4, 0.38, 1.14),
             cowl_ring(0.75, 0.52, 0.36, 1.18), cowl_ring(0.58, 0.62, 0.36, 1.2), cowl_ring(0.52, 0.63, 0.36, 1.2)]
    cowl = loft("cowl", rings, [M["paint"]])
    subsurf(cowl, 2); smooth(cowl)
    parts.append(cowl)
    # front mudguard over the front wheel (curved sheet)
    mg = []
    for k in range(13):
        a = math.pi * (0.1 + 0.8 * k / 12)
        r = 0.27
        mg.append([Vector((x, 1.0 + r * math.cos(a) * 1.0, 0.21 + r * math.sin(a))) for x in (-0.09, -0.06, 0.06, 0.09)])
    mguard = loft("mudguard_f", [ [p for p in ring] + [Vector((p.x, p.y, p.z - 0.012)) for p in reversed(ring)] for ring in mg], [M["paint"]])
    smooth(mguard); parts.append(mguard)
    # fork
    for sx in (-0.07, 0.07):
        parts.append(tube("fork", [Vector((sx, 1.0, 0.21)), Vector((sx, 1.08, 0.62))], 0.022, [M["chrome"]]))
    parts.append(lamp("headlamp", (0, 1.30, 0.86), 0.085, 0.07, M, "lamp_head"))
    for sx in (-0.11, 0.11):
        parts.append(rbox("ind_f", (sx, 1.24, 1.0), (0.025, 0.02, 0.018), [M["lamp_ind"]], bevel=0.008))
    # --- tub: floor + sides from the dashboard back to the tail, with the high rear deck
    def tub_ring(y, w, z0, z1):
        return [Vector(p) for p in [(-w, y, z0), (-w * 0.98, y, z0 + (z1 - z0) * 0.5), (-w, y, z1), (-w * 0.6, y, z1 + 0.012), (w * 0.6, y, z1 + 0.012), (w, y, z1), (w * 0.98, y, z0 + (z1 - z0) * 0.5), (w, y, z0), (w * 0.6, y, z0 - 0.02), (-w * 0.6, y, z0 - 0.02)]]
    tub = loft("tub", [tub_ring(0.5, 0.6, 0.34, 0.64), tub_ring(0.2, 0.62, 0.34, 0.64), tub_ring(0.05, 0.64, 0.34, 0.64), tub_ring(-0.72, 0.65, 0.34, 0.64),
                       tub_ring(-0.8, 0.65, 0.34, 1.13), tub_ring(-1.25, 0.65, 0.34, 1.13), tub_ring(-1.32, 0.62, 0.36, 1.08)], [M["paint"]])
    subsurf(tub, 2); smooth(tub)
    assign(tub, lambda c, n: "trim" if n.z > 0.8 and c.z < 0.7 and c.y > -0.75 else None, M)  # rubber floor mat
    # rear wheel arches
    for sx in (-0.58, 0.58):
        boolean_cut(tub, cylinder_x("arch", (sx, -0.95, 0.21), 0.3, 0.3))
    parts.append(tub)
    # --- seats: driver's saddle and the passenger bench with backrest
    parts.append(rbox("seat_d", (0, 0.3, 0.74), (0.24, 0.17, 0.06), [M["seat"]], 0.04))
    parts.append(rbox("seat_p", (0, -0.42, 0.72), (0.58, 0.22, 0.07), [M["seat"]], 0.05))
    parts.append(rbox("seat_pb", (0, -0.7, 0.95), (0.58, 0.06, 0.2), [M["seat"]], 0.05))
    parts.append(rbox("seat_db", (0, 0.13, 0.86), (0.26, 0.04, 0.09), [M["seat"]], 0.03))  # driver backrest / partition
    # --- windscreen with frame, wiper, rear-view mirror
    ws = rbox("windscreen", (0, 0.6, 1.42), (0.47, 0.012, 0.22), [M["glass"]], 0.0, 1)
    ws.rotation_euler.x = -0.32
    parts.append(ws)
    for sx in (-0.5, 0.5):
        parts.append(tube("ws_post", [Vector((sx, 0.55, 1.15)), Vector((sx * 0.98, 0.68, 1.64))], 0.018, [M["trim"]]))
    parts.append(tube("ws_top", [Vector((-0.5, 0.69, 1.64)), Vector((0.5, 0.69, 1.64))], 0.018, [M["trim"]]))
    parts.append(tube("wiper", [Vector((0.05, 0.53, 1.23)), Vector((0.3, 0.6, 1.5))], 0.006, [M["trim"]]))
    # --- handlebar with grips and a brake lever, meter box
    hb = [Vector((-0.34, 0.47, 1.12)), Vector((-0.2, 0.52, 1.17)), Vector((0, 0.53, 1.18)), Vector((0.2, 0.52, 1.17)), Vector((0.34, 0.47, 1.12))]
    parts.append(tube("handlebar", hb, 0.014, [M["chrome"]]))
    for sx in (-0.34, 0.34):
        parts.append(tube("grip", [Vector((sx, 0.47, 1.12)), Vector((sx * 1.25, 0.44, 1.1))], 0.02, [M["rubber"]]))
    parts.append(rbox("meter", (-0.24, 0.47, 1.25), (0.07, 0.04, 0.09), [M["trim"]], 0.012))
    # --- canvas roof: curved shell with thickness, rolled side curtains, rear canvas panel
    roof_rings = []
    for k in range(11):
        t = k / 10
        y = 0.72 - t * 2.06
        z = 1.64 + math.sin(t * math.pi) * 0.09 - t * 0.04
        w = 0.62 + 0.06 * math.sin(min(1, t * 1.4) * math.pi / 2)
        top = [Vector((x * w, y, z + 0.05 * (1 - x * x))) for x in [-1, -0.7, -0.35, 0, 0.35, 0.7, 1]]
        roof_rings.append(top + [Vector((p.x * 0.99, p.y, p.z - 0.02)) for p in reversed(top)])
    roof = loft("roof", roof_rings, [M["canvas"]])
    subsurf(roof, 1); smooth(roof); parts.append(roof)
    for sx in (-0.67, 0.67):
        parts.append(tube("curtain", [Vector((sx, 0.6, 1.62)), Vector((sx, -1.3, 1.56))], 0.04, [M["canvas"]], seg=8))
    rear_canvas = loft("rear_canvas", [[Vector((x * 0.66, -1.33, z)) for x, z in [(-1, 1.12), (1, 1.12), (1, 1.56), (-1, 1.56)]],
                                       [Vector((x * 0.66, -1.345, z)) for x, z in [(-1, 1.12), (1, 1.12), (1, 1.56), (-1, 1.56)]]], [M["canvas"]])
    parts.append(rear_canvas)
    parts.append(rbox("rear_window", (0, -1.35, 1.38), (0.3, 0.006, 0.09), [M["glass"]], 0.0, 1))
    # roof frame posts and grab rails
    for sy in (0.02, -0.82):
        for sx in (-0.63, 0.63):
            parts.append(tube("post", [Vector((sx, sy, 0.62 if sy > -0.5 else 1.1)), Vector((sx, sy, 1.62))], 0.016, [M["trim"]]))
    parts.append(tube("grab", [Vector((-0.55, -0.1, 1.42)), Vector((0.55, -0.1, 1.42))], 0.012, [M["chrome"]]))
    # --- rear: tail lamps, number plate (yellow: commercial), slogan board, bumper guard
    for sx in (-0.48, 0.48):
        parts.append(rbox("tail", (sx, -1.33, 0.82), (0.07, 0.02, 0.05), [M["lamp_tail"]], 0.012))
        parts.append(rbox("ind_r", (sx, -1.33, 0.72), (0.035, 0.02, 0.025), [M["lamp_ind"]], 0.008))
    parts.append(rbox("plate_r", (0, -1.335, 0.62), (0.16, 0.006, 0.06), [M["plate_y"]], 0.004, 1))
    parts.append(rbox("slogan", (0, -1.335, 0.98), (0.4, 0.006, 0.08), [M["plate"]], 0.004, 1))
    parts.append(tube("bumper_r", [Vector((-0.6, -1.36, 0.42)), Vector((-0.55, -1.42, 0.42)), Vector((0.55, -1.42, 0.42)), Vector((0.6, -1.36, 0.42))], 0.018, [M["chrome"]]))
    parts.append(rbox("exhaust", (0.45, -1.3, 0.3), (0.035, 0.12, 0.035), [M["metal"]], 0.02))
    body = join(parts, "body")
    wheels = [(0, 1.0, 0.21), (-0.565, -0.95, 0.21), (0.565, -0.95, 0.21)]
    return body, wheels, dict(R=0.21, width=0.11, rim=0.115, style="steel", spokes=4)


# ========================================================================================= HATCHBACK
def build_hatch(variant=0):
    """small hatchback (Alto/Swift class, fictional 'Mithra'): 3.72 × 1.64 × 1.50 m"""
    cols = ["#f2f2f0", "#c8c8c8", "#8a8a8a", "#7a1414", "#1c3a6a", "#2a2a2a", "#d8d0b8", "#b8b8ba", "#5e2a6e"]
    M = std_mats(cols[variant % len(cols)], "#1a1a1a")
    # stations: y, z_bottom, z_belt, z_top, half-width at belt, half-width at top
    S = [(-1.86, 0.36, 0.66, 0.74, 0.62, 0.5), (-1.83, 0.3, 0.88, 1.0, 0.76, 0.66), (-1.74, 0.27, 0.95, 1.3, 0.79, 0.6), (-1.6, 0.25, 0.96, 1.44, 0.8, 0.62),
         (-1.1, 0.24, 0.97, 1.49, 0.81, 0.63), (-0.4, 0.24, 0.97, 1.5, 0.81, 0.64), (0.15, 0.24, 0.96, 1.47, 0.81, 0.63), (0.48, 0.25, 0.94, 1.18, 0.8, 0.69),
         (0.75, 0.26, 0.92, 0.99, 0.79, 0.74), (1.2, 0.28, 0.87, 0.92, 0.78, 0.72), (1.6, 0.3, 0.8, 0.84, 0.76, 0.68), (1.8, 0.34, 0.68, 0.74, 0.7, 0.56), (1.87, 0.4, 0.56, 0.6, 0.58, 0.45)]
    # insert stations exactly on the glass / pillar edges so material boundaries are clean lines
    cuts = [0.74, 0.70, 0.24, 0.2, -0.22, -0.3, -1.05, -1.1, -1.5, -1.64, -1.8]
    def lerp_st(y):
        for a_, b_ in zip(S[:-1], S[1:]):
            if a_[0] <= y <= b_[0]:
                t = (y - a_[0]) / (b_[0] - a_[0])
                return tuple(p + (q - p) * t for p, q in zip(a_, b_))
    S = sorted(S + [lerp_st(y) for y in cuts], key=lambda s: s[0])
    def prof(st):
        y, zb, zbelt, zt, wb, wt = st
        return [(0.0, zb - 0.01), (wb * 0.78, zb), (wb * 0.97, zb + 0.08), (wb, zb + (zbelt - zb) * 0.55), (wb * 0.985, zbelt),
                (wb * 0.95, zbelt + 0.02), (wt + (wb * 0.95 - wt) * 0.4, zbelt + (zt - zbelt) * 0.5), (wt, zt - 0.07), (wt * 0.85, zt - 0.012), (0.0, zt)]
    def region(y, seg, sub, c, n):
        if seg <= 1: return "trim"                                   # underbody, sill
        if seg == 2 and sub == 0 and (y > 1.6 or y < -1.7): return "trim"   # bumper lower lips
        if c.z < 0.42 and y > 1.8: return "trim"
        if seg in (5, 6):
            if not (-1.5 < y < 0.74): return None
            if (seg == 5 and sub == 0) or (seg == 6 and sub == 2): return "trim"  # rubber seals
            if -0.3 < y < -0.22 or -1.1 < y < -1.05: return "trim"      # B pillar, quarter divider
            return "glass"
        if seg == 8 and 0.2 < y < 0.74:
            return "trim" if (y < 0.24 or y > 0.70 or sub == 0) else "glass"      # windscreen + frit
        if seg == 8 and -1.8 < y < -1.64:
            return "trim" if (y < -1.78 or y > -1.66 or sub == 0) else "glass"   # tailgate glass
        return None
    body = param_shell("shell", S, prof, region, M, step_y=0.04, prof_subs=[3, 2, 3, 3, 1, 3, 3, 2, 4])
    for sx in (-0.74, 0.74):
        for sy in (1.22, -1.2):
            boolean_cut(body, cylinder_x("arch", (sx, sy, 0.29), 0.36, 0.5))
    parts = [body]
    for sx in (-1, 1):
        for sy in (1.22, -1.2):
            arc = [Vector((sx * 0.8, sy + 0.37 * math.cos(a), 0.29 + 0.37 * math.sin(a))) for a in [math.pi * (0.02 + 0.96 * k / 16) for k in range(17)]]
            parts.append(tube("arch_lip", arc, 0.018, [M["trim"]], seg=6))
    # inner arch liners (black) so you can't see into the shell
    for sx in (-0.62, 0.62):
        for sy in (1.22, -1.2):
            parts.append(lathe("liner", [(-0.12, 0.35), (0.12, 0.35)], [M["trim"]], seg=24))
            parts[-1].location = (sx, sy, 0.29)
    # headlamps (swept-back clusters), grille, fog lamps, tail lamps, plates, mirrors, handles
    for sx in (-1, 1):
        hl = rbox("headlamp", (sx * 0.5, 1.78, 0.74), (0.2, 0.08, 0.06), [M["lamp_head"]], 0.03)
        hl.rotation_euler.z = sx * 0.35
        parts.append(hl)
        parts.append(rbox("tail", (sx * 0.66, -1.8, 0.92), (0.1, 0.05, 0.12), [M["lamp_tail"]], 0.02))
        parts.append(rbox("mirror", (sx * 0.86, 0.55, 1.02), (0.06, 0.04, 0.05), [M["paint"]], 0.02))
        parts.append(rbox("mirror_arm", (sx * 0.81, 0.58, 1.0), (0.03, 0.02, 0.015), [M["trim"]], 0.005))
        for sy in (0.15, -0.65):
            parts.append(rbox("handle", (sx * 0.815, sy, 0.92), (0.01, 0.07, 0.012), [M["trim"]], 0.004))
        parts.append(rbox("ind_side", (sx * 0.82, 1.0, 0.8), (0.006, 0.03, 0.012), [M["lamp_ind"]], 0.003))
    parts.append(rbox("grille", (0, 1.86, 0.6), (0.36, 0.03, 0.06), [M["trim"]], 0.02))
    parts.append(rbox("grille_low", (0, 1.83, 0.42), (0.42, 0.03, 0.05), [M["trim"]], 0.02))
    parts.append(rbox("plate_f", (0, 1.88, 0.5), (0.25, 0.01, 0.055), [M["plate"]], 0.005))
    parts.append(rbox("plate_r", (0, -1.86, 0.62), (0.25, 0.01, 0.055), [M["plate"]], 0.005))
    parts.append(rbox("wiper_f", (0.12, 0.62, 1.02), (0.28, 0.008, 0.008), [M["trim"]], 0.003))
    parts.append(rbox("wiper_r", (0, -1.78, 1.18), (0.18, 0.008, 0.008), [M["trim"]], 0.003))
    parts.append(rbox("antenna", (0.2, -1.2, 1.55), (0.006, 0.006, 0.12), [M["trim"]], 0.0))
    # interior silhouette visible through glass: seats, dash, steering wheel
    parts.append(rbox("dash", (0, 0.45, 0.9), (0.72, 0.18, 0.08), [M["interior"]], 0.04))
    for sx in (-0.38, 0.38):
        parts.append(rbox("seat_f", (sx, -0.15, 0.62), (0.24, 0.24, 0.06), [M["interior"]], 0.05))
        parts.append(rbox("seat_fb", (sx, -0.38, 0.92), (0.23, 0.06, 0.28), [M["interior"]], 0.05))
    parts.append(rbox("seat_r", (0, -1.0, 0.62), (0.66, 0.24, 0.06), [M["interior"]], 0.05))
    parts.append(rbox("seat_rb", (0, -1.22, 0.92), (0.66, 0.06, 0.26), [M["interior"]], 0.05))
    sw = lathe("steering", [(-0.015, 0.17), (-0.015, 0.19), (0.015, 0.19), (0.015, 0.17)], [M["trim"]], seg=24)
    sw.rotation_euler = (0, 0, math.pi / 2); sw.location = (-0.38, 0.28, 1.0)
    bpy.ops.object.select_all(action="DESELECT"); sw.select_set(True); bpy.context.view_layer.objects.active = sw
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    sw.rotation_euler.x = -0.5
    parts.append(sw)
    ob = join(parts, "body")
    wheels = [(-0.71, 1.22, 0.29), (0.71, 1.22, 0.29), (-0.71, -1.2, 0.29), (0.71, -1.2, 0.29)]
    return ob, wheels, dict(R=0.29, width=0.165, rim=0.18, style="alloy", spokes=5)


# ======================================================================================= MOTORCYCLE
def build_bike(variant=0):
    """commuter motorcycle (100–125 cc, fictional 'Vikram'): 1.97 × 0.72 × 1.08 m"""
    cols = [("#151515", "#c62828"), ("#8a1010", "#151515"), ("#1a3a8a", "#d0d0d0"), ("#5a5a5a", "#f2b705"), ("#0d0d0d", "#2e7d32")]
    M = std_mats(*cols[variant % len(cols)])
    parts = []
    # fuel tank: lofted teardrop
    def tank_ring(y, w, z0, z1):
        return [Vector((math.cos(t) * w * (1 - 0.25 * max(0, math.sin(t)) ** 2), y, (z0 + z1) / 2 + math.sin(t) * (z1 - z0) / 2)) for t in [k / 14 * 2 * math.pi for k in range(14)]]
    tank = loft("tank", [tank_ring(0.42, 0.06, 0.86, 0.94), tank_ring(0.36, 0.14, 0.8, 1.02), tank_ring(0.2, 0.17, 0.79, 1.05), tank_ring(0.02, 0.15, 0.8, 1.02), tank_ring(-0.1, 0.1, 0.82, 0.96), tank_ring(-0.14, 0.05, 0.85, 0.92)], [M["paint"]])
    subsurf(tank, 2); smooth(tank)
    parts.append(tank)
    parts.append(lathe("tank_cap", [(0.0, 0.035), (0.012, 0.035), (0.014, 0.0)], [M["chrome"]], seg=16))
    parts[-1].rotation_euler = (0, -math.pi / 2, 0); parts[-1].location = (0, 0.24, 1.05)
    # seat: long dual seat with a grab rail
    seat = loft("seat", [[Vector((x * w, y, z)) for x, z in [(-1, zc - 0.03), (-1, zc + 0.03), (-0.6, zc + 0.06), (0.6, zc + 0.06), (1, zc + 0.03), (1, zc - 0.03)]]
                         for (y, w, zc) in [(-0.1, 0.11, 0.9), (-0.2, 0.14, 0.9), (-0.45, 0.14, 0.89), (-0.68, 0.13, 0.9), (-0.8, 0.1, 0.92)]], [M["seat"]])
    subsurf(seat, 2); smooth(seat); parts.append(seat)
    parts.append(tube("grabrail", [Vector((-0.12, -0.55, 0.88)), Vector((-0.13, -0.82, 0.9)), Vector((0.13, -0.82, 0.9)), Vector((0.12, -0.55, 0.88))], 0.012, [M["chrome"]]))
    # side panels and tail cowl
    for sx in (-1, 1):
        sp = loft("sidepanel", [[Vector((sx * 0.1, y, z)) for z in (0.62, 0.74, 0.84)] + [Vector((sx * 0.13, y, z)) for z in (0.84, 0.74, 0.62)] for y in (-0.05, -0.3)], [M["paint"]])
        parts.append(sp)
    tail = loft("tailcowl", [tank_ring(-0.75, 0.1, 0.78, 0.88), tank_ring(-0.9, 0.07, 0.8, 0.88), tank_ring(-0.98, 0.04, 0.82, 0.86)], [M["paint"]])
    subsurf(tail, 1); smooth(tail); parts.append(tail)
    parts.append(rbox("taillamp", (0, -0.97, 0.84), (0.05, 0.02, 0.025), [M["lamp_tail"]], 0.01))
    parts.append(rbox("plate", (0, -0.98, 0.7), (0.1, 0.005, 0.05), [M["plate"]], 0.004, 1))
    for sx in (-0.13, 0.13):
        parts.append(rbox("ind_r", (sx, -0.92, 0.8), (0.03, 0.015, 0.015), [M["lamp_ind"]], 0.008))
        parts.append(rbox("ind_f", (sx * 1.1, 0.72, 0.92), (0.03, 0.015, 0.015), [M["lamp_ind"]], 0.008))
    # frame: backbone tube, down tube, rear subframe, swing arm, chain guard
    parts.append(tube("frame", [Vector((0, 0.56, 0.98)), Vector((0, 0.3, 0.84)), Vector((0, 0.0, 0.66)), Vector((0, -0.15, 0.58))], 0.03, [M["trim"]]))
    for sx in (-0.09, 0.09):
        parts.append(tube("swingarm", [Vector((sx, -0.1, 0.42)), Vector((sx, -0.62, 0.3))], 0.02, [M["trim"]]))
        parts.append(tube("subframe", [Vector((sx * 0.8, -0.1, 0.62)), Vector((sx, -0.75, 0.82))], 0.015, [M["trim"]]))
        # rear shocks: chromed spring (helix) around a damper
        coil = [Vector((sx + 0.025 * math.cos(t), -0.62 + (-0.05) * (t / 40) + 0.025 * math.sin(t), 0.33 + (t / 40) * 0.42)) for t in [k * 0.5 for k in range(81)]]
        parts.append(tube("spring", coil, 0.004, [M["chrome"]], seg=4))
        parts.append(tube("damper", [Vector((sx, -0.62, 0.32)), Vector((sx, -0.67, 0.78))], 0.012, [M["trim"]]))
    parts.append(rbox("chainguard", (0.1, -0.35, 0.4), (0.012, 0.28, 0.035), [M["trim"]], 0.01))
    # engine: crankcase + finned cylinder + carb, exhaust with heat shield and muffler
    parts.append(rbox("crankcase", (0, 0.0, 0.38), (0.13, 0.17, 0.11), [M["engine"]], 0.05))
    for k in range(7):
        parts.append(rbox("fin", (0, 0.2 + k * 0.004, 0.46 + k * 0.035), (0.085, 0.07, 0.008), [M["engine"]], 0.004))
    parts.append(rbox("head", (0, 0.24, 0.72), (0.07, 0.06, 0.04), [M["engine"]], 0.02))
    parts.append(tube("exhaust", [Vector((0.03, 0.27, 0.48)), Vector((0.08, 0.28, 0.28)), Vector((0.14, 0.1, 0.24)), Vector((0.16, -0.35, 0.3)), Vector((0.17, -0.7, 0.38))], 0.022, [M["chrome"]]))
    parts.append(tube("muffler", [Vector((0.17, -0.3, 0.3)), Vector((0.18, -0.72, 0.39))], 0.042, [M["chrome"]]))
    parts.append(rbox("heatshield", (0.18, -0.4, 0.33), (0.012, 0.12, 0.035), [M["trim"]], 0.008))
    # front: telescopic fork, headlamp nacelle, speedometer, handlebar with mirrors
    for sx in (-0.085, 0.085):
        parts.append(tube("fork_l", [Vector((sx, 0.66, 0.29)), Vector((sx, 0.6, 0.62))], 0.024, [M["rim"]]))
        parts.append(tube("fork_u", [Vector((sx, 0.6, 0.62)), Vector((sx, 0.55, 0.92))], 0.019, [M["chrome"]]))
    nac = loft("nacelle", [tank_ring(0.6, 0.11, 0.86, 1.06), tank_ring(0.7, 0.12, 0.84, 1.07), tank_ring(0.76, 0.1, 0.86, 1.04)], [M["paint"]])
    subsurf(nac, 1); smooth(nac); parts.append(nac)
    parts.append(lamp("headlamp", (0, 0.76, 0.95), 0.07, 0.05, M, "lamp_head"))
    hb = [Vector((-0.34, 0.5, 1.07)), Vector((-0.2, 0.55, 1.05)), Vector((0.2, 0.55, 1.05)), Vector((0.34, 0.5, 1.07))]
    parts.append(tube("handlebar", hb, 0.012, [M["chrome"]]))
    for sx in (-1, 1):
        parts.append(tube("grip", [Vector((sx * 0.34, 0.5, 1.07)), Vector((sx * 0.43, 0.47, 1.08))], 0.017, [M["rubber"]]))
        parts.append(tube("mirror_stalk", [Vector((sx * 0.25, 0.53, 1.06)), Vector((sx * 0.3, 0.5, 1.28))], 0.006, [M["chrome"]]))
        parts.append(rbox("mirror", (sx * 0.3, 0.5, 1.3), (0.05, 0.012, 0.035), [M["trim"]], 0.01))
    parts.append(rbox("speedo", (0, 0.58, 1.1), (0.06, 0.035, 0.04), [M["trim"]], 0.015))
    # mudguards
    for (yc, a0, a1, r, w) in [(0.66, 0.05, 0.62, 0.32, 0.06), (-0.62, 0.42, 0.95, 0.32, 0.075)]:
        ring_pts = []
        for k in range(10):
            a = math.pi * (a0 + (a1 - a0) * k / 9)
            ring_pts.append([Vector((x, yc + r * math.cos(a), 0.29 + r * math.sin(a))) for x in (-w, w)] + [Vector((x, yc + (r - 0.01) * math.cos(a), 0.29 + (r - 0.01) * math.sin(a))) for x in (w, -w)])
        mg = loft("mudguard", ring_pts, [M["paint"] if yc > 0 else M["trim"]]); smooth(mg); parts.append(mg)
    parts.append(tube("stand", [Vector((-0.1, -0.05, 0.3)), Vector((-0.24, 0.05, 0.02))], 0.012, [M["trim"]]))  # side stand (deployed)
    body = join(parts, "body")
    wheels = [(0, 0.66, 0.29), (0, -0.62, 0.29)]
    return body, wheels, dict(R=0.29, width=0.08, rim=0.215, style="alloy", spokes=5)


# =========================================================================================== SCOOTER
def build_scooter(variant=0):
    """scooter (Activa class, fictional 'Sakhi'): 1.76 × 0.71 × 1.15 m"""
    cols = ["#f5f5f5", "#151515", "#8a1010", "#1a3a8a", "#7f8c8d", "#2e7d32", "#5e2a6e"]
    M = std_mats(cols[variant % len(cols)], "#1a1a1a")
    parts = []
    def ring(y, w, z0, z1, flat=0.0):
        return [Vector((math.cos(t) * w, y, (z0 + z1) / 2 + math.sin(t) * (z1 - z0) / 2 * (1 - flat * max(0, -math.sin(t))))) for t in [k / 16 * 2 * math.pi for k in range(16)]]
    # front apron + leg shield (one loft going up from the front wheel to the handlebar)
    apron = loft("apron", [ring(0.62, 0.06, 0.55, 0.62), ring(0.66, 0.2, 0.45, 0.95), ring(0.6, 0.26, 0.38, 1.0), ring(0.5, 0.27, 0.36, 1.0), ring(0.44, 0.24, 0.36, 0.98)], [M["paint"]])
    subsurf(apron, 2); smooth(apron); parts.append(apron)
    # floorboard
    parts.append(rbox("floor", (0, 0.15, 0.3), (0.17, 0.3, 0.03), [M["trim"]], 0.02))
    # rear body (under the seat) and side panels
    rear = loft("rearbody", [ring(-0.1, 0.12, 0.28, 0.66, 0.4), ring(-0.25, 0.18, 0.26, 0.76, 0.4), ring(-0.6, 0.19, 0.3, 0.8, 0.4), ring(-0.8, 0.14, 0.42, 0.8), ring(-0.88, 0.06, 0.55, 0.76)], [M["paint"]])
    subsurf(rear, 2); smooth(rear)
    boolean_cut(rear, cylinder_x("arch", (0, -0.55, 0.26), 0.25, 0.3))
    parts.append(rear)
    seat = loft("seat", [[Vector((x * w, y, z)) for x, z in [(-1, 0.78), (-1, 0.82), (-0.6, 0.86), (0.6, 0.86), (1, 0.82), (1, 0.78)]] for (y, w) in [(-0.08, 0.13), (-0.3, 0.17), (-0.65, 0.16), (-0.82, 0.1)]], [M["seat"]])
    subsurf(seat, 2); smooth(seat); parts.append(seat)
    parts.append(rbox("tail", (0, -0.88, 0.7), (0.06, 0.02, 0.03), [M["lamp_tail"]], 0.012))
    parts.append(rbox("plate", (0, -0.86, 0.55), (0.1, 0.005, 0.05), [M["plate"]], 0.004, 1))
    # handlebar cover with headlamp, mirrors
    hc = loft("handlecover", [ring(0.42, 0.08, 0.98, 1.08), ring(0.5, 0.3, 0.99, 1.1), ring(0.58, 0.12, 0.98, 1.08)], [M["paint"]])
    subsurf(hc, 2); smooth(hc); parts.append(hc)
    parts.append(lamp("headlamp", (0, 0.6, 1.03), 0.055, 0.04, M, "lamp_head"))
    for sx in (-1, 1):
        parts.append(tube("grip", [Vector((sx * 0.3, 0.5, 1.05)), Vector((sx * 0.38, 0.48, 1.05))], 0.017, [M["rubber"]]))
        parts.append(tube("mirror_stalk", [Vector((sx * 0.22, 0.5, 1.08)), Vector((sx * 0.27, 0.47, 1.28))], 0.006, [M["chrome"]]))
        parts.append(rbox("mirror", (sx * 0.27, 0.47, 1.3), (0.05, 0.012, 0.035), [M["trim"]], 0.01))
        parts.append(rbox("ind", (sx * 0.16, 0.68, 0.78), (0.03, 0.012, 0.015), [M["lamp_ind"]], 0.008))
    parts.append(tube("fork", [Vector((0.05, 0.66, 0.26)), Vector((0.05, 0.6, 0.6))], 0.022, [M["trim"]]))
    mg = []
    for k in range(9):
        a = math.pi * (0.1 + 0.6 * k / 8); r = 0.26
        mg.append([Vector((x, 0.66 + r * math.cos(a), 0.26 + r * math.sin(a))) for x in (-0.06, 0.06)] + [Vector((x, 0.66 + (r - 0.01) * math.cos(a), 0.26 + (r - 0.01) * math.sin(a))) for x in (0.06, -0.06)])
    m = loft("mudguard", mg, [M["paint"]]); smooth(m); parts.append(m)
    parts.append(rbox("muffler", (0.15, -0.55, 0.3), (0.05, 0.2, 0.06), [M["metal"]], 0.04))
    body = join(parts, "body")
    wheels = [(0, 0.66, 0.26), (0, -0.55, 0.26)]
    return body, wheels, dict(R=0.26, width=0.09, rim=0.17, style="alloy", spokes=5)


# =============================================================================================== BUS
def build_bus(variant=0):
    """city bus (fictional MNT, MTC-like blue/white): 11.9 × 2.55 × 3.1 m"""
    pal = [("#2a5db0", "#f2f0ea"), ("#2f8a4a", "#f2f0ea"), ("#a52a2a", "#f2c811")][variant % 3]
    M = std_mats(*pal)
    # stations: y, zb, zt, half-width; extra stations on every window-bay edge (clean glass lines)
    S = [(-5.95, 0.42, 2.9, 1.2), (-5.9, 0.38, 3.0, 1.25), (-5.7, 0.36, 3.08, 1.27)]
    bays = []
    y = -5.25
    while y + 1.3 < 5.3:
        bays.append((y + 0.05, y + 1.3)); y += 1.35
    for (y0, y1) in bays: S += [(y0, 0.36, 3.08, 1.27), (y1, 0.36, 3.08, 1.27)]
    S += [(5.6, 0.36, 3.08, 1.27), (5.85, 0.4, 3.0, 1.25), (5.95, 0.45, 2.8, 1.2)]
    S = sorted(S)
    def prof(st):
        y, zb, zt, w = st
        return [(0.0, zb), (w * 0.95, zb), (w, zb + 0.15), (w, 0.9), (w, 1.3), (w, 1.36), (w, 2.5), (w, 2.58), (w * 0.95, zt - 0.03), (0.0, zt)]
    def in_bay(y):
        return any(y0 < y < y1 for (y0, y1) in bays)
    def region(y, seg, sub, c, n):
        if seg == 0: return "trim"
        if seg == 3: return "paint2"                       # white band under the windows
        if seg in (5,):
            door = c.x > 0 and (4.05 < y < 5.15 or -0.25 < y < 0.85)
            if door: return "trim"
            return "glass" if in_bay(y) and sub > 0 else "trim"
        if seg in (6, 7, 8): return "paint2"               # roof and cant rail
        return None
    shell = param_shell("shell", S, prof, region, M, step_y=0.3, prof_subs=[2, 2, 3, 2, 1, 3, 1, 2, 4], cap_mat="paint")
    # front: windscreen (two panes), destination board; rear window
    for sx in (-1, 1):
        parts0 = rbox("ws", (sx * 0.58, 5.965, 1.9), (0.56, 0.008, 0.72), [M["glass"]], 0.0, 1)
        if sx < 0: ws_objs = [parts0]
        else: ws_objs.append(parts0)
    ws_frame = rbox("ws_frame", (0, 5.958, 1.9), (1.19, 0.008, 0.78), [M["trim"]], 0.0, 1)
    for sy in (3.6, -2.4):
        boolean_cut(shell, cylinder_x("arch", (0, sy, 0.5), 0.55, 3.0))
    parts = [shell, ws_frame] + ws_objs
    parts.append(rbox("rear_glass", (0, -5.965, 2.15), (1.0, 0.008, 0.4), [M["glass"]], 0.0, 1))
    # doors (front and middle): dark glazed panels flush with the side (+x is the kerb side)
    for sy in (4.6, 0.3):
        parts.append(rbox("door", (1.272, sy, 1.45), (0.012, 0.55, 1.0), [M["glass"]], 0.0, 1))
    parts.append(rbox("dest_board", (0, 5.96, 2.78), (0.8, 0.01, 0.12), [M["lamp_ind"]], 0.0, 1))
    for sx in (-1, 1):
        parts.append(lamp("headlamp", (sx * 0.95, 5.95, 0.85), 0.11, 0.06, M, "lamp_head"))
        parts.append(rbox("tail", (sx * 1.1, -5.95, 0.95), (0.08, 0.03, 0.2), [M["lamp_tail"]], 0.02))
        parts.append(tube("mirror_arm", [Vector((sx * 1.25, 5.7, 2.3)), Vector((sx * 1.45, 6.0, 2.4)), Vector((sx * 1.45, 6.1, 2.1))], 0.02, [M["trim"]]))
        parts.append(rbox("mirror", (sx * 1.45, 6.1, 1.95), (0.04, 0.12, 0.2), [M["trim"]], 0.02))
    parts.append(rbox("bumper_f", (0, 5.98, 0.5), (1.26, 0.06, 0.1), [M["trim"]], 0.03))
    parts.append(rbox("bumper_r", (0, -5.98, 0.5), (1.26, 0.06, 0.1), [M["trim"]], 0.03))
    parts.append(rbox("plate_f", (0, 6.0, 0.72), (0.25, 0.01, 0.07), [M["plate_y"]], 0.004, 1))
    # interior: seats rows and grab rails visible through windows
    for k in range(9):
        y = -4.6 + k * 1.05
        for sx in (-0.8, 0.8):
            parts.append(rbox("seat", (sx, y, 0.95), (0.42, 0.2, 0.05), [M["seat"]], 0.03))
            parts.append(rbox("seatb", (sx, y - 0.2, 1.25), (0.42, 0.04, 0.25), [M["seat"]], 0.03))
    for sx in (-0.35, 0.35):
        parts.append(tube("rail", [Vector((sx, -5.4, 2.55)), Vector((sx, 5.2, 2.55))], 0.015, [M["chrome"]]))
    body = join(parts, "body")
    wheels = [(-1.05, 3.6, 0.5), (1.05, 3.6, 0.5), (-1.05, -2.4, 0.5), (1.05, -2.4, 0.5)]
    return body, wheels, dict(R=0.5, width=0.28, rim=0.3, style="alloy", spokes=10)


BUILDERS = {"auto": (build_auto, 3), "hatch": (build_hatch, 4), "bike": (build_bike, 3), "scooter": (build_scooter, 3), "bus": (build_bus, 2)}


def export(vid, variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body, wheels, wd = BUILDERS[vid][0](variant)
    M = MATS
    objs = [body]
    for i, (x, y, z) in enumerate(wheels):
        w = wheel(f"wheel_{i}", wd["R"], wd["width"], wd["rim"], M, wd.get("spokes", 5), wd.get("style", "alloy"))
        if x < 0:  # left wheels: rim face outward
            w.rotation_euler.z = math.pi
            bpy.ops.object.select_all(action="DESELECT"); w.select_set(True); bpy.context.view_layer.objects.active = w
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        w.location = (x, y, z)
        objs.append(w)
    root = bpy.data.objects.new(f"{vid}_{variant}", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs: o.parent = root
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + [root]: o.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{vid}_{variant}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(o.data.polygons) for o in objs)
    print(f"[vehicles] {vid}_{variant}: {tris} faces, {os.path.getsize(path) // 1024} KB")
    # low-detail copy for parked rows / distant traffic (MultiMesh): collapse-decimated
    for o in objs:
        m = o.modifiers.new("dec", "DECIMATE"); m.ratio = 0.22
        apply_mods(o)
    path_lo = os.path.join(OUT, f"{vid}_{variant}_lo.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + [root]: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path_lo, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print(f"[vehicles] {vid}_{variant}_lo: {sum(len(o.data.polygons) for o in objs)} faces")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    for vid, (fn, nvar) in BUILDERS.items():
        if a.only and vid not in a.only.split(","): continue
        for v in range(nvar):
            export(vid, v)
