// Phase 0 rendering spike: WebGPU/WebGL2 + Rapier + 10k GPU-animated instanced people.
import * as THREE from 'three/webgpu';
import RAPIER from '@dimforge/rapier3d-compat';
import { createRenderer } from './engine/renderer';
import { Stats } from './engine/stats';
import { Sky } from './world/sky';
import { CrowdRenderer } from './crowd/crowdRenderer';
import { makeAppearance } from './crowd/appearance';
import { mulberry } from './engine/rng';
import { urlParams } from './engine/settings';

export async function runSpike(canvas: HTMLCanvasElement) {
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 5000);
  const ctx = await createRenderer(canvas, scene, camera);
  const stats = new Stats(true);
  const sky = new Sky(scene);
  sky.hour = parseFloat(urlParams.get('hour') || '16.5'); sky.paused = true;

  const ground = new THREE.Mesh(new THREE.PlaneGeometry(2000, 2000).rotateX(-Math.PI / 2), new THREE.MeshStandardNodeMaterial({ color: 0x8a7c6a, roughness: 0.95 }));
  ground.receiveShadow = true; scene.add(ground);

  await RAPIER.init();
  const world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
  world.createCollider(RAPIER.ColliderDesc.cuboid(1000, 0.1, 1000).setTranslation(0, -0.1, 0));
  const boxes: { body: RAPIER.RigidBody; mesh: THREE.Mesh }[] = [];
  const bm = new THREE.MeshStandardNodeMaterial({ color: 0xc4513a, roughness: 0.7 });
  for (let i = 0; i < 60; i++) {
    const body = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation((i % 10) * 1.2 - 6, 2 + Math.floor(i / 10) * 1.3, -12));
    world.createCollider(RAPIER.ColliderDesc.cuboid(0.5, 0.5, 0.5), body);
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), bm); mesh.castShadow = true; scene.add(mesh);
    boxes.push({ body, mesh });
  }

  const N = parseInt(urlParams.get('n') || '10000');
  const crowd = new CrowdRenderer(N + 100);
  scene.add(crowd.group);
  const r = mulberry(42);
  const R = N < 1000 ? 25 : 160;
  for (let i = 0; i < N; i++) {
    const a = r() * Math.PI * 2, d = Math.sqrt(r()) * R;
    const p = crowd.add(makeAppearance(r), Math.cos(a) * d, Math.sin(a) * d, r() * Math.PI * 2);
    p.gait = urlParams.get('still') ? 0 : r() < 0.75 ? 1 : 0; p.wobble = r() < 0.15 ? 0.12 : 0; p.gesture = r() < 0.04 ? 1 : 0;
  }
  camera.position.set(0, 3.2, 14); camera.lookAt(0, 1.4, 0);
  let orbit = 0;
  const clock = new THREE.Timer();
  const loop = () => {
    clock.update(); const dt = Math.min(clock.getDelta(), 0.1);
    world.timestep = Math.min(dt, 1 / 30); world.step();
    for (const b of boxes) { const t = b.body.translation(), q = b.body.rotation(); b.mesh.position.set(t.x, t.y, t.z); b.mesh.quaternion.set(q.x, q.y, q.z, q.w); }
    for (const p of crowd.people) {
      if (p.gait > 0) { const v = 1.25 * p.app.gait * dt; p.x += Math.sin(p.heading) * v; p.z += Math.cos(p.heading) * v;
        if (p.x * p.x + p.z * p.z > R * R) p.heading += Math.PI; }
    }
    if (urlParams.get('orbit') === '1') { orbit += dt * 0.05; camera.position.set(Math.sin(orbit) * 14, 3.2, Math.cos(orbit) * 14); camera.lookAt(0, 1.4, 0); }
    camera.updateMatrixWorld();
    crowd.sync(camera);
    sky.update(dt, camera.position, ctx.exposure, ctx.renderer);
    ctx.render();
    stats.extra = { npcs: crowd.people.length, near: crowd.stats.near, mid: crowd.stats.mid, far: crowd.stats.far, culled: crowd.stats.culled };
    stats.update(dt, ctx.renderer, ctx.backend);
    requestAnimationFrame(loop);
  };
  document.getElementById('loading')?.classList.add('done');
  (window as unknown as { __ready: boolean }).__ready = true;
  loop();
}
