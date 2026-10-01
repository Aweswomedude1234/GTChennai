// Debug stats overlay (BRIEF §2): FPS, frame time, draw calls, triangles, NPCs, vehicles, memory.
import type * as THREE from 'three/webgpu';

export class Stats {
  el: HTMLDivElement;
  private frames = 0; private acc = 0; private worst = 0;
  fps = 0; frameMs = 0; worstMs = 0;
  extra: Record<string, string | number> = {};
  constructor(visible: boolean) {
    this.el = document.createElement('div');
    this.el.id = 'stats';
    this.el.style.cssText = 'position:fixed;left:8px;top:8px;font:11px/1.35 ui-monospace,Consolas,monospace;color:#e8f5e8;background:rgba(0,0,0,.55);padding:6px 8px;border-radius:4px;pointer-events:none;z-index:50;white-space:pre;';
    this.el.style.display = visible ? 'block' : 'none';
    document.body.appendChild(this.el);
  }
  toggle() { this.el.style.display = this.el.style.display === 'none' ? 'block' : 'none'; }
  update(dt: number, renderer: THREE.WebGPURenderer, backend: string) {
    this.frames++; this.acc += dt; this.worst = Math.max(this.worst, dt);
    if (this.acc < 0.5) return;
    this.fps = this.frames / this.acc; this.frameMs = (this.acc / this.frames) * 1000; this.worstMs = this.worst * 1000;
    this.frames = 0; this.acc = 0; this.worst = 0;
    const r = renderer.info.render;
    const mem = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory;
    const lines = [
      `GTIndian ${backend.toUpperCase()}  ${this.fps.toFixed(0)} fps  ${this.frameMs.toFixed(1)} ms (worst ${this.worstMs.toFixed(1)})`,
      `draws ${r.drawCalls}  tris ${(r.triangles / 1e6).toFixed(2)}M  geo ${renderer.info.memory.geometries}  tex ${renderer.info.memory.textures}`,
      mem ? `heap ${(mem.usedJSHeapSize / 1048576).toFixed(0)} MB` : '',
      ...Object.entries(this.extra).map(([k, v]) => `${k}: ${v}`),
    ];
    this.el.textContent = lines.filter(Boolean).join('\n');
    (window as unknown as { __stats: unknown }).__stats = { fps: this.fps, frameMs: this.frameMs, worstMs: this.worstMs, draws: r.drawCalls, tris: r.triangles, ...this.extra };
  }
}
