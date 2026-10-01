// Rapier world wrapper: static world colliders (ground trimesh, per-chunk building shells),
// dynamic bodies for vehicles and props, and a fixed-step accumulator.
import RAPIER from '@dimforge/rapier3d-compat';
import type * as THREE from 'three/webgpu';

export { RAPIER };
export const enum Group { World = 0x0001, Vehicle = 0x0002, Character = 0x0004, Prop = 0x0008, Ped = 0x0010 }
/** Rapier interaction groups: membership in high 16 bits, filter in low 16 */
export const groups = (member: number, filter: number) => ((member & 0xffff) << 16) | (filter & 0xffff);

export class Physics {
  world!: RAPIER.World;
  private acc = 0;
  readonly step = 1 / 60;
  private chunkColliders = new Map<string, RAPIER.Collider[]>();
  eventQueue!: RAPIER.EventQueue;
  alpha = 0;

  async init() {
    await RAPIER.init();
    this.world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
    this.world.timestep = this.step;
    this.eventQueue = new RAPIER.EventQueue(true);
    // safety floor far below everything
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(20000, 1, 20000).setTranslation(0, -30, 0));
  }

  /** run fixed steps; `pre` is called before each step (apply forces / controllers) */
  update(dt: number, pre: (h: number) => void, post?: () => void) {
    this.acc += Math.min(dt, 0.1);
    let n = 0;
    while (this.acc >= this.step && n < 4) { pre(this.step); this.world.step(this.eventQueue); post?.(); this.acc -= this.step; n++; }
    if (n === 4) this.acc = 0;
    this.alpha = this.acc / this.step;
  }

  /** static trimesh from a render geometry (ground, footpaths) */
  addStaticMesh(geo: THREE.BufferGeometry, friction = 0.9): RAPIER.Collider {
    const pos = geo.getAttribute('position').array as Float32Array;
    const idx = geo.getIndex()!.array as Uint32Array;
    const desc = RAPIER.ColliderDesc.trimesh(new Float32Array(pos), new Uint32Array(idx)).setFriction(friction)
      .setCollisionGroups(groups(Group.World, 0xffff));
    return this.world.createCollider(desc);
  }

  /** building shells for one chunk: wall quads + roof caps as one trimesh */
  addChunk(key: string, buildings: { f: number[]; h: number }[]) {
    if (this.chunkColliders.has(key) || !buildings.length) return;
    const v: number[] = [], ix: number[] = [];
    for (const b of buildings) {
      const n = b.f.length / 2, base = v.length / 3;
      for (let i = 0; i < n; i++) { v.push(b.f[i * 2], -0.5, b.f[i * 2 + 1], b.f[i * 2], b.h, b.f[i * 2 + 1]); }
      for (let i = 0; i < n; i++) {
        const a = base + i * 2, c = base + ((i + 1) % n) * 2;
        ix.push(a, c, a + 1, c, c + 1, a + 1);
      }
      // roof as a fan (good enough for convex-ish footprints; walls carry the collision)
      for (let i = 1; i < n - 1; i++) ix.push(base + 1, base + i * 2 + 1, base + (i + 1) * 2 + 1);
    }
    const desc = RAPIER.ColliderDesc.trimesh(new Float32Array(v), new Uint32Array(ix), RAPIER.TriMeshFlags.FIX_INTERNAL_EDGES)
      .setCollisionGroups(groups(Group.World, 0xffff)).setFriction(0.6);
    this.chunkColliders.set(key, [this.world.createCollider(desc)]);
  }
  removeChunk(key: string) {
    const c = this.chunkColliders.get(key); if (!c) return;
    for (const x of c) this.world.removeCollider(x, false);
    this.chunkColliders.delete(key);
  }

  castRay(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, maxToi: number, exclude?: RAPIER.RigidBody, filterGroups?: number): { toi: number; collider: RAPIER.Collider } | null {
    const ray = new RAPIER.Ray({ x: ox, y: oy, z: oz }, { x: dx, y: dy, z: dz });
    const hit = this.world.castRay(ray, maxToi, true, undefined, filterGroups, undefined, exclude);
    return hit ? { toi: hit.timeOfImpact, collider: hit.collider } : null;
  }
  get chunkCount() { return this.chunkColliders.size; }
}
