// Appearance generator: realistic South Indian dress and skin-tone distribution.
// Values are from STYLE_BIBLE §People. Skin tones span light wheatish to deep brown with
// no correlation to role or wealth (no colourism).
import { type Rng, pick, pickW } from '../engine/rng';
import type { Variant } from './humanMesh';

const hex = (h: string): [number, number, number] => {
  const n = parseInt(h.slice(1), 16);
  // sRGB → linear so colours match the swatches under AgX tonemapping
  const l = (c: number) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return [l((n >> 16) & 255), l((n >> 8) & 255), l(n & 255)];
};

export const SKIN_TONES = ['#c99c78', '#b98a63', '#ab7b55', '#9c6c48', '#8c5e3e', '#7c5034', '#6b442c', '#5b3925', '#4d3020'].map(hex);
const SKIN_WEIGHTS = [5, 10, 15, 18, 17, 14, 10, 7, 4];
const HAIR = ['#120e0c', '#1a1310', '#211813', '#0d0b0a'].map(hex);
const HAIR_GREY = ['#8a8580', '#b5b0aa', '#d8d4ce', '#5c5650'].map(hex);

const SHIRTS = ['#f2f0ea', '#e9eef2', '#a9c4de', '#7fa2c8', '#5a6f8c', '#7a2e35', '#2f3e5c', '#8c8c86', '#6b7a4a', '#c9b48a', '#d9c8a6', '#3d6b72', '#b85c3c', '#e0d36a', '#4f7f5b', '#9a4f80', '#262626', '#cfdbe6'].map(hex);
const TSHIRTS = ['#d93636', '#2b6fd6', '#f2c230', '#1b1b1b', '#f5f5f5', '#2e9e6a', '#ff7a2f', '#7e57c2', '#00a3b4', '#e94b8a'].map(hex);
const PANTS = ['#1f2533', '#2b2b2b', '#474b52', '#6e6450', '#3c4f73', '#2f4a6b', '#5a4b3a', '#4a5a6a'].map(hex);
const VESHTI = ['#f4f1e8', '#efe9d8', '#f7f5ef', '#e8e0c8'].map(hex);
const VESHTI_BORDER = ['#c9a43a', '#1f6b3a', '#1d3f8a', '#8a1c2a', '#d4b04a'].map(hex);
const LUNGI = ['#2a4f8f', '#7b1f2d', '#2f6d47', '#4b3b7a', '#8f5a1f', '#1f5e6e', '#6d2a5b'].map(hex);
const SAREES = ['#c2185b', '#e6a91c', '#7cb342', '#00838f', '#c62828', '#ef6c00', '#6a1b9a', '#1565c0', '#ad1457', '#558b2f', '#f9a825', '#4e342e', '#00695c', '#d84315', '#283593', '#9e9d24', '#b71c1c', '#ff8f00'].map(hex);
const SAREE_BORDER = ['#d4af37', '#c9a43a', '#b71c1c', '#1b5e20', '#0d47a1', '#4a148c', '#e8c766'].map(hex);
const KURTA = ['#f8bbd0', '#b2dfdb', '#fff59d', '#ce93d8', '#80cbc4', '#ffab91', '#90caf9', '#c5e1a5', '#f48fb1', '#e57373', '#4db6ac', '#ffd54f', '#9575cd'].map(hex);
const LEGGINGS = ['#fafafa', '#212121', '#e0e0e0', '#c2185b', '#1a237e', '#004d40'].map(hex);
const UNIFORM_SHIRT = ['#f5f5f5', '#e3f2fd', '#fff8e1'].map(hex);
const UNIFORM_LOWER = ['#1a2a5a', '#5d1a1a', '#2e4a2e', '#3b5a8a', '#4a4a4a'].map(hex);
const JASMINE = hex('#f6f3e6');

export interface Appearance {
  variant: Variant; scale: number; elder: boolean;
  top: [number, number, number]; lower: [number, number, number]; skin: [number, number, number];
  hair: [number, number, number]; border: [number, number, number]; accent: [number, number, number]; drape: [number, number, number];
  /** 0 plain, 1 checks (lungi/checked shirt), 2 border band (veshti/saree), 3 vertical stripes */
  pattern: number; topPattern: number; gait: number;
}

export interface Demographics { men: number; women: number; children: number; elders: number; traditional: number }
export const DEFAULT_DEMO: Demographics = { men: 0.52, women: 0.38, children: 0.1, elders: 0.16, traditional: 0.45 };

export function makeAppearance(r: Rng, demo: Demographics = DEFAULT_DEMO): Appearance {
  const kind = pickW(r, [demo.men, demo.women, demo.children]);
  const elder = kind !== 2 && r() < demo.elders;
  const skin = SKIN_TONES[pickW(r, SKIN_WEIGHTS)];
  const hair = elder && r() < 0.7 ? pick(r, HAIR_GREY) : pick(r, HAIR);
  const a: Appearance = { variant: 'man_pants', scale: 1, elder, top: skin, lower: skin, skin, hair, border: JASMINE, accent: JASMINE, drape: skin, pattern: 0, topPattern: 0, gait: elder ? 0.75 : 1 };
  if (kind === 0) {
    a.scale = 0.97 + r() * 0.1;
    const trad = r() < demo.traditional + (elder ? 0.3 : 0);
    if (trad) {
      if (r() < 0.55) { a.variant = 'man_veshti'; a.lower = pick(r, VESHTI); a.border = pick(r, VESHTI_BORDER); a.accent = pick(r, VESHTI); a.pattern = 2; }
      else { a.variant = 'man_lungi'; a.lower = pick(r, LUNGI); a.border = pick(r, LUNGI); a.accent = pick(r, VESHTI); a.pattern = 1; }
      a.top = r() < 0.75 ? pick(r, SHIRTS) : pick(r, VESHTI);
      a.topPattern = r() < 0.25 ? 1 : 0;
    } else {
      a.variant = 'man_pants';
      a.top = r() < 0.4 ? pick(r, TSHIRTS) : pick(r, SHIRTS);
      a.topPattern = r() < 0.2 ? 1 : r() < 0.1 ? 3 : 0;
      a.lower = pick(r, PANTS);
    }
  } else if (kind === 1) {
    a.scale = 0.92 + r() * 0.08;
    if (r() < demo.traditional + 0.3 + (elder ? 0.3 : 0)) {
      a.variant = 'woman_saree';
      a.lower = pick(r, SAREES); a.drape = a.lower; a.top = r() < 0.6 ? pick(r, SAREES) : a.lower; a.pattern = 2;
      a.accent = r() < 0.75 ? JASMINE : pick(r, SAREE_BORDER);
      a.border = pick(r, SAREE_BORDER);
    } else {
      a.variant = 'woman_churidar';
      a.top = pick(r, KURTA); a.lower = pick(r, LEGGINGS); a.drape = r() < 0.5 ? pick(r, KURTA) : a.lower;
      a.accent = r() < 0.5 ? JASMINE : a.hair; a.topPattern = r() < 0.3 ? 3 : 0;
    }
  } else {
    a.variant = 'child'; a.scale = 0.62 + r() * 0.2; a.gait = 1.2;
    if (r() < 0.6) { a.top = pick(r, UNIFORM_SHIRT); a.lower = pick(r, UNIFORM_LOWER); }
    else { a.top = pick(r, TSHIRTS); a.lower = pick(r, PANTS); }
  }
  return a;
}
