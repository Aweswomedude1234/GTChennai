// Persistent player settings (BRIEF §14). Voice / subtitle / UI languages are independent.
export type Lang = 'ta' | 'te' | 'hi' | 'ml' | 'kn' | 'en';
export type Quality = 'low' | 'medium' | 'high' | 'ultra';
export type CameraMode = 'third' | 'first' | 'top';

export interface Settings {
  voiceLang: Lang; subtitleLang: Lang; uiLang: Lang; city: string;
  camera: CameraMode; fov: number; quality: Quality;
  shadows: boolean; ssao: boolean; bloom: boolean; renderScale: number;
  npcDensity: number; trafficDensity: number; hornIntensity: number;
  subtitleSize: number; colorblind: 'none' | 'protan' | 'deutan' | 'tritan';
  radio: boolean; masterVolume: number; musicVolume: number; debug: boolean;
}

export const QUALITY_PRESETS: Record<Quality, Partial<Settings>> = {
  low: { shadows: false, ssao: false, bloom: false, renderScale: 0.75 },
  medium: { shadows: true, ssao: false, bloom: true, renderScale: 1 },
  high: { shadows: true, ssao: true, bloom: true, renderScale: 1 },
  ultra: { shadows: true, ssao: true, bloom: true, renderScale: 1.25 },
};

const DEFAULTS: Settings = {
  voiceLang: 'ta', subtitleLang: 'en', uiLang: 'en', city: 'chennai',
  camera: 'third', fov: 62, quality: 'high', shadows: true, ssao: true, bloom: true, renderScale: 1,
  npcDensity: 1, trafficDensity: 1, hornIntensity: 1, subtitleSize: 1, colorblind: 'none',
  radio: true, masterVolume: 0.8, musicVolume: 0.7, debug: true,
};

function load(): Settings {
  let s: Partial<Settings> = {};
  try { s = JSON.parse(localStorage.getItem('gti.settings') || '{}'); } catch { /* storage unavailable */ }
  const url = new URLSearchParams(location.search);
  const out = { ...DEFAULTS, ...s } as Settings;
  // URL overrides (used by the verification harness)
  for (const [k, v] of url) if (k in DEFAULTS) {
    const d = (DEFAULTS as unknown as Record<string, unknown>)[k];
    (out as unknown as Record<string, unknown>)[k] = typeof d === 'number' ? parseFloat(v) : typeof d === 'boolean' ? v === '1' || v === 'true' : v;
  }
  if (url.has('quality')) Object.assign(out, QUALITY_PRESETS[out.quality]);
  return out;
}

export const settings: Settings = load();
const listeners = new Set<(s: Settings) => void>();
export function saveSettings(patch: Partial<Settings>) {
  Object.assign(settings, patch);
  try { localStorage.setItem('gti.settings', JSON.stringify(settings)); } catch { /* ignore */ }
  for (const l of listeners) l(settings);
}
export function onSettings(fn: (s: Settings) => void) { listeners.add(fn); return () => listeners.delete(fn); }
export const urlParams = new URLSearchParams(location.search);
