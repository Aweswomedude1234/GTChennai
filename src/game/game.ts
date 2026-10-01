// Top-level game: boots renderer, loads the city pack, streams the region, runs the loop.
import * as THREE from 'three/webgpu';
import { createRenderer, type RenderCtx } from '../engine/renderer';
import { Stats } from '../engine/stats';
import { Input } from '../engine/input';
import { settings, urlParams } from '../engine/settings';
import { Sky } from '../world/sky';
import { Region, type RegionMeta } from '../world/region';
import { Streamer } from '../world/streamer';
import { U } from '../world/materials';
import { Physics } from '../physics/physics';

export interface Pack { id: string; name: Record<string, string>; localLang: string; regions: string[]; spawn: { region: string; x: number; z: number; heading: number }; style: string; names: string }

export async function parseFonts(cssUrl: string) {
  const css = await (await fetch(cssUrl)).text();
  const out: { family: string; url: string; weight: string; style: string; unicodeRange: string }[] = [];
  for (const block of css.split('@font-face').slice(1)) {
    const fam = block.match(/font-family:\s*'([^']+)'/)?.[1]; const url = block.match(/url\(([^)]+)\)/)?.[1];
    if (!fam || !url) continue;
    out.push({ family: fam, url: new URL(url, new URL(cssUrl, location.href)).href, weight: block.match(/font-weight:\s*([^;]+);/)?.[1] || '400', style: block.match(/font-style:\s*([^;]+);/)?.[1] || 'normal', unicodeRange: block.match(/unicode-range:\s*([^;]+);/)?.[1] || 'U+0-10FFFF' });
  }
  return out;
}

export class Game {
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(settings.fov, 1, 0.1, 6000);
  ctx!: RenderCtx;
  stats = new Stats(settings.debug);
  input: Input;
  sky!: Sky;
  physics = new Physics();
  region!: Region;
  streamer!: Streamer;
  pack!: Pack;
  focus = new THREE.Vector3();
  private timer = new THREE.Timer();
  private loadingEl = document.getElementById('loading');

  constructor(public canvas: HTMLCanvasElement) { this.input = new Input(canvas); }

  private progress(p: number, msg: string) {
    const bar = this.loadingEl?.querySelector('.bar i') as HTMLElement | null; if (bar) bar.style.width = `${Math.round(p * 100)}%`;
    const m = this.loadingEl?.querySelector('.msg'); if (m) m.textContent = msg;
  }

  async start() {
    const t0 = performance.now();
    this.progress(0.05, 'Starting renderer…');
    this.ctx = await createRenderer(this.canvas, this.scene, this.camera);
    this.sky = new Sky(this.scene);
    if (urlParams.has('hour')) this.sky.hour = parseFloat(urlParams.get('hour')!);
    if (urlParams.get('freeze') === '1') this.sky.paused = true;
    this.progress(0.15, 'Loading Chennai…');
    const packBase = `packs/${settings.city}`;
    this.pack = await (await fetch(`${packBase}/pack.json`)).json();
    const [style, names, fonts] = await Promise.all([
      fetch(`${packBase}/${this.pack.style}`).then((r) => r.json()),
      fetch(`${packBase}/${this.pack.names}`).then((r) => r.json()),
      parseFonts('fonts/fonts.css'),
      this.physics.init(),
    ]);
    const regionId = this.pack.spawn.region;
    const regionBase = `${packBase}/regions/${regionId}`;
    const meta: RegionMeta = await (await fetch(`${regionBase}/meta.json`)).json();
    this.progress(0.3, 'Laying roads…');
    this.region = new Region(meta);
    this.scene.add(this.region.group);
    for (const name of ['ground', 'footpaths']) { const m = this.region.group.getObjectByName(name) as THREE.Mesh | undefined; if (m) this.physics.addStaticMesh(m.geometry); }
    this.streamer = new Streamer(meta, regionBase, this.physics);
    await this.streamer.init(style, names, fonts);
    this.scene.add(this.streamer.group);

    // spawn / camera
    const sp = urlParams.get('spawn')?.split(',').map(Number);
    this.focus.set(sp?.[0] ?? this.pack.spawn.x, 0, sp?.[1] ?? this.pack.spawn.z);
    const cam = urlParams.get('cam')?.split(',').map(Number);
    if (cam) { this.camera.position.set(cam[0], cam[1], cam[2]); this.camera.lookAt(cam[3], cam[4], cam[5]); this.focus.set(cam[3], 0, cam[5]); }
    else { this.camera.position.set(this.focus.x - 20, 12, this.focus.z + 20); this.camera.lookAt(this.focus.x, 2, this.focus.z); }

    // wait for the near ring before showing the world
    this.progress(0.45, 'Building Mylapore…');
    await new Promise<void>((res) => {
      const tick = () => {
        this.streamer.update(this.focus.x, this.focus.z);
        const s = this.streamer.stats;
        this.progress(0.45 + 0.5 * Math.min(1, s.built / Math.max(1, s.built + s.pending)), `Building streets… ${s.near} near / ${s.far} far`);
        if (this.streamer.nearReady(this.focus.x, this.focus.z)) res(); else setTimeout(tick, 50);
      };
      tick();
    });
    this.loadingEl?.classList.add('done');
    (window as unknown as { __loadMs: number }).__loadMs = performance.now() - t0;
    this.timer.update();
    this.loop();
    setTimeout(() => { (window as unknown as { __ready: boolean }).__ready = true; }, 300);
  }

  private loop = () => {
    requestAnimationFrame(this.loop);
    this.timer.update();
    const dt = Math.min(this.timer.getDelta(), 0.1);
    if (this.input.justPressed('debug')) this.stats.toggle();
    this.streamer.update(this.focus.x, this.focus.z);
    this.sky.update(dt, this.focus, this.ctx.exposure, this.ctx.renderer);
    U.night.value = this.sky.nightFactor; U.hour.value = this.sky.hour;
    this.camera.updateMatrixWorld();
    this.ctx.render();
    const s = this.streamer.stats;
    this.stats.extra = { time: this.sky.formatClock(), chunks: `${s.near} near ${s.far} far (${s.pending} pending, ${s.lastBuildMs.toFixed(0)} ms)`, colliders: this.physics.chunkCount, pos: `${this.focus.x.toFixed(0)}, ${this.focus.z.toFixed(0)}` };
    this.stats.update(dt, this.ctx.renderer, this.ctx.backend);
    this.input.endFrame();
  };
}
