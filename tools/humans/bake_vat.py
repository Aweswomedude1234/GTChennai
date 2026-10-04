#!/usr/bin/env python3
"""Bake vertex-animation textures (VAT) for the mid-distance crowd tier.

    /path/to/python-with-bpy tools/humans/bake_vat.py [--ratio 0.2] [--clips walk,walk_slow,idle,talk]

For every body variant in godot/assets/humans/bodies.json: import its GLB, merge body + garments +
hair into one mesh (UV2.y encodes the part: 0 skin, 1 top, 2 lower, 3 drape, 4 hair,
5 extra, 6 eyes/teeth), decimate it (default 20% → ~2.5k verts), then play the shared CMU clips
from anims.glb and record every vertex's skinned position and normal per frame.

Output per variant in godot/assets/humans/vat/:
  <id>.glb       static decimated mesh; UV2.x = (vertex index + 0.5) / vertex count
  <id>_pos.png   RGBA8: x = vertex, y = frame row (clips stacked); rgb = offset from rest in ±1 m
  <id>_nrm.png   RGB8: normal * 0.5 + 0.5
and clips.json (row offsets / frame counts / fps), identical for every variant.
"""
import argparse, json, os, sys
import bpy, bmesh
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HUM = os.path.join(ROOT, "godot", "assets", "humans")
OUT = os.path.join(HUM, "vat")
ONLY = []
RANGE = 1.0
MAX_FRAMES = {"idle": 60, "talk": 60, "drink_tea": 60, "argue": 60, "ride_bike": 1, "ride_scooter": 1, "ride_auto": 1, "ride_pass": 1, "ride_pillion": 1}
PART = {"body": 0, "top": 1, "lower": 2, "drape": 3, "hair": 4, "hair_extra": 4, "moustache": 4, "extra": 5, "eyes": 6, "teeth": 6, "shoes": 7}  # brows/lashes cards: too small to matter at range


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def main(ratio, clips):
    specs = json.load(open(os.path.join(HUM, "bodies.json")))
    if ONLY: specs = [s for s in specs if s["id"] in ONLY]
    os.makedirs(OUT, exist_ok=True)
    clip_info = None
    for spec in specs:
        clear()
        new = import_glb(os.path.join(HUM, "anims.glb"))
        actions = {a.name: a for a in bpy.data.actions}
        for o in new: bpy.data.objects.remove(o, do_unlink=True)
        objs = import_glb(os.path.join(HUM, spec["id"] + ".glb"))
        rig = next(o for o in objs if o.type == "ARMATURE")
        meshes = [o for o in objs if o.type == "MESH" and o.name.split(".")[0] in PART]
        # part id into vertex colour, then merge
        for o in meshes:
            pid = PART[o.name.split(".")[0]]
            me = o.data
            # part id kept in a temporary vertex group weight (survives join + decimate)
            g = o.vertex_groups.new(name="_part")
            g.add([v.index for v in me.vertices], (pid + 0.5) / 8.0, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes: o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
        merged = bpy.context.view_layer.objects.active
        merged.name = "crowd"
        # decimate before the armature modifier (vertex groups are interpolated by collapse)
        dec = merged.modifiers.new("dec", "DECIMATE")
        dec.ratio = ratio
        dec.use_collapse_triangulate = True
        while merged.modifiers[0].name != "dec":
            bpy.ops.object.modifier_move_up(modifier="dec")
        bpy.ops.object.modifier_apply(modifier="dec")
        nv = len(merged.data.vertices)
        # index UV for VAT lookup
        uv2 = merged.data.uv_layers.new(name="vat")
        gi = merged.vertex_groups["_part"].index
        part = [0.0] * nv
        for v in merged.data.vertices:
            for gg in v.groups:
                if gg.group == gi: part[v.index] = gg.weight
        for poly in merged.data.polygons:
            pmax = max(part[merged.data.loops[li].vertex_index] for li in poly.loop_indices)
            for li in poly.loop_indices:
                vi = merged.data.loops[li].vertex_index
                uv2.data[li].uv = ((vi + 0.5) / nv, pmax)   # y = part id (whole face, no bleeding)
        # ---- record clips
        rows_p, rows_n, info, row = [], [], {}, 0
        if not rig.animation_data: rig.animation_data_create()
        dg = bpy.context.evaluated_depsgraph_get()
        for cname in clips:
            act = actions.get(cname)
            if act is None: continue
            rig.animation_data.action = act
            if hasattr(rig.animation_data, "action_slot") and act.slots:
                rig.animation_data.action_slot = act.slots[0]
            f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
            f1 = min(f1, f0 + MAX_FRAMES.get(cname, 999) - 1)
            n = f1 - f0 + 1
            for f in range(f0, f1 + 1):
                bpy.context.scene.frame_set(f)
                dg = bpy.context.evaluated_depsgraph_get()
                ev = merged.evaluated_get(dg)
                me = ev.to_mesh()
                co = np.empty(nv * 3, dtype=np.float32); me.vertices.foreach_get("co", co)
                nr = np.empty(nv * 3, dtype=np.float32); me.vertices.foreach_get("normal", nr)
                ev.to_mesh_clear()
                # Blender Z-up → glTF/Godot Y-up: (x, y, z) → (x, z, -y)
                co = co.reshape(nv, 3); nr = nr.reshape(nv, 3)
                rows_p.append(np.stack([co[:, 0], co[:, 2], -co[:, 1]], -1))
                rows_n.append(np.stack([nr[:, 0], nr[:, 2], -nr[:, 1]], -1))
            info[cname] = {"row": row, "frames": n}
            row += n
        clip_info = info
        H = len(rows_p)
        # rest positions (Y-up) → store per-frame offsets in ±RANGE m as RGB8, normals as RGB8
        rest = np.empty(nv * 3, dtype=np.float32); merged.data.vertices.foreach_get("co", rest)
        rest = rest.reshape(nv, 3); rest = np.stack([rest[:, 0], rest[:, 2], -rest[:, 1]], -1)
        P = np.stack(rows_p, 0) - rest[None]
        N = np.stack(rows_n, 0)
        pos8 = np.clip((P / (2 * RANGE) + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
        nrm8 = np.clip((N * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
        from PIL import Image
        Image.fromarray(np.concatenate([pos8, np.full((H, nv, 1), 255, np.uint8)], -1), "RGBA").save(os.path.join(OUT, f"{spec['id']}_pos.png"), optimize=True)
        Image.fromarray(nrm8, "RGB").save(os.path.join(OUT, f"{spec['id']}_nrm.png"), optimize=True)
        # static mesh export (rest pose, no skin): unparent and drop modifiers
        rig.animation_data.action = None
        merged.modifiers.clear()
        merged.parent = None
        for vg in list(merged.vertex_groups): merged.vertex_groups.remove(vg)
        bpy.ops.object.select_all(action="DESELECT")
        merged.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, spec["id"] + ".glb"), export_format="GLB", use_selection=True,
                                  export_skins=False, export_animations=False, export_attributes=True)
        print(f"[vat] {spec['id']}: {nv} verts × {H} frames")
    json.dump({"fps": 30, "clips": clip_info}, open(os.path.join(OUT, "clips.json"), "w"), indent=1)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--ratio", type=float, default=0.1)
    ap.add_argument("--only", default="")
    ap.add_argument("--clips", default="walk,walk_slow,idle,talk,drink_tea,ride_bike,ride_scooter,ride_auto,ride_pass,ride_pillion")
    a = ap.parse_args(argv)
    ONLY = [x for x in a.only.split(",") if x]
    main(a.ratio, a.clips.split(","))
