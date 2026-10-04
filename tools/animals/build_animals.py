#!/usr/bin/env python3
"""Street animals for GTIndian, built procedurally in Blender (run with a Python that has `bpy`):

    /path/to/python-with-bpy tools/animals/build_animals.py

  dog  — Indian pariah dog (INDog): lean, deep chest, wedge head, erect ears, sickle tail, 50 cm at
         the shoulder.
  cow  — zebu street cow: hump, dewlap, upswept horns, long face, 1.3 m at the withers.
  goat — small black/brown goat with drooping ears.

Bodies are lofted from cross-sections and subdivided; legs, tail and horns are tapered tubes.
Each vertex carries its body part in UV2.x (0 body, 1–4 legs FL FR BL BR, 5 tail, 6 head/neck,
7 ears) so `animal.gdshader` can animate walking, lying down, head turns and tail wags without a
skeleton (thousands can share one MultiMesh). Leg hip pivots and sizes go to animals.json.

Front faces Blender +Y (→ Godot −Z). Output: godot/assets/animals/<id>.glb + animals.json.
"""
import json, math, os, sys
import bpy, bmesh
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "animals")


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ellipse_ring(y, cx, cz, rx, rz_top, rz_bot, n=12, belly=0.0):
    pts = []
    for k in range(n):
        t = k / n * 2 * math.pi
        s = math.sin(t)
        rz = rz_top if s > 0 else rz_bot
        x = math.cos(t) * rx * (1 - belly * max(0.0, -s) ** 2)
        pts.append(Vector((cx + x, y, cz + s * rz)))
    return pts


def loft(name, rings, cap=True):
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vr[:-1], vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(vr[0][::-1]); bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm)


def tube(name, pts, radii, seg=8):
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        a = t.cross(up).normalized(); b = t.cross(a).normalized()
        r = radii[i]
        rings.append([p + (a * math.cos(k / seg * 2 * math.pi) + b * math.sin(k / seg * 2 * math.pi)) * r for k in range(seg)])
    return loft(name, rings)


def flatten(ob, f):
    """squash a part along Y about its own centre (ears are thin flaps)"""
    vs = ob.data.vertices
    cy = sum(v.co.y for v in vs) / len(vs)
    for v in vs: v.co.y = cy + (v.co.y - cy) * f


def subsurf(ob, levels=1):
    m = ob.modifiers.new("s", "SUBSURF"); m.levels = levels
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="s")


def tag(ob, part, shade=1.0):
    """part id in UV2.x, and a per-vertex shade (dark muzzle, pale belly…) in UV2.y"""
    me = ob.data
    if len(me.uv_layers) == 0: me.uv_layers.new(name="UVMap")
    uv2 = me.uv_layers.new(name="part")
    for li, loop in enumerate(me.loops):
        uv2.data[li].uv = ((part + 0.5) / 8.0, shade)
    for p in me.polygons: p.use_smooth = True


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def legs(spec, parts):
    """four tapered legs with a knee/hock; returns hip pivots"""
    hips = []
    for i, (x, y, top, front) in enumerate(spec["legs"]):
        h = top
        r0, r1 = spec["leg_r"]
        if front:   # front leg: straight with a slight forward carpus
            pts = [Vector((x, y, h)), Vector((x, y + 0.01, h * 0.55)), Vector((x, y + 0.015, h * 0.22)), Vector((x, y + 0.03, 0.03)), Vector((x, y + 0.06, 0.012))]
        else:       # hind leg: thigh back, hock bends backwards
            pts = [Vector((x, y, h)), Vector((x, y - 0.05 * h, h * 0.62)), Vector((x, y - 0.11 * h, h * 0.33)), Vector((x, y - 0.06 * h, 0.04)), Vector((x, y - 0.02 * h, 0.012))]
        rad = [r0 * 2.5, r0 * 1.5, r1 * 1.15, r1, r1 * 0.95]   # thigh/shoulder mass blends into the body
        lg = tube(f"leg{i}", pts, rad, 8)
        tag(lg, 1 + i, 0.92)
        parts.append(lg)
        hips.append([x, h, -y])   # Godot coords (x, z, -y)
    return hips


def build_dog():
    clear()
    parts = []
    # torso: deep chest, tucked waist (pariah dog), from rump (y -0.3) to chest (y +0.27)
    rings = [ellipse_ring(-0.34, 0, 0.47, 0.06, 0.05, 0.07), ellipse_ring(-0.28, 0, 0.47, 0.105, 0.085, 0.11), ellipse_ring(-0.15, 0, 0.47, 0.1, 0.08, 0.09, belly=0.3),
             ellipse_ring(0.02, 0, 0.47, 0.115, 0.09, 0.15), ellipse_ring(0.17, 0, 0.47, 0.125, 0.095, 0.18), ellipse_ring(0.27, 0, 0.49, 0.11, 0.09, 0.16), ellipse_ring(0.33, 0, 0.53, 0.07, 0.07, 0.09)]
    torso = loft("torso", rings); subsurf(torso, 1); tag(torso, 0, 1.0); parts.append(torso)
    # neck + head (wedge muzzle), ears erect
    neck = loft("neck", [ellipse_ring(0.25, 0, 0.53, 0.06, 0.06, 0.07), ellipse_ring(0.33, 0, 0.62, 0.05, 0.05, 0.055), ellipse_ring(0.38, 0, 0.68, 0.05, 0.05, 0.05)])
    subsurf(neck, 1); tag(neck, 6, 1.0); parts.append(neck)
    head = loft("head", [ellipse_ring(0.34, 0, 0.7, 0.045, 0.05, 0.04), ellipse_ring(0.4, 0, 0.71, 0.06, 0.055, 0.05), ellipse_ring(0.46, 0, 0.7, 0.05, 0.045, 0.04),
                         ellipse_ring(0.52, 0, 0.68, 0.032, 0.03, 0.028), ellipse_ring(0.57, 0, 0.665, 0.022, 0.02, 0.02), ellipse_ring(0.585, 0, 0.665, 0.012, 0.012, 0.012)])
    subsurf(head, 1); tag(head, 6, 1.0); parts.append(head)
    nose = tube("nose", [Vector((0, 0.575, 0.672)), Vector((0, 0.592, 0.672))], [0.014, 0.008]); tag(nose, 6, 0.1); parts.append(nose)
    for sx in (-1, 1):
        ear = tube("ear", [Vector((sx * 0.035, 0.38, 0.74)), Vector((sx * 0.05, 0.375, 0.79)), Vector((sx * 0.055, 0.372, 0.815))], [0.022, 0.016, 0.003], 6)
        flatten(ear, 0.4); tag(ear, 7, 0.9); parts.append(ear)
        eye = tube("eye", [Vector((sx * 0.038, 0.47, 0.725)), Vector((sx * 0.041, 0.475, 0.725))], [0.007, 0.004], 6); tag(eye, 6, 0.05); parts.append(eye)
    # sickle tail curling over the back
    tail = tube("tail", [Vector((0, -0.32, 0.5)), Vector((0, -0.38, 0.58)), Vector((0, -0.37, 0.66)), Vector((0, -0.3, 0.7)), Vector((0, -0.24, 0.68))], [0.022, 0.02, 0.018, 0.014, 0.006], 6)
    tag(tail, 5, 1.0); parts.append(tail)
    spec = {"legs": [(-0.055, 0.2, 0.42, True), (0.055, 0.2, 0.42, True), (-0.055, -0.24, 0.44, False), (0.055, -0.24, 0.44, False)], "leg_r": (0.024, 0.014)}
    hips = legs(spec, parts)
    ob = join(parts, "dog")
    return ob, {"hips": hips, "height": 0.5, "length": 0.92, "lie_drop": 0.33, "stride": 0.28}


def build_cow():
    clear()
    parts = []
    # zebu: long body, hump over the withers, deep dewlap, bony hips
    rings = [ellipse_ring(-0.74, 0, 1.08, 0.12, 0.1, 0.16), ellipse_ring(-0.64, 0, 1.08, 0.24, 0.16, 0.3), ellipse_ring(-0.35, 0, 1.03, 0.29, 0.18, 0.38, belly=0.15),
             ellipse_ring(-0.05, 0, 1.0, 0.31, 0.19, 0.42), ellipse_ring(0.25, 0, 1.02, 0.29, 0.21, 0.4), ellipse_ring(0.45, 0, 1.04, 0.25, 0.23, 0.38),
             ellipse_ring(0.6, 0, 1.04, 0.18, 0.18, 0.3), ellipse_ring(0.7, 0, 1.05, 0.1, 0.1, 0.16)]
    torso = loft("torso", rings); subsurf(torso, 1); tag(torso, 0, 1.0); parts.append(torso)
    hump = loft("hump", [ellipse_ring(0.36, 0, 1.24, 0.03, 0.02, 0.02), ellipse_ring(0.42, 0, 1.27, 0.1, 0.1, 0.06), ellipse_ring(0.52, 0, 1.25, 0.09, 0.07, 0.06), ellipse_ring(0.58, 0, 1.18, 0.03, 0.02, 0.02)])
    subsurf(hump, 1); tag(hump, 0, 1.0); parts.append(hump)
    dew = loft("dewlap", [ellipse_ring(0.4, 0, 0.82, 0.02, 0.05, 0.04), ellipse_ring(0.62, 0, 0.82, 0.035, 0.12, 0.1), ellipse_ring(0.78, 0, 0.92, 0.03, 0.08, 0.07), ellipse_ring(0.86, 0, 1.0, 0.02, 0.03, 0.03)])
    subsurf(dew, 1); tag(dew, 6, 0.95); parts.append(dew)
    neck = loft("neck", [ellipse_ring(0.62, 0, 1.08, 0.13, 0.13, 0.17), ellipse_ring(0.8, 0, 1.12, 0.1, 0.1, 0.13), ellipse_ring(0.92, 0, 1.15, 0.085, 0.09, 0.1)])
    subsurf(neck, 1); tag(neck, 6, 1.0); parts.append(neck)
    head = loft("head", [ellipse_ring(0.9, 0, 1.18, 0.08, 0.09, 0.09), ellipse_ring(0.98, 0, 1.13, 0.09, 0.07, 0.09), ellipse_ring(1.08, 0, 1.02, 0.07, 0.05, 0.07),
                         ellipse_ring(1.16, 0, 0.92, 0.065, 0.045, 0.055), ellipse_ring(1.2, 0, 0.87, 0.06, 0.04, 0.045), ellipse_ring(1.215, 0, 0.85, 0.035, 0.025, 0.03)])
    subsurf(head, 1); tag(head, 6, 1.0); parts.append(head)
    muzzle = loft("muzzle", [ellipse_ring(1.17, 0, 0.88, 0.062, 0.043, 0.05), ellipse_ring(1.215, 0, 0.855, 0.05, 0.035, 0.04), ellipse_ring(1.23, 0, 0.85, 0.03, 0.02, 0.025)])
    subsurf(muzzle, 1); tag(muzzle, 6, 0.25); parts.append(muzzle)
    for sx in (-1, 1):
        horn = tube("horn", [Vector((sx * 0.06, 0.95, 1.24)), Vector((sx * 0.13, 0.93, 1.3)), Vector((sx * 0.16, 0.95, 1.4)), Vector((sx * 0.15, 0.98, 1.48))], [0.03, 0.024, 0.016, 0.004], 6)
        tag(horn, 6, 0.3); parts.append(horn)
        ear = tube("ear", [Vector((sx * 0.08, 0.95, 1.16)), Vector((sx * 0.17, 0.94, 1.12)), Vector((sx * 0.23, 0.95, 1.08))], [0.03, 0.035, 0.01], 6)
        flatten(ear, 0.45); tag(ear, 7, 0.95); parts.append(ear)
        eye = tube("eye", [Vector((sx * 0.085, 1.02, 1.12)), Vector((sx * 0.09, 1.03, 1.12))], [0.012, 0.007], 6); tag(eye, 6, 0.05); parts.append(eye)
    tail = tube("tail", [Vector((0, -0.7, 1.15)), Vector((0, -0.76, 1.0)), Vector((0, -0.77, 0.75)), Vector((0, -0.76, 0.55)), Vector((0, -0.75, 0.42))], [0.035, 0.022, 0.016, 0.014, 0.04], 6)
    tag(tail, 5, 0.6); parts.append(tail)
    spec = {"legs": [(-0.13, 0.48, 0.86, True), (0.13, 0.48, 0.86, True), (-0.14, -0.55, 0.92, False), (0.14, -0.55, 0.92, False)], "leg_r": (0.06, 0.032)}
    hips = legs(spec, parts)
    ob = join(parts, "cow")
    return ob, {"hips": hips, "height": 1.32, "length": 2.0, "lie_drop": 0.62, "stride": 0.55}


def build_goat():
    clear()
    parts = []
    rings = [ellipse_ring(-0.3, 0, 0.55, 0.06, 0.05, 0.06), ellipse_ring(-0.24, 0, 0.56, 0.11, 0.08, 0.12), ellipse_ring(-0.05, 0, 0.55, 0.13, 0.09, 0.15, belly=0.1),
             ellipse_ring(0.15, 0, 0.56, 0.12, 0.09, 0.15), ellipse_ring(0.26, 0, 0.58, 0.08, 0.07, 0.1), ellipse_ring(0.3, 0, 0.6, 0.05, 0.04, 0.05)]
    torso = loft("torso", rings); subsurf(torso, 1); tag(torso, 0, 1.0); parts.append(torso)
    neck = loft("neck", [ellipse_ring(0.24, 0, 0.62, 0.05, 0.05, 0.06), ellipse_ring(0.32, 0, 0.72, 0.04, 0.04, 0.045)])
    subsurf(neck, 1); tag(neck, 6, 1.0); parts.append(neck)
    head = loft("head", [ellipse_ring(0.3, 0, 0.78, 0.04, 0.045, 0.04), ellipse_ring(0.36, 0, 0.78, 0.045, 0.04, 0.04), ellipse_ring(0.43, 0, 0.73, 0.03, 0.03, 0.03), ellipse_ring(0.47, 0, 0.7, 0.018, 0.015, 0.016)])
    subsurf(head, 1); tag(head, 6, 1.0); parts.append(head)
    for sx in (-1, 1):
        ear = tube("ear", [Vector((sx * 0.04, 0.33, 0.8)), Vector((sx * 0.08, 0.34, 0.76)), Vector((sx * 0.095, 0.35, 0.7))], [0.015, 0.02, 0.006], 6)
        flatten(ear, 0.4); tag(ear, 7, 0.9); parts.append(ear)
        horn = tube("horn", [Vector((sx * 0.02, 0.32, 0.82)), Vector((sx * 0.03, 0.28, 0.87)), Vector((sx * 0.035, 0.24, 0.88))], [0.01, 0.007, 0.002], 5)
        tag(horn, 6, 0.4); parts.append(horn)
    tail = tube("tail", [Vector((0, -0.3, 0.6)), Vector((0, -0.33, 0.66)), Vector((0, -0.32, 0.7))], [0.015, 0.012, 0.004], 5)
    tag(tail, 5, 1.0); parts.append(tail)
    spec = {"legs": [(-0.05, 0.17, 0.48, True), (0.05, 0.17, 0.48, True), (-0.05, -0.2, 0.5, False), (0.05, -0.2, 0.5, False)], "leg_r": (0.018, 0.011)}
    hips = legs(spec, parts)
    ob = join(parts, "goat")
    return ob, {"hips": hips, "height": 0.62, "length": 0.8, "lie_drop": 0.38, "stride": 0.24}


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    info = {}
    for name, fn in (("dog", build_dog), ("cow", build_cow), ("goat", build_goat)):
        ob, meta = fn()
        export(ob, os.path.join(OUT, name + ".glb"))
        info[name] = meta
        print(f"[animals] {name}: {len(ob.data.vertices)} verts")
    json.dump(info, open(os.path.join(OUT, "animals.json"), "w"), indent=1)
