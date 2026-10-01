#!/usr/bin/env python3
"""Retarget CMU motion capture (BVH, MotionBuilder-friendly naming) onto the MPFB `cmu_mb` rig and
export one animation library GLB (godot/assets/humans/anims.glb) shared by every human.

    /path/to/python-with-bpy tools/humans/build_anims.py [--cmu /path/to/cmu-mocap]

The CMU bone names match MPFB's cmu_mb rig, so retargeting is per bone: each target bone gets the
source bone's world orientation (bone axis follows the mocap exactly), with a per-bone roll
correction measured at rest so limbs don't twist. Root motion is removed for locomotion loops
(the game moves the capsule) and the clip is rotated to face -Y like the MPFB body. Loop points
are found automatically (minimum pose difference over one gait cycle). 120 fps → 30 fps.

CMU data: "The data used in this project was obtained from mocap.cs.cmu.edu. The database was
created with funding from NSF EIA-0196217." Free to use, including in products.
"""
import argparse, math, os, sys
import bpy, addon_utils
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "humans", "anims.glb")
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

# name, file, mode, window seconds (or None = whole clip), pick: "loop" | "calm" | "busy" | (start_s, end_s)
CLIPS = [
    ("walk", "007/07_01", "loop", (0.8, 1.4), "loop"),
    ("walk_slow", "007/07_04", "loop", (1.0, 1.8), "loop"),
    ("walk_brisk", "007/07_12", "loop", (0.7, 1.2), "loop"),
    ("walk_alt", "002/02_01", "loop", (0.8, 1.4), "loop"),
    ("run", "009/09_01", "loop", (0.5, 0.9), "loop"),
    ("jog", "002/02_03", "loop", (0.55, 1.0), "loop"),
    ("idle", "018/18_08", "once", 4.0, "calm"),
    ("idle_alt", "013/13_09", "once", 4.0, "calm"),
    ("talk", "018/18_08", "once", 6.0, "busy"),
    ("argue", "018/18_10", "once", 5.0, "busy"),
    ("drink_tea", "013/13_09", "once", 5.0, "busy"),
    ("traffic_police", "013/13_26", "once", 8.0, "busy"),
    ("sit", "013/13_01", "once", 3.0, "calm_low"),
    ("squat", "013/13_29", "once", 3.0, "lowest"),
    ("punch", "002/02_05", "once", 2.5, "busy"),
    ("reach", "015/15_06", "once", 3.0, "busy"),
]
FPS_SRC = 120
STEP = 4  # → 30 fps


def clear():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)


def import_bvh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, frame_start=0, use_fps_scale=False, update_scene_fps=False,
                            update_scene_duration=False, rotate_mode="NATIVE", axis_forward="-Z", axis_up="Y")
    ob = next(o for o in bpy.data.objects if o not in before)
    act = ob.animation_data.action
    n = int(act.frame_range[1]) + 1
    return ob, n


def world_rots(src, frame):
    """world rotation (3x3) and position of every source bone at `frame`"""
    bpy.context.scene.frame_set(frame)
    out = {}
    mw = src.matrix_world
    for pb in src.pose.bones:
        m = mw @ pb.matrix
        out[pb.name] = (m.to_3x3().normalized(), m.translation.copy())
    return out


def pose_diff(a, b, names):
    d = 0.0
    for n in names:
        q1 = a[n][0].to_quaternion(); q2 = b[n][0].to_quaternion()
        d += 1.0 - abs(q1.dot(q2))
    return d


def main(cmu):
    # reference target human (all humans share bone names / hierarchy)
    clear()
    macro = TargetService.get_default_macro_info_dict()
    macro.update({"gender": 1.0, "age": 0.5})
    body = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
    rig = HumanService.add_builtin_rig(body, "cmu_mb") or next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.name = "rig"
    T = rig
    tb = T.data.bones
    T_rest = {b.name: (T.matrix_world @ b.matrix_local) for b in tb}
    t_hips_h = T_rest["Hips"].translation.z
    order = [b.name for b in tb]  # parents before children
    for name, file, mode, window, pick in CLIPS:
        path = os.path.join(cmu, "data", file + ".bvh")
        if not os.path.exists(path):
            print("missing", path); continue
        S, n = import_bvh(path)
        sb = S.data.bones
        S_rest = {b.name: (S.matrix_world @ b.matrix_local) for b in sb}
        frames = list(range(0, n, STEP))
        poses = [world_rots(S, f) for f in frames]
        names = [b for b in order if b in poses[0]]
        # ---- choose the frame window
        fps = FPS_SRC / STEP
        if pick == "loop":
            lo, hi = int(window[0] * fps), int(window[1] * fps)
            best = (1e9, 0, lo)
            for s in range(int(len(poses) * 0.15), max(int(len(poses) * 0.6), int(len(poses) * 0.15) + 1)):
                for L in range(lo, hi + 1):
                    if s + L >= len(poses): break
                    d = pose_diff(poses[s], poses[s + L], ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Spine"])
                    if d < best[0]: best = (d, s, L)
            s0, s1 = best[1], best[1] + best[2]
        else:
            L = min(len(poses) - 1, int(window * fps))
            energy = []
            for i in range(1, len(poses)):
                energy.append(pose_diff(poses[i - 1], poses[i], names))
            hips = [p["Hips"][1].z for p in poses]
            best_s, best_v = 0, None
            for s in range(min(int(0.7 * fps), max(0, len(poses) - L - 2)), max(1, len(poses) - L - 1), 3):
                e = sum(energy[s:s + L])
                h = sum(hips[s:s + L]) / L
                if pick == "calm": v = e + abs(h - max(hips)) * 0.2
                elif pick == "busy": v = -e
                elif pick == "calm_low": v = e + h * 0.05
                else: v = h
                if best_v is None or v < best_v: best_s, best_v = s, v
            s0, s1 = best_s, best_s + L
        win = poses[s0:s1 + 1]
        # ---- scale, facing and root motion
        s_hips_h = S_rest["Hips"].translation.z if S_rest["Hips"].translation.z > 0.1 else sum(p["Hips"][1].z for p in win) / len(win)
        k = t_hips_h / max(1e-4, sum(p["Hips"][1].z for p in poses[:10]) / 10.0) if pick != "lowest" and pick != "calm_low" else t_hips_h / max(1e-4, max(p["Hips"][1].z for p in poses))
        p0 = win[0]
        left = (p0["LeftUpLeg"][1] - p0["RightUpLeg"][1]); left.z = 0
        if mode == "loop":
            mv = win[-1]["Hips"][1] - win[0]["Hips"][1]; mv.z = 0
            facing = mv.normalized() if mv.length > 0.05 else left.normalized().cross(Vector((0, 0, 1)))
        else:
            facing = left.normalized().cross(Vector((0, 0, 1)))
        yaw = math.atan2(facing.x, -facing.y)  # angle that maps facing → (0,-1)
        Rfix = Matrix.Rotation(-yaw, 3, "Z")
        # ---- roll corrections C[b] = S_rest_rot^-1 @ (q_align @ T_rest_rot)
        C = {}
        for b in names:
            if b not in T_rest: continue
            sr = S_rest[b].to_3x3().normalized(); tr = T_rest[b].to_3x3().normalized()
            ys = sr.col[1]; yt = tr.col[1]
            q = yt.rotation_difference(ys).to_matrix()
            C[b] = sr.inverted() @ (q @ tr)
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        if not T.animation_data: T.animation_data_create()
        T.animation_data.action = act
        for pb in T.pose.bones: pb.rotation_mode = "QUATERNION"
        base0 = win[0]["Hips"][1].copy()
        for fi, P in enumerate(win):
            frame = fi + 1
            world = {}
            for b in order:
                if b not in C:
                    continue
                world[b] = (Rfix @ P[b][0]) @ C[b]
            for b in order:
                if b not in world: continue
                bone = tb[b]
                pb = T.pose.bones[b]
                tr = T_rest[b].to_3x3().normalized()
                if bone.parent and bone.parent.name in world:
                    prr = T_rest[bone.parent.name].to_3x3().normalized()
                    rest_rel = prr.inverted() @ tr
                    local = rest_rel.inverted() @ world[bone.parent.name].inverted() @ world[b]
                else:
                    local = tr.inverted() @ world[b]
                pb.rotation_quaternion = local.to_quaternion()
                pb.keyframe_insert("rotation_quaternion", frame=frame)
            # hips translation (in-place for loops; vertical bob kept)
            hp = P["Hips"][1]
            rel = Rfix @ ((hp - base0) * k)
            if mode == "loop":
                rel.x = 0; rel.y = 0
            target = Vector((0, 0, (hp.z * k))) + Vector((rel.x, rel.y, 0))
            off = target - T_rest["Hips"].translation
            off.x += 0  # keep
            pbh = T.pose.bones["Hips"]
            pbh.location = T_rest["Hips"].to_3x3().normalized().inverted() @ off
            pbh.keyframe_insert("location", frame=frame)
        # make loops seamless: copy first key to the end
        print(f"[anims] {name}: {file} frames {s0 * STEP}-{s1 * STEP} ({len(win)} keys @30fps), scale {k:.3f}")
        src_act = S.animation_data.action if S.animation_data else None
        bpy.data.objects.remove(S, do_unlink=True)
        if src_act: bpy.data.actions.remove(src_act)
    T.animation_data.action = None
    # export: armature + body (Godot needs a skin to build the skeleton) with all actions
    bpy.context.scene.render.fps = 30
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    T.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_skins=True)
    print("[anims] wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--cmu", default="/home/claude/cmu")
    main(ap.parse_args(argv).cmu)
