// Paints unique Tamil + English shop signboards into a per-chunk atlas (OffscreenCanvas, in the worker).
// Styles follow STYLE_BIBLE §3: Tamil first and largest; 60% printed flex, 40% hand-painted.
import { mulberry, pick, pickW, type Rng } from '../../engine/rng';
import { SIGN_ATLAS, type SignReq } from './buildings';

export interface NamesData {
  prefix: [string, string, number][]; given: [string, string][]; suffix: [string, string, number][];
  trades: { id: string; w: number; ta: string[]; en: string[]; colors?: string[]; hours: [number, number] }[];
  upper: { ta: string; en: string }[]; flexColors: string[]; paintColors: string[];
}

export interface ShopName { ta: string; en: string; trade: string }
export function shopName(names: NamesData, seed: number, trade: number): ShopName {
  const r = mulberry(seed ^ 0x5bd1e995);
  const t = names.trades[trade];
  const pi = pickW(r, names.prefix.map((p) => p[2]));
  const [pTa, pEn] = names.prefix[pi];
  const [gTa, gEn] = pick(r, names.given);
  const vi = Math.floor(r() * t.ta.length);
  const si = pickW(r, names.suffix.map((s) => s[2]));
  const [sTa, sEn] = names.suffix[si];
  const ta = [pTa, gTa, t.ta[vi], sTa].filter(Boolean).join(' ');
  const en = [pEn, gEn, t.en[Math.min(vi, t.en.length - 1)], sEn].filter(Boolean).join(' ');
  return { ta, en, trade: t.id };
}

const lum = (hex: string) => { const n = parseInt(hex.slice(1), 16); return (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255; };
function shade(hex: string, k: number) {
  const n = parseInt(hex.slice(1), 16); const f = (c: number) => Math.max(0, Math.min(255, Math.round(c * k)));
  return `rgb(${f((n >> 16) & 255)},${f((n >> 8) & 255)},${f(n & 255)})`;
}
function fitText(g: OffscreenCanvasRenderingContext2D, text: string, font: (px: number) => string, maxW: number, px: number, minPx = 8) {
  let s = px; g.font = font(s);
  while (g.measureText(text).width > maxW && s > minPx) { s -= 1; g.font = font(s); }
  return s;
}
function phone(r: Rng) { return r() < 0.5 ? `Ph: 044-24${Math.floor(10 + r() * 89)} ${Math.floor(1000 + r() * 8999)}` : `Cell: 9${Math.floor(r() * 9)}${Math.floor(100 + r() * 899)} ${Math.floor(10000 + r() * 89999)}`; }

function emblem(g: OffscreenCanvasRenderingContext2D, r: Rng, x: number, y: number, rad: number, fg: string, bg: string, trade: string) {
  g.save();
  g.fillStyle = bg; g.beginPath(); g.arc(x, y, rad, 0, Math.PI * 2); g.fill();
  g.strokeStyle = fg; g.lineWidth = 2; g.stroke();
  g.fillStyle = fg;
  // simple trade pictograms
  if (trade === 'tea') { g.fillRect(x - rad * 0.35, y - rad * 0.2, rad * 0.6, rad * 0.6); g.fillRect(x + rad * 0.25, y - rad * 0.05, rad * 0.2, rad * 0.25); }
  else if (trade === 'medical') { g.fillRect(x - rad * 0.15, y - rad * 0.55, rad * 0.3, rad * 1.1); g.fillRect(x - rad * 0.55, y - rad * 0.15, rad * 1.1, rad * 0.3); }
  else if (trade === 'jewel') { g.beginPath(); g.moveTo(x, y + rad * 0.6); g.lineTo(x - rad * 0.55, y - rad * 0.1); g.lineTo(x - rad * 0.25, y - rad * 0.45); g.lineTo(x + rad * 0.25, y - rad * 0.45); g.lineTo(x + rad * 0.55, y - rad * 0.1); g.fill(); }
  else if (trade === 'mobile') { g.fillRect(x - rad * 0.28, y - rad * 0.55, rad * 0.56, rad * 1.1); g.fillStyle = bg; g.fillRect(x - rad * 0.2, y - rad * 0.42, rad * 0.4, rad * 0.75); }
  else { g.font = `800 ${Math.round(rad * 1.1)}px 'Baloo Thambi 2', 'Noto Sans Tamil'`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(pick(r, ['ஸ்ரீ', 'ௐ', '★', 'அ']), x, y + rad * 0.08); }
  g.restore();
}

/** paint all requested signs; returns the atlas as an ImageBitmap */
export function paintSigns(signs: SignReq[], names: NamesData, roadNames: string[], chunkKey: string): ImageBitmap | null {
  if (!signs.length) return null;
  const { w, h, cw, ch, cols } = SIGN_ATLAS;
  const rows = Math.ceil(signs.length / cols);
  const cv = new OffscreenCanvas(w, Math.min(h, Math.max(ch * rows, 256)));
  const g = cv.getContext('2d')!;
  g.fillStyle = '#777'; g.fillRect(0, 0, cv.width, cv.height);
  for (const s of signs) {
    const x0 = (s.cell % cols) * cw, y0 = Math.floor(s.cell / cols) * ch;
    const r = mulberry(s.seed ^ 0x2545f491);
    const nm = shopName(names, s.seed, s.trade);
    const trade = names.trades[s.trade];
    g.save(); g.beginPath(); g.rect(x0, y0, cw, ch); g.clip(); g.translate(x0, y0);
    const road = s.road >= 0 ? roadNames[s.road] : '';
    const addr = `No.${1 + Math.floor(r() * 180)}${road ? ', ' + road : ''}, Mylapore, Ch-4`;
    if (s.kind === 'flex') {
      const bg = trade.colors && r() < 0.6 ? trade.colors[0] : pick(r, names.flexColors);
      const light = lum(bg) > 0.6;
      const fg = trade.colors && r() < 0.6 ? trade.colors[1] : light ? pick(r, ['#c62828', '#1a237e', '#1b5e20', '#111']) : pick(r, ['#ffffff', '#ffeb3b', '#fff59d']);
      const grad = g.createLinearGradient(0, 0, 0, ch);
      grad.addColorStop(0, shade(bg, 1.15)); grad.addColorStop(1, shade(bg, 0.8));
      g.fillStyle = grad; g.fillRect(0, 0, cw, ch);
      // swoosh band
      g.fillStyle = light ? 'rgba(0,0,0,0.08)' : 'rgba(255,255,255,0.12)';
      g.beginPath(); g.moveTo(0, ch * 0.7); g.quadraticCurveTo(cw * 0.5, ch * 0.45, cw, ch * 0.75); g.lineTo(cw, ch); g.lineTo(0, ch); g.fill();
      const em = r() < 0.75;
      const left = em ? ch * 0.86 : 8;
      if (em) emblem(g, r, ch * 0.44, ch * 0.42, ch * 0.3, fg, shade(bg, 0.7), trade.id);
      g.fillStyle = fg; g.textAlign = 'center'; g.textBaseline = 'alphabetic';
      const cx = (left + cw - 6) / 2, maxW = cw - left - 10;
      const taPx = fitText(g, nm.ta, (p) => `800 ${p}px 'Baloo Thambi 2', 'Noto Sans Tamil'`, maxW, 30);
      g.shadowColor = 'rgba(0,0,0,0.35)'; g.shadowOffsetY = 1.5; g.shadowBlur = 1;
      g.fillText(nm.ta, cx, 6 + taPx);
      g.shadowColor = 'transparent';
      g.fillStyle = light ? '#222' : '#fff';
      const enPx = fitText(g, nm.en, (p) => `${p}px Anton, Oswald, 'Noto Sans'`, maxW, 19);
      g.fillText(nm.en, cx, 10 + taPx + enPx);
      g.font = `600 9px 'Noto Sans'`; g.fillStyle = light ? '#333' : 'rgba(255,255,255,0.9)';
      g.fillText(`${addr}  ${phone(r)}`.slice(0, 62), cw / 2, ch - 4);
    } else if (s.kind === 'paint') {
      const bg = pick(r, names.paintColors);
      const light = lum(bg) > 0.55;
      g.fillStyle = bg; g.fillRect(0, 0, cw, ch);
      const fg = light ? pick(r, ['#b71c1c', '#0d47a1', '#1b5e20', '#212121', '#4a148c']) : pick(r, ['#ffffff', '#ffe082', '#fff8e1']);
      g.strokeStyle = fg; g.lineWidth = 3; g.strokeRect(5, 5, cw - 10, ch - 10);
      g.fillStyle = fg; g.textAlign = 'center';
      const font = pick(r, ["700 PXpx Arima, 'Noto Sans Tamil'", "800 PXpx Catamaran, 'Noto Sans Tamil'", "700 PXpx 'Hind Madurai', 'Noto Sans Tamil'", "400 PXpx Kavivanar, 'Noto Sans Tamil'"]);
      g.save(); g.translate(cw / 2, 0); g.rotate((r() - 0.5) * 0.02);
      const taPx = fitText(g, nm.ta, (p) => font.replace('PX', String(p)), cw - 24, 28);
      g.fillText(nm.ta, 0, 8 + taPx);
      const enPx = fitText(g, nm.en, (p) => `700 ${p}px 'Noto Serif', serif`, cw - 24, 17);
      g.fillStyle = light ? shade(fg.startsWith('#') ? fg : '#000000', 0.8) : fg;
      g.fillText(nm.en, 0, 12 + taPx + enPx);
      g.restore();
    } else {
      const u = names.upper[(s.upper ?? 0) % names.upper.length];
      const bg = pick(r, names.flexColors);
      const light = lum(bg) > 0.6;
      g.fillStyle = bg; g.fillRect(0, 0, cw, ch);
      g.fillStyle = light ? '#1a237e' : '#fff'; g.textAlign = 'center';
      const given = pick(r, names.given);
      const t1 = `${given[0]} ${u.ta}`, t2 = `${given[1]} ${u.en}`;
      const p1 = fitText(g, t1, (p) => `800 ${p}px 'Baloo Thambi 2'`, cw - 16, 26);
      g.fillText(t1, cw / 2, 6 + p1);
      const p2 = fitText(g, t2, (p) => `${p}px Oswald, 'Noto Sans'`, cw - 16, 18);
      g.fillText(t2, cw / 2, 12 + p1 + p2);
      g.font = `600 10px 'Noto Sans'`; g.fillText(phone(r), cw / 2, ch - 5);
    }
    // weathering: dust, fading, stains (hand-painted boards weather more)
    const wAmt = s.kind === 'paint' ? 0.25 + r() * 0.35 : r() * 0.25;
    for (let i = 0; i < 18; i++) {
      g.fillStyle = `rgba(${r() < 0.5 ? '90,80,60' : '255,250,235'},${(r() * wAmt * 0.35).toFixed(3)})`;
      g.fillRect(r() * cw, r() * ch, 8 + r() * 60, 3 + r() * 20);
    }
    if (s.kind === 'paint') for (let i = 0; i < 4; i++) { g.fillStyle = `rgba(110,60,20,${(0.15 * wAmt + r() * 0.1).toFixed(3)})`; g.fillRect(r() * cw, ch * 0.6, 2 + r() * 3, ch * 0.4); }
    g.restore();
  }
  void chunkKey;
  return cv.transferToImageBitmap();
}
