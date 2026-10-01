#!/usr/bin/env python3
"""Realistic human pipeline (run with Blender as a Python module, `bpy`):

    /path/to/python-with-bpy tools/humans/build_humans.py [--only id,id] [--count N]

Uses MPFB2 (MakeHuman for Blender, CC0 assets) to build South Indian bodies and faces:
macro details (gender, age, muscle, weight, height) plus a randomised set of facial targets
(nose, lips, jaw, cheeks, eyes, brows, ears) so no two faces are alike, rigged with MPFB's
CMU-MotionBuilder skeleton (so CMU mocap retargets by bone name). Clothing is built from MPFB's
helper geometry and the body surface (so it is skinned to the same rig):
  shirt / T-shirt / blouse / kurta (body surface, pushed out), trousers / leggings (tights helper),
  veshti / lungi / saree pleats (skirt helper extended to the ankle), saree pallu and dupatta (draped
  strips), hair cap + bun/plait, towel over the shoulder.
Each variant is exported as godot/assets/humans/<id>.glb with material slots named
skin / eyes / teeth / lashes / hair / top / lower / drape / extra, which the game re-shades
(skin tone, garment colour and pattern) per person at runtime.

Specs live in data/characters/bodies.json (generated on first run, then hand-tunable).
"""
import argparse, json, math, os, random, sys, time
import bpy, bmesh, addon_utils
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "humans")
SPECS = os.path.join(ROOT, "data", "characters", "bodies.json")

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

FACE_TARGETS = {
    "nose": ["nose-flaring-incr", "nose-flaring-decr", "nose-width1-incr", "nose-width2-incr", "nose-width3-incr", "nose-base-down", "nose-base-up",
             "nose-hump-incr", "nose-scale-vert-incr", "nose-scale-vert-decr", "nose-point-width-incr", "nose-nostrils-width-incr", "nose-curve-convex"],
    "mouth": ["mouth-lowerlip-volume-incr", "mouth-upperlip-volume-incr", "mouth-scale-horiz-incr", "mouth-scale-horiz-decr", "mouth-cupidsbow-incr",
              "mouth-lowerlip-height-incr", "mouth-angles-down", "mouth-angles-up", "mouth-trans-forward"],
    "chin": ["chin-width-incr", "chin-width-decr", "chin-prominent-incr", "chin-height-incr", "chin-bones-incr", "chin-bones-decr"],
    "cheek": ["l-cheek-bones-incr", "r-cheek-bones-incr", "l-cheek-volume-incr", "r-cheek-volume-incr", "l-cheek-inner-incr", "r-cheek-inner-incr"],
    "eyes": ["l-eye-height2-incr", "r-eye-height2-incr", "l-eye-scale-incr", "r-eye-scale-incr", "l-eye-bag-incr", "r-eye-bag-incr", "l-eye-trans-out", "r-eye-trans-out"],
    "brows": ["eyebrows-trans-down", "eyebrows-trans-up", "eyebrows-angle-down", "eyebrows-angle-up", "eyebrows-trans-forward"],
    "head": ["head-oval", "head-round", "head-square", "head-fat-incr", "head-fat-decr", "head-age-incr"],
    "forehead": ["forehead-scale-vert-incr", "forehead-trans-forward", "forehead-temple-decr"],
}


# ------------------------------------------------------------------------------------------- specs
def make_specs(n_men=8, n_women=7, n_kids=3):
    """Body/face/clothing specs for crowd variants (STYLE_BIBLE §6 dress shares)."""
    r = random.Random(20261001)
    specs = []
    def race():
        a = r.uniform(0.28, 0.52); c = r.uniform(0.3, 0.5); s = r.uniform(0.08, 0.22)
        t = a + c + s
        return {"african": round(a / t, 3), "caucasian": round(c / t, 3), "asian": round(s / t, 3)}
    for i in range(n_men):
        age = [0.38, 0.45, 0.5, 0.55, 0.62, 0.7, 0.82, 0.9][i % 8]
        dress = r.choices(["shirt_pants", "shirt_veshti", "shirt_lungi", "tshirt_pants"], [45, 22, 18, 15])[0]
        if age > 0.78: dress = r.choice(["shirt_veshti", "shirt_veshti", "shirt_lungi"])
        specs.append({"id": f"man_{i:02d}", "sex": "m", "macro": {"gender": 1.0, "age": age, "muscle": round(r.uniform(0.35, 0.7), 2),
                      "weight": round(r.uniform(0.3, 0.75), 2), "height": round(r.uniform(0.35, 0.6), 2), "proportions": 0.5, "race": race()},
                      "dress": dress, "sleeve": r.choice(["half", "half", "full"]), "hair": "short" if age < 0.85 else r.choice(["short", "bald_sides"]),
                      "towel": dress != "shirt_pants" and r.random() < 0.4, "seed": r.randrange(1 << 30)})
    for i in range(n_women):
        age = [0.4, 0.46, 0.52, 0.58, 0.66, 0.75, 0.88][i % 7]
        dress = r.choices(["saree", "churidar", "nighty"], [60, 32, 8])[0]
        if age > 0.7: dress = "saree"
        specs.append({"id": f"woman_{i:02d}", "sex": "f", "macro": {"gender": 0.0, "age": age, "muscle": round(r.uniform(0.3, 0.55), 2),
                      "weight": round(r.uniform(0.35, 0.8), 2), "height": round(r.uniform(0.3, 0.5), 2), "proportions": 0.5,
                      "cupsize": round(r.uniform(0.4, 0.6), 2), "firmness": 0.5, "race": race()},
                      "dress": dress, "sleeve": "short", "hair": "bun" if r.random() < 0.45 else "plait", "seed": r.randrange(1 << 30)})
    for i in range(n_kids):
        sex = "m" if i % 2 == 0 else "f"
        specs.append({"id": f"child_{i:02d}", "sex": sex, "macro": {"gender": 1.0 if sex == "m" else 0.0, "age": round(r.uniform(0.18, 0.26), 2),
                      "muscle": 0.4, "weight": 0.45, "height": 0.5, "proportions": 0.5, "race": race()},
                      "dress": "uniform_shorts" if sex == "m" else "uniform_skirt", "sleeve": "half", "hair": "short" if sex == "m" else "plait",
                      "seed": r.randrange(1 << 30)})
    return specs


# ------------------------------------------------------------------------------------------ helpers
def clear():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    for a in list(bpy.data.armatures): bpy.data.armatures.remove(a)


def mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf: bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    return m


def group_index(obj, name):
    g = obj.vertex_groups.get(name)
    return g.index if g else -1


def verts_in_group(obj, name, minw=0.5):
    gi = group_index(obj, name)
    if gi < 0: return set()
    out = set()
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == gi and g.weight >= minw: out.add(v.index); break
    return out


def dominant_bone(obj, bones):
    """per-vertex: the deform group with the largest weight among `bones` (or None)"""
    idx = {obj.vertex_groups[b].index: b for b in bones if b in obj.vertex_groups}
    dom = {}
    for v in obj.data.vertices:
        best, bw = None, 0.0
        for g in v.groups:
            if g.group in idx and g.weight > bw: best, bw = idx[g.group], g.weight
        dom[v.index] = best
    return dom


def extract(src, keep, name, offset=0.0, material=None):
    """duplicate `src`, keep only vertex indices in `keep` (faces fully inside), push out along normals"""
    me = src.data.copy()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for vg in src.vertex_groups:
        pass
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    # keep faces with at least half their vertices selected (no pin-holes at region borders)
    keep_faces = {f for f in bm.faces if sum(1 for v in f.verts if v.index in keep) * 2 >= len(f.verts)}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep_faces], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    if offset:
        bm.normal_update()
        for v in bm.verts: v.co += v.normal * offset
    bm.to_mesh(me); bm.free()
    me.materials.clear()
    if material: me.materials.append(material)
    return ob


MPFB_TEX = "/root/.config/blender/5.2/extensions/user_default/mpfb/data/textures/"
_mask_cache = {}

def uv_mask_verts(obj, mask_file, thresh=0.5):
    """vertex indices whose UV falls inside an MPFB region mask (lips, eyelids…)"""
    if mask_file not in _mask_cache:
        img = bpy.data.images.load(MPFB_TEX + mask_file)
        w, h = img.size
        import numpy as np
        px = np.array(img.pixels[:]).reshape(h, w, 4)[..., 0]
        _mask_cache[mask_file] = (px, w, h)
    px, w, h = _mask_cache[mask_file]
    uv = obj.data.uv_layers.active.data
    out = set()
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            u, v = uv[li].uv
            x = min(w - 1, max(0, int(u * w))); y = min(h - 1, max(0, int(v * h)))
            if px[y, x] > thresh: out.add(obj.data.loops[li].vertex_index)
    return out


def parent_to_rig(ob, rig, src):
    # vertex groups are copied with the mesh data only by name: recreate them from the source object
    for vg in src.vertex_groups:
        if vg.name not in ob.vertex_groups: ob.vertex_groups.new(name=vg.name)
    ob.parent = rig
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


# ------------------------------------------------------------------------------------------- build
def build(spec):
    t0 = time.time()
    clear()
    r = random.Random(spec["seed"])
    macro = TargetService.get_default_macro_info_dict()
    for k, v in spec["macro"].items(): macro[k] = v
    body = HumanService.create_human(macro_detail_dict=macro, scale=0.1, mask_helpers=False)
    # facial variation: one or two targets per feature group, modest weights
    for group, names in FACE_TARGETS.items():
        for name in r.sample(names, k=min(len(names), r.choice([1, 1, 2]))):
            path = TargetService.target_full_path(name)
            if path: TargetService.load_target(body, path, weight=round(r.uniform(0.15, 0.6), 2), name=name)
    # broader nose and fuller lips are common in South India; slightly lighter at random so faces vary
    for name, w in (("nose-flaring-incr", r.uniform(0.1, 0.45)), ("mouth-lowerlip-volume-incr", r.uniform(0.0, 0.35))):
        path = TargetService.target_full_path(name)
        if path and not body.data.shape_keys.key_blocks.get(name): TargetService.load_target(body, path, weight=round(w, 2), name=name)
    TargetService.bake_targets(body)
    rig = HumanService.add_builtin_rig(body, "cmu_mb")
    if rig is None:
        rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.name = "rig"

    M = {k: mat(k, c) for k, c in (("skin", (0.45, 0.3, 0.2)), ("eyes", (0.9, 0.9, 0.9)), ("teeth", (0.9, 0.88, 0.8)), ("lashes", (0.02, 0.02, 0.02)),
                                   ("hair", (0.02, 0.015, 0.01)), ("top", (0.8, 0.8, 0.8)), ("lower", (0.2, 0.2, 0.3)), ("drape", (0.7, 0.2, 0.3)), ("extra", (0.9, 0.9, 0.85)))}
    zs = [v.co.z for v in body.data.vertices]
    height = max(zs) - min(zs)
    body_vs = verts_in_group(body, "body", 0.5)
    hips_z = rig.data.bones["Hips"].head_local.z if "Hips" in rig.data.bones else height * 0.53
    # ------------------------------------------------ garments
    dress = spec["dress"]
    upper_bones = ["LowerBack", "Spine", "Spine1", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "Neck", "Hips"]
    sleeve = spec.get("sleeve", "half")
    if sleeve == "full": upper_bones += ["LeftForeArm", "RightForeArm"]
    dom = dominant_bone(body, list(rig.data.bones.keys()))
    neck_z = rig.data.bones["Neck"].head_local.z if "Neck" in rig.data.bones else height * 0.82
    garments = []
    arm = {}
    for side in ("Left", "Right"):
        a0 = rig.data.bones[side + "Arm"].head_local; a1 = rig.data.bones[side + "ForeArm"].head_local; a2 = rig.data.bones[side + "Hand"].head_local
        arm[side] = (a0, a1, a2)
    def arm_t(co, side):
        a0, a1, a2 = arm[side]
        L1 = (a1 - a0).length; L2 = (a2 - a1).length
        d = (co - a0).dot((a1 - a0).normalized())
        if d <= L1: return d / (L1 + L2)
        return (L1 + (co - a1).dot((a2 - a1).normalized())) / (L1 + L2)
    sleeve_t = {"short": 0.22, "half": 0.32, "full": 0.93}.get(sleeve, 0.32)
    def top_keep(hem_z, collar_z, sleeves):
        keep = set()
        for i in body_vs:
            co = body.data.vertices[i].co
            b = dom.get(i) or ""
            if co.z < hem_z or co.z > collar_z: continue
            if b in ("Head", "Neck1", "LeftHand", "RightHand"): continue
            side = "Left" if b.startswith("Left") else ("Right" if b.startswith("Right") else "")
            if side and b.replace(side, "") in ("Arm", "ForeArm"):
                if arm_t(co, side) <= sleeve_t: keep.add(i)
                continue
            if b in ("LeftShoulder", "RightShoulder", "LowerBack", "Spine", "Spine1", "Neck", "Hips", "LHipJoint", "RHipJoint", "LeftUpLeg", "RightUpLeg", ""):
                keep.add(i)
        return keep
    if dress in ("shirt_pants", "shirt_veshti", "shirt_lungi", "tshirt_pants", "uniform_shorts", "uniform_skirt", "churidar", "nighty"):
        hem = hips_z - (0.12 if dress in ("shirt_pants", "tshirt_pants") else 0.18) * (height / 1.75)
        if dress == "churidar": hem = hips_z - 0.42 * (height / 1.75)          # kurta to the knee
        if dress == "nighty": hem = 0.12
        garments.append(extract(body, top_keep(hem, neck_z - 0.02, True), "top", 0.009, M["top"]))
    if dress == "saree":
        blouse_hem = hips_z + 0.16 * (height / 1.75)
        garments.append(extract(body, top_keep(blouse_hem, neck_z - 0.04, True), "top", 0.007, M["top"]))
    # lower garments from helpers
    tights = verts_in_group(body, "helper-tights", 0.5)
    skirt = verts_in_group(body, "helper-skirt", 0.5)
    if dress in ("shirt_pants", "tshirt_pants", "churidar", "uniform_shorts"):
        # trousers only up to the waistband, tucked just under the shirt hem (no poke-through)
        waist = hips_z + 0.06 * (height / 1.75)
        keep = {i for i in tights if body.data.vertices[i].co.z < waist}
        if dress == "uniform_shorts":
            knee_z = rig.data.bones["LeftLeg"].head_local.z if "LeftLeg" in rig.data.bones else height * 0.28
            keep = {i for i in keep if body.data.vertices[i].co.z > knee_z + 0.05}
        garments.append(extract(body, keep, "lower", 0.004, M["lower"]))
    if dress in ("shirt_veshti", "shirt_lungi", "saree", "uniform_skirt"):
        sk = extract(body, {i for i in skirt if body.data.vertices[i].co.z < hips_z + 0.09 * (height / 1.75)}, "lower", 0.012, M["lower"])
        # extend the skirt helper down to the ankle (veshti/lungi/saree are ankle length; skirt to the knee)
        zmin = min(v.co.z for v in sk.data.vertices); zmax = max(v.co.z for v in sk.data.vertices)
        target = 0.07 if dress != "uniform_skirt" else zmin
        for v in sk.data.vertices:
            t = (zmax - v.co.z) / max(zmax - zmin, 1e-4)
            v.co.z = zmax - t * (zmax - target)
            # flare slightly toward the hem so the cloth clears the walking legs
            flare = 1.0 + 0.18 * t * t
            v.co.x *= flare; v.co.y = v.co.y * flare
        garments.append(sk)
        if dress == "saree":
            # pleats bunch at the front + pallu draped from the left hip over the left shoulder down the back
            ls = rig.data.bones["LeftArm"].head_local; rh = rig.data.bones["RightUpLeg"].head_local
            p0 = Vector((ls.x * 0.85, ls.z + 0.02)); p1 = Vector((rh.x * 1.25, hips_z + 0.1 * (height / 1.75)))
            dvec = (p1 - p0).normalized()
            cy = sum(body.data.vertices[i].co.y for i in body_vs if dom.get(i) in ("Spine", "Spine1")) / max(1, sum(1 for i in body_vs if dom.get(i) in ("Spine", "Spine1")))
            band = set()
            for i in body_vs:
                co = body.data.vertices[i].co
                if dom.get(i) in ("Head", "Neck1", "LeftHand", "RightHand", "LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"): continue
                if co.z < hips_z - 0.05 or co.z > ls.z + 0.08: continue
                q = Vector((co.x, co.z)) - p0
                along = q.dot(dvec); perp = abs(q.x * dvec.y - q.y * dvec.x)
                front = co.y < cy
                if front and -0.06 < along < (p1 - p0).length + 0.05 and perp < 0.12: band.add(i)
                elif not front and co.x > 0.02 and co.z > hips_z + 0.02: band.add(i)   # falls down the back on the left
                elif dom.get(i) == "LeftArm" and co.z > ls.z - 0.12: band.add(i)       # over the shoulder
            pallu = extract(body, band, "drape", 0.016, M["drape"])
            garments.append(pallu)
    if dress == "churidar" and r.random() < 0.8:
        garments.append(make_dupatta(rig, height, M["drape"]))
    if spec.get("towel"):
        garments.append(make_towel(rig, height, M["extra"]))
    # ------------------------------------------------ hair
    head_b = rig.data.bones["Head"]
    hz = head_b.head_local.z
    hlen = (head_b.tail_local - head_b.head_local).length
    head_vs = [i for i in body_vs if dom.get(i) in ("Head", "Neck1")]
    lids_m = uv_mask_verts(body, "mpfb_eyelids.jpg") & body_vs
    lid_top = max(body.data.vertices[i].co.z for i in lids_m) if lids_m else hz + hlen * 0.5
    face_y = min(body.data.vertices[i].co.y for i in head_vs)
    back_y = max(body.data.vertices[i].co.y for i in head_vs)
    depth = max(0.05, back_y - face_y)
    fem = spec["sex"] == "f"
    front_line = lid_top + (0.052 if not fem else 0.048)
    nape = lid_top - (0.075 if not fem else 0.09)
    def is_scalp(co):
        f = (co.y - face_y) / depth                       # 0 face … 1 back of head
        thr = front_line + (nape - front_line) * max(0.0, (f - 0.25) / 0.75) ** 1.3
        if abs(co.x) > 0.062 and f < 0.72:                # sideburn line: keep ears and temples clear
            thr = max(thr, lid_top + 0.012 + (0.02 if f < 0.4 else 0.0))
        return co.z > thr
    hair_vs = {i for i in head_vs if is_scalp(body.data.vertices[i].co)}
    if hair_vs and spec.get("hair") != "bald":
        hair = extract(body, hair_vs, "hair", 0.005, M["hair"])
        # volume: thicker on the crown than at the hairline (short men's cut ~1.5 cm, women's ~2.5 cm)
        vol = 0.016 if spec["sex"] == "m" else 0.024
        zs_h = [v.co.z for v in hair.data.vertices]
        z0, z1 = min(zs_h), max(zs_h)
        bmh = bmesh.new(); bmh.from_mesh(hair.data); bmh.normal_update()
        for v in bmh.verts:
            t = (v.co.z - z0) / max(1e-4, z1 - z0)
            v.co += v.normal * vol * (t ** 0.7)
        bmh.to_mesh(hair.data); bmh.free()
        garments.append(hair)
        if spec["sex"] == "f": garments.append(make_bun(rig, height, M["hair"], spec.get("hair", "bun")))
    # ------------------------------------------------ eyebrows and (for most men) a moustache
    lips = uv_mask_verts(body, "mpfb_lips.jpg") & body_vs
    lids = uv_mask_verts(body, "mpfb_eyelids.jpg") & body_vs
    if lips and lids:
        lv = [body.data.vertices[i].co for i in lips]
        lip_top = max(c.z for c in lv); lip_w = max(abs(c.x) for c in lv); lip_y = min(c.y for c in lv)
        dv = [body.data.vertices[i].co for i in lids]
        lid_top = max(c.z for c in dv); lid_y = min(c.y for c in dv); eye_x = max(abs(c.x) for c in dv)
        brow = {i for i in head_vs if lid_top + 0.004 < body.data.vertices[i].co.z < lid_top + 0.016 and 0.008 < abs(body.data.vertices[i].co.x) < eye_x + 0.006 and body.data.vertices[i].co.y < lid_y + 0.012}
        if brow: garments.append(extract(body, brow, "brows", 0.0015 if spec["sex"] == "f" else 0.0025, M["hair"]))
        if spec["sex"] == "m" and float(spec["macro"]["age"]) > 0.3 and r.random() < 0.7:
            stache = {i for i in head_vs if lip_top + 0.001 < body.data.vertices[i].co.z < lip_top + 0.017 and abs(body.data.vertices[i].co.x) < lip_w + 0.008 and body.data.vertices[i].co.y < lip_y + 0.012}
            if stache: garments.append(extract(body, stache, "moustache", 0.003, M["hair"]))
    # ------------------------------------------------ keep eyes, lashes, teeth; drop other helpers from the body
    keep_groups = {"body"}
    keep_helpers = ["helper-l-eye", "helper-r-eye", "helper-l-eyelashes-1", "helper-r-eyelashes-1", "helper-l-eyelashes-2", "helper-r-eyelashes-2", "helper-upper-teeth", "helper-lower-teeth", "helper-tongue"]
    eyes = set().union(*(verts_in_group(body, g, 0.5) for g in keep_helpers[:2]))
    lashes = set().union(*(verts_in_group(body, g, 0.5) for g in keep_helpers[2:6]))
    teeth = set().union(*(verts_in_group(body, g, 0.5) for g in keep_helpers[6:]))
    for name, vs, m in (("eyes", eyes, M["eyes"]), ("lashes", lashes, M["lashes"]), ("teeth", teeth, M["teeth"])):
        if vs: garments.append(extract(body, vs, name, 0.0, m))
    me = body.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in body_vs], context="VERTS")
    bm.to_mesh(me); bm.free()
    me.materials.clear(); me.materials.append(M["skin"])
    body.name = "body"
    for g in garments: parent_to_rig(g, rig, body)
    # strip non-deform groups so the exporter only writes bone weights
    bone_names = set(rig.data.bones.keys())
    for ob in [body] + garments:
        for vg in list(ob.vertex_groups):
            if vg.name not in bone_names: ob.vertex_groups.remove(vg)
        for mod in list(ob.modifiers):
            if mod.type == "MASK": ob.modifiers.remove(mod)
    for ob in [body] + garments:
        print("   ", ob.name, len(ob.data.vertices), [m.name for m in ob.data.materials])
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, spec["id"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_animations=False,
                              export_skins=True, export_morph=False, export_apply=True, export_yup=True)
    print(f"[humans] {spec['id']}: {len(me.vertices)} body verts, {len(garments)} parts, {os.path.getsize(path) / 1e6:.1f} MB, {time.time() - t0:.1f}s")


def _strip(points, widths, name, material, rig, bone_weights):
    """ribbon mesh along `points` with per-point half-width vectors; skinned with fixed bone weights"""
    me = bpy.data.meshes.new(name)
    verts, faces = [], []
    for p, w in zip(points, widths):
        verts += [p - w, p + w]
    for i in range(len(points) - 1):
        a = i * 2
        faces.append((a, a + 1, a + 3, a + 2))
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for i, v in enumerate(me.vertices):
        t = (i // 2) / max(1, len(points) - 1)
        for bone, wfn in bone_weights.items():
            g = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
            w = wfn(t)
            if w > 0: g.add([i], w, "REPLACE")
    mod = ob.modifiers.new("Solidify", "SOLIDIFY"); mod.thickness = 0.004
    return ob


def _bone(rig, name):
    b = rig.data.bones.get(name)
    return (b.head_local.copy(), b.tail_local.copy()) if b else (Vector((0, 0, 1)), Vector((0, 0, 1.1)))


def make_pallu(rig, height, material):
    lh, _ = _bone(rig, "LeftUpLeg"); ls, _ = _bone(rig, "LeftArm"); sp, _ = _bone(rig, "Spine1")
    front = -1.0  # MPFB faces -Y
    pts = [lh + Vector((0.0, front * 0.13, 0.12)), sp + Vector((0.05, front * 0.12, 0.05)), ls + Vector((-0.03, front * 0.07, 0.06)),
           ls + Vector((-0.02, 0.06, 0.06)), sp + Vector((0.08, 0.14, -0.05)), lh + Vector((0.12, 0.16, -0.15))]
    w = [Vector((0.09, 0, 0)), Vector((0.12, 0, 0.03)), Vector((0.08, 0, 0.0)), Vector((0.08, 0, 0.0)), Vector((0.15, 0, 0)), Vector((0.18, 0, 0))]
    return _strip(pts, w, "drape", material, rig, {"Spine1": lambda t: 1.0 - abs(t - 0.5), "LeftShoulder": lambda t: 1.0 - abs(t - 0.5) * 2, "Hips": lambda t: abs(t - 0.5)})


def make_dupatta(rig, height, material):
    ls, _ = _bone(rig, "LeftArm"); rs, _ = _bone(rig, "RightArm"); sp, _ = _bone(rig, "Spine1")
    pts = [ls + Vector((0.02, 0.05, -0.35)), ls + Vector((0.0, 0.02, 0.04)), sp + Vector((0.0, -0.13, 0.02)), rs + Vector((0.0, 0.02, 0.04)), rs + Vector((-0.02, 0.05, -0.35))]
    w = [Vector((0, 0.08, 0)), Vector((0, 0.09, 0)), Vector((0, 0, 0.07)), Vector((0, 0.09, 0)), Vector((0, 0.08, 0))]
    return _strip(pts, w, "drape", material, rig, {"Spine1": lambda t: 0.6, "LeftShoulder": lambda t: max(0, 0.4 - t), "RightShoulder": lambda t: max(0, t - 0.6)})


def make_towel(rig, height, material):
    ls, _ = _bone(rig, "LeftShoulder")
    pts = [ls + Vector((0.08, -0.12, -0.25)), ls + Vector((0.1, -0.06, 0.02)), ls + Vector((0.1, 0.06, 0.02)), ls + Vector((0.08, 0.1, -0.3))]
    w = [Vector((0.06, 0, 0)), Vector((0.07, 0, 0)), Vector((0.07, 0, 0)), Vector((0.06, 0, 0))]
    return _strip(pts, w, "extra", material, rig, {"LeftShoulder": lambda t: 1.0})


def make_bun(rig, height, material, style):
    h, t = _bone(rig, "Head")
    head_top = t
    me = bpy.data.meshes.new("bun")
    bm = bmesh.new()
    if style == "bun":
        c = h.lerp(head_top, 0.55) + Vector((0, 0.1, -0.02))
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.055)
        for v in bm.verts: v.co = v.co * Vector((1.1, 0.8, 0.9)) + c
    else:
        # plait hanging down the back, tied with jasmine at the nape (the jasmine is an "extra" ring)
        c = h.lerp(head_top, 0.3) + Vector((0, 0.09, 0))
        for k in range(7):
            ring = bmesh.ops.create_circle(bm, cap_ends=False, segments=8, radius=0.026 - k * 0.002)
            for v in ring["verts"]: v.co = v.co.copy() + c + Vector((0, 0.01 * k, -0.07 * k))
        bm.verts.ensure_lookup_table()
        for k in range(6):
            for s in range(8):
                a, b = k * 8 + s, k * 8 + (s + 1) % 8
                bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[b + 8], bm.verts[a + 8]))
    bm.to_mesh(me); bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new("hair_extra", me)
    bpy.context.scene.collection.objects.link(ob)
    g = ob.vertex_groups.new(name="Head")
    g.add([v.index for v in me.vertices], 1.0, "REPLACE")
    return ob


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--regen-specs", action="store_true")
    a = ap.parse_args(argv)
    if a.regen_specs or not os.path.exists(SPECS):
        os.makedirs(os.path.dirname(SPECS), exist_ok=True)
        json.dump(make_specs(), open(SPECS, "w"), indent=1)
    specs = json.load(open(SPECS))
    os.makedirs(OUT, exist_ok=True)
    json.dump(specs, open(os.path.join(OUT, "bodies.json"), "w"), indent=1)  # the game reads variants from here
    for s in specs:
        if a.only and s["id"] not in a.only.split(","): continue
        build(s)
