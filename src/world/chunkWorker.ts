// Chunk worker: fetches a chunk's building data and generates façade / generic / sign meshes,
// collider footprints, shop metadata and the chunk's unique signboard atlas.
import { genBuilding, newCtx, SIGN_ATLAS, type BuildingIn, type Style } from './gen/buildings';
import { paintSigns, type NamesData } from './gen/signPainter';

interface InitMsg { type: 'init'; base: string; style: Style; names: NamesData; roadNames: string[]; fonts: { family: string; url: string; weight: string; style: string; unicodeRange: string }[] }
interface BuildMsg { type: 'build'; id: number; key: string; url: string; detail: boolean }

let style: Style, names: NamesData, roadNames: string[] = [];
let fontsReady: Promise<unknown> = Promise.resolve();
const cache = new Map<string, { b: BuildingIn[] }>();

self.onmessage = async (ev: MessageEvent<InitMsg | BuildMsg>) => {
  const m = ev.data;
  if (m.type === 'init') {
    style = m.style; names = m.names; roadNames = m.roadNames;
    const fs = (self as unknown as { fonts: FontFaceSet }).fonts;
    fontsReady = Promise.all(m.fonts.map(async (f) => {
      try {
        const ff = new FontFace(f.family, `url(${new URL(f.url, m.base).href})`, { weight: f.weight, style: f.style, unicodeRange: f.unicodeRange });
        fs.add(ff); await ff.load();
      } catch (e) { console.warn('font', f.family, e); }
    }));
    return;
  }
  if (m.type === 'build') {
    try {
      let data = cache.get(m.url);
      if (!data) { data = await (await fetch(m.url)).json() as { b: BuildingIn[] }; cache.set(m.url, data); }
      const ctx = newCtx(m.detail, SIGN_ATLAS.cols * SIGN_ATLAS.rows, names.trades);
      for (const b of data.b) genBuilding(b, style, ctx);
      let atlas: ImageBitmap | null = null;
      if (m.detail && ctx.signs.length) {
        await fontsReady;
        atlas = paintSigns(ctx.signs, names, roadNames, m.key);
        // the atlas is only as tall as needed: rescale sign v coordinates
        if (atlas) { const k = SIGN_ATLAS.h / atlas.height; const uv = ctx.sign.data.uv; for (let i = 1; i < uv.length; i += 2) uv[i] *= k; }
      }
      const out = { facade: ctx.facade.build(), generic: ctx.generic.build(), sign: ctx.sign.build() };
      const colliders = ctx.colliders;
      const transfer: Transferable[] = [];
      for (const g of Object.values(out)) { transfer.push(g.index.buffer); for (const a of Object.values(g.attrs)) transfer.push(a.buffer); }
      if (atlas) transfer.push(atlas);
      (self as unknown as Worker).postMessage({ type: 'built', id: m.id, key: m.key, detail: m.detail, out, colliders, shops: ctx.shops, lights: ctx.lights, atlas }, transfer);
    } catch (e) {
      (self as unknown as Worker).postMessage({ type: 'error', id: m.id, key: m.key, error: String((e as Error)?.stack || e) });
    }
  }
};
