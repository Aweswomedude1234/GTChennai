#!/usr/bin/env python3
"""Plot infill for city regions.

OpenStreetMap maps only part of Chennai's buildings: in Mylapore whole street frontages are
missing, which turns dense streets into empty lots. This tool fills the gaps the way Chennai
streets are actually built: narrow plots (3.5–12 m wide) shoulder to shoulder along every road,
deeper on main roads, shop houses on busy roads, agraharam row houses near the temple, and a
second pass of back-plots inside large blocks. OSM buildings are kept untouched; generated
buildings carry "g": 1 and are rebuilt on every run (idempotent).

Excluded: water, parks, playgrounds, temple/church compounds, cemeteries, the beach strip,
road corridors (+ footpaths) and existing buildings.

Usage: python3 tools/osm/infill.py [region_id]   (default: every region in data/regions.json)
"""
import json, math, os, sys
from shapely.geometry import Polygon, LineString, Point, box
from shapely.geometry.polygon import orient
from shapely.strtree import STRtree
from shapely.ops import unary_union

PACKS = "godot/packs"
M32 = 0xFFFFFFFF


def mulberry(seed):
    a = seed & M32
    def nxt():
        nonlocal a
        a = (a + 0x6D2B79F5) & M32
        t = ((a ^ (a >> 15)) * (1 | a)) & M32
        t = (((t + (((t ^ (t >> 7)) * (61 | t)) & M32)) & M32) ^ t)
        return ((t ^ (t >> 14)) & M32) / 4294967296.0
    return nxt


def pick_w(r, ws):
    t = r() * sum(ws)
    for i, w in enumerate(ws):
        t -= w
        if t <= 0: return i
    return len(ws) - 1


def h32(*vals):
    h = 2166136261
    for v in vals:
        h ^= int(v) & M32
        h = (h * 16777619) & M32
    return h


LEVELS = {  # G+n distributions (STYLE_BIBLE §2), as (base, weights)
    "agraharam": (1, [45, 45, 10]), "oldhouse": (1, [30, 50, 20]), "informal": (1, [70, 30]),
    "residential": (1, [8, 32, 34, 18, 8]), "commercial": (1, [6, 26, 34, 22, 12]),
    "apartment": (3, [15, 35, 25, 15, 10]),
}
EXCL_AREAS = {"water", "tank", "canal", "park", "ground", "religious", "cemetery", "beach", "parking"}


def run(region):
    rdir = f"{PACKS}/{region['city']}/regions/{region['id']}"
    meta = json.load(open(f"{rdir}/meta.json"))
    cs = meta["chunkSize"]; x0, z0, x1, z1 = meta["bounds"]
    roads = meta["roads"]
    # ---------- obstacles
    chunks = {}
    osm = []
    for k in meta["chunks"]:
        d = json.load(open(f"{rdir}/chunks/{k}.json"))
        d["b"] = [b for b in d["b"] if not b.get("g")]
        chunks[k] = d
        for b in d["b"]:
            f = b["f"]
            try:
                p = Polygon([(f[i], f[i + 1]) for i in range(0, len(f), 2)])
                if p.is_valid: osm.append(p.buffer(0.25))
            except Exception: pass
    corridors = []
    for r in roads:
        P = r["pts"]
        if len(P) < 4: continue
        foot = 2.0 if r["rank"] >= 3 else 0.6
        if r["rank"] == 0 and r["cls"] != "pedestrian": foot = 0.0
        ls = LineString([(P[i], P[i + 1]) for i in range(0, len(P), 2)])
        corridors.append(ls.buffer(r["w"] / 2 + foot + 0.4, cap_style=2))
    excl = []
    for a in meta["areas"]:
        if a["k"] in EXCL_AREAS:
            P = a["pts"]
            try:
                p = Polygon([(P[i], P[i + 1]) for i in range(0, len(P), 2)])
                if not p.is_valid: p = p.buffer(0)
                excl.append(p.buffer(1.0))
            except Exception: pass
    for rl in meta.get("rails", []):
        P = rl["pts"]
        excl.append(LineString([(P[i], P[i + 1]) for i in range(0, len(P), 2)]).buffer(6.0 if rl.get("elevated") else 5.0))
    # clean the coastline: drop the vertical bbox-closing stubs and order by z (Marina runs N–S)
    coast = meta["coast"]
    cp = [(coast[i], coast[i + 1]) for i in range(0, len(coast), 2)]
    while len(cp) > 2 and abs(cp[0][0] - cp[1][0]) < 1.0 and abs(cp[0][1] - cp[1][1]) > 200: cp.pop(0)
    while len(cp) > 2 and abs(cp[-1][0] - cp[-2][0]) < 1.0 and abs(cp[-1][1] - cp[-2][1]) > 200: cp.pop()
    cp.sort(key=lambda p: p[1])
    coast = [round(v, 1) for p in cp for v in p]
    meta["coast"] = coast
    # classify water: compact temple tanks (stepped kulam) vs canals/ponds
    for a in meta["areas"]:
        if a["k"] not in ("water", "tank", "canal"): continue
        P = a["pts"]
        p = Polygon([(P[i], P[i + 1]) for i in range(0, len(P), 2)]).buffer(0)
        rect = p.minimum_rotated_rectangle
        compact = p.area / max(rect.area, 1.0)
        nm = (a.get("name") or "").lower()
        is_tank = ("kulam" in nm or "tank" in nm or "theertham" in nm) or (compact > 0.8 and p.area < 40000)
        a["k"] = "tank" if is_tank else "canal"
    if len(coast) >= 4:
        cpts = [(coast[i], coast[i + 1]) for i in range(0, len(coast), 2)]
        # everything east of (coastline - 75 m) is beach/sea
        shore = [(x - 75, z) for x, z in cpts]
        excl.append(Polygon(shore + [(x1 + 5000, cpts[-1][1]), (x1 + 5000, cpts[0][1])]).buffer(0))
    # ---------- temple compounds: reclassify inner OSM buildings as mandapams, place gopurams/vimanas
    structures = []
    for a in meta["areas"]:
        if a["k"] != "religious": continue
        P = a["pts"]
        poly = Polygon([(P[i], P[i + 1]) for i in range(0, len(P), 2)]).buffer(0)
        if poly.is_empty or poly.area < 400: continue
        lms = [l for l in meta["landmarks"] if poly.buffer(15).contains(Point(l["c"][0], l["c"][1]))]
        faith = lms[0]["k"] if lms else ""
        a["faith"] = faith
        if faith and faith != "hindu": continue
        if not faith and not any(w in (a.get("name") or "").lower() for w in ("temple", "koil", "kovil")): continue
        a["faith"] = "hindu"
        for d in chunks.values():
            for b in d["b"]:
                f = b["f"]
                c = Point(sum(f[0::2]) / (len(f) / 2), sum(f[1::2]) / (len(f) / 2))
                if poly.contains(c) and not b.get("g"):
                    b["k"] = "mandapam"; b["l"] = 1
        # main gopuram on the edge facing east (Hindu temples face east), smaller one opposite
        ring = list(poly.exterior.coords)[:-1]
        if poly.exterior.is_ccw is False: ring = ring[::-1]
        edges = []
        for i in range(len(ring)):
            (ax, az), (bx, bz) = ring[i], ring[(i + 1) % len(ring)]
            L = math.hypot(bx - ax, bz - az)
            if L < 8: continue
            nx, nz = (bz - az) / L, -(bx - ax) / L   # outward for CCW (positive area) rings
            edges.append(((ax + bx) / 2, (az + bz) / 2, nx, nz, L))
        if not edges: continue
        big = poly.area > 5000
        east = max(edges, key=lambda e: e[2])
        west = min(edges, key=lambda e: e[2])
        tiers = 7 if poly.area > 7000 else (5 if big else 3)
        def gop(e, tiers, h):
            w = min(e[4] * 0.38, 6 + tiers * 3.6)
            structures.append({"type": "gopuram", "p": [round(e[0], 1), round(e[1], 1)], "n": [round(e[2], 3), round(e[3], 3)], "w": round(w, 1), "d": round(w * 0.55, 1), "tiers": tiers, "h": h, "name": a.get("name") or ""})
        gop(east, tiers, {7: 37.0, 5: 24.0, 3: 13.0}[tiers])
        if big: gop(west, tiers - 2, {5: 24.0, 3: 13.0}[tiers - 2] if tiers - 2 in (3, 5) else 13.0)
        c = poly.centroid
        structures.append({"type": "vimana", "p": [round(c.x, 1), round(c.y, 1)], "n": [round(east[2], 3), round(east[3], 3)], "w": 7.0 if big else 4.5, "h": 14.0 if big else 8.0, "name": a.get("name") or ""})
        structures.append({"type": "compound", "pts": [round(v, 1) for xy in ring for v in xy], "h": 4.2 if big else 2.4})
    # drop OSM buildings standing where a gopuram/vimana is generated
    for st in structures:
        if st["type"] not in ("gopuram", "vimana"): continue
        cx, cz = st["p"]; nx, nz = st["n"]; tx, tz = -nz, nx
        hw = st["w"] / 2 + 1.0; hd = st.get("d", st["w"]) / 2 + 1.0
        fp = Polygon([(cx + tx * u + nx * v, cz + tz * u + nz * v) for u, v in ((-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd))])
        for d in chunks.values():
            d["b"] = [b for b in d["b"] if not fp.contains(Point(sum(b["f"][0::2]) / (len(b["f"]) / 2), sum(b["f"][1::2]) / (len(b["f"]) / 2)))]
    meta["structures"] = structures
    print("temple structures", len(structures))

    static = osm + corridors + excl
    tree = STRtree(static)
    placed = []           # generated polygons (for overlap tests among themselves)
    placed_tree_dirty = True
    gen_tree = None
    temple = next((l["c"] for l in meta["landmarks"] if "Kapaleeshwarar" in (l.get("name") or "")), [10.2, -26.6])

    def blocked(poly):
        for i in tree.query(poly, predicate="intersects"):
            return True
        for q in placed_near(poly):
            if q.intersects(poly): return True
        return False

    grid = {}
    def placed_near(poly):
        mx, mz, Mx, Mz = poly.bounds
        out = []
        for gx in range(int(mx // 30) - 1, int(Mx // 30) + 2):
            for gz in range(int(mz // 30) - 1, int(Mz // 30) + 2):
                out.extend(grid.get((gx, gz), []))
        return out

    def add(poly):
        mx, mz, Mx, Mz = poly.bounds
        for gx in range(int(mx // 30), int(Mx // 30) + 1):
            for gz in range(int(mz // 30), int(Mz // 30) + 1):
                grid.setdefault((gx, gz), []).append(poly.buffer(0.15))

    def emit(poly, kind, levels, seed, front_edge_road, front_rank):
        poly = orient(poly, 1.0)  # positive shoelace area = outward normal (dz, -dx)
        pts = list(poly.exterior.coords)[:-1]
        f = [round(v, 2) for p in pts for v in p]
        e, rr = [], []
        n = len(pts)
        for i in range(n):
            (ax, az), (bx, bz) = pts[i], pts[(i + 1) % n]
            L = math.hypot(bx - ax, bz - az)
            nx, nz = (bz - az) / L, -(bx - ax) / L
            hit = 0; ri = -1
            for (r_i, rank, lsx) in front_edge_road:
                mx, mz = (ax + bx) / 2 + nx * 3, (az + bz) / 2 + nz * 3
                if lsx.distance(Point(mx, mz)) < lsx_w[r_i] / 2 + 6.5 and L > 2.5:
                    hit = rank + 1; ri = r_i
                    break
            e.append(hit); rr.append(ri)
        cx = sum(p[0] for p in pts) / n; cz = sum(p[1] for p in pts) / n
        ck = f"{int((cx - x0) // cs)}_{int((cz - z0) // cs)}"
        chunks.setdefault(ck, {"b": []})["b"].append({"f": f, "k": kind, "l": levels, "s": seed, "e": e, "r": rr, "g": 1})
        add(poly)

    lsx_w = {}
    road_ls = {}
    for ri, r in enumerate(roads):
        P = r["pts"]
        if len(P) >= 4:
            road_ls[ri] = LineString([(P[i], P[i + 1]) for i in range(0, len(P), 2)])
            lsx_w[ri] = r["w"]

    def kind_for(r, rank, cx, cz, rnd):
        d_t = math.hypot(cx - temple[0], cz - temple[1])
        if rank >= 4: return "commercial" if rnd() < 0.85 else "residential"
        if rank == 3: return "commercial" if rnd() < (0.75 if d_t < 500 else 0.55) else "residential"
        if d_t < 420 and rnd() < 0.6: return "agraharam" if rnd() < 0.65 else "oldhouse"
        if rnd() < 0.18: return "commercial"
        if rnd() < 0.07: return "informal"
        return "residential"

    count = {"front": 0, "back": 0}
    # ---------- pass 1: frontage plots along every road side (bigger roads first)
    order = sorted(range(len(roads)), key=lambda i: -roads[i]["rank"])
    for ri in order:
        r = roads[ri]
        if r["rank"] < 1 or ri not in road_ls: continue
        P = r["pts"]
        foot = 2.0 if r["rank"] >= 3 else 0.6
        for side in (-1, 1):
            rnd = mulberry(h32(r["id"], side + 7))
            for si in range(0, len(P) // 2 - 1):
                ax, az, bx, bz = P[si * 2], P[si * 2 + 1], P[si * 2 + 2], P[si * 2 + 3]
                L = math.hypot(bx - ax, bz - az)
                if L < 4: continue
                tx, tz = (bx - ax) / L, (bz - az) / L
                nx, nz = -tz * side, tx * side   # toward this side
                s = 1.5
                while s < L - 3.0:
                    rank = r["rank"]
                    comm_road = rank >= 3
                    w = (3.5 + rnd() * 4.5) if comm_road and rnd() < 0.7 else (5.0 + rnd() * 7.0)
                    if rank <= 1: w = 4.5 + rnd() * 6
                    w = min(w, L - s - 0.5)
                    if w < 3.2: break
                    setback = (0.1 + rnd() * 0.6) if comm_road else (0.4 + rnd() * 3.5 if rnd() < 0.7 else 0.2)
                    depth = (12 + rnd() * 12) if rank >= 4 else (9 + rnd() * 10)
                    off = r["w"] / 2 + foot + 0.45 + setback
                    made = False
                    for d in (depth, depth * 0.7, max(6.0, depth * 0.45)):
                        p0 = (ax + tx * s + nx * off, az + tz * s + nz * off)
                        p1 = (ax + tx * (s + w) + nx * off, az + tz * (s + w) + nz * off)
                        p2 = (p1[0] + nx * d, p1[1] + nz * d)
                        p3 = (p0[0] + nx * d, p0[1] + nz * d)
                        poly = Polygon([p0, p1, p2, p3])
                        if not blocked(poly):
                            cx, cz = poly.centroid.x, poly.centroid.y
                            kind = kind_for(r, rank, cx, cz, rnd)
                            if kind in ("agraharam", "oldhouse") and w > 9: kind = "residential"
                            if w * d > 550 and rnd() < 0.5: kind = "apartment"
                            base, wts = LEVELS[kind]
                            lv = base + pick_w(rnd, wts)
                            emit(poly, kind, lv, h32(r["id"], si, int(s * 10), side), [(ri, rank, road_ls[ri])], rank)
                            count["front"] += 1
                            made = True
                            break
                    s += w + (0.0 if made and rnd() < 0.85 else (0.3 + rnd() * 1.2 if made else 1.0))
    road_ids = list(road_ls.keys())
    road_tree = STRtree([road_ls[i] for i in road_ids])
    # ---------- pass 2: back plots inside large blocks (houses reached by unmapped lanes)
    step = 9.0
    rnd = mulberry(99)
    gx = x0
    while gx < x1:
        gz = z0
        while gz < z1:
            cx, cz = gx + (rnd() - 0.5) * 4, gz + (rnd() - 0.5) * 4
            pt = Point(cx, cz)
            cands = [road_ids[i] for i in road_tree.query(pt.buffer(90)) if roads[road_ids[i]]["rank"] >= 1]
            if cands:
                ri = min(cands, key=lambda i: road_ls[i].distance(pt))
                ls = road_ls[ri]
                pr = ls.project(pt); q = ls.interpolate(pr); q2 = ls.interpolate(min(ls.length, pr + 1.0))
                ang = math.atan2(q2.y - q.y, q2.x - q.x)
                if ls.distance(pt) > 14:
                    c, s_ = math.cos(ang), math.sin(ang)
                    poly = None
                    for scale in (1.0, 0.75, 0.55):
                        w = (6 + rnd() * 7) * scale; d = (8 + rnd() * 8) * scale
                        corners = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
                        cand = Polygon([(cx + u * c - v * s_, cz + u * s_ + v * c) for u, v in corners])
                        if w * d > 30 and not blocked(cand): poly = cand; break
                    if poly is not None:
                        kind = "residential" if rnd() > 0.1 else "informal"
                        if math.hypot(cx - temple[0], cz - temple[1]) < 420 and rnd() < 0.4: kind = "oldhouse"
                        base, wts = LEVELS[kind]
                        emit(poly, kind, base + pick_w(rnd, wts), h32(int(cx * 10), int(cz * 10), 3), [], 0)
                        count["back"] += 1
            gz += step
        gx += step
    # ---------- write
    for k, d in chunks.items():
        json.dump(d, open(f"{rdir}/chunks/{k}.json", "w"), separators=(",", ":"))
    meta["chunks"] = sorted(chunks.keys())
    meta["infill"] = count
    json.dump(meta, open(f"{rdir}/meta.json", "w"), separators=(",", ":"))
    total = sum(len(d["b"]) for d in chunks.values())
    print(region["id"], count, "total buildings", total)


if __name__ == "__main__":
    regions = json.load(open("data/regions.json"))
    want = sys.argv[1:] or [r["id"] for r in regions]
    for r in regions:
        if r["id"] in want: run(r)
