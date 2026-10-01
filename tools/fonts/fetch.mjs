// Download OFL fonts from Google Fonts (woff2) and write public/fonts/fonts.css with relative URLs.
import fs from 'node:fs';
const FAMILIES = [
  'Baloo+Thambi+2:wght@600;800', 'Arima:wght@700', 'Catamaran:wght@500;800', 'Noto+Sans+Tamil:wght@400;700', 'Kavivanar',
  'Hind+Madurai:wght@500;700', 'Anton', 'Oswald:wght@600', 'Noto+Sans:wght@400;700', 'Noto+Serif:wght@700',
  'Noto+Sans+Telugu:wght@400;700', 'Noto+Sans+Devanagari:wght@400;700', 'Noto+Sans+Malayalam:wght@400;700', 'Noto+Sans+Kannada:wght@400;700',
];
const UA = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36' };
let css = '/* OFL fonts from Google Fonts — see docs/CREDITS.md */\n';
for (const fam of FAMILIES) {
  const src = await (await fetch(`https://fonts.googleapis.com/css2?family=${fam}&display=swap`, { headers: UA })).text();
  // keep only latin + indic subsets (skip cyrillic/greek/vietnamese)
  const blocks = src.split('/* ').slice(1);
  for (const b of blocks) {
    const subset = b.slice(0, b.indexOf(' */'));
    if (!/^(latin|tamil|telugu|devanagari|malayalam|kannada)$/.test(subset)) continue;
    const url = b.match(/url\((https:[^)]+)\)/)?.[1]; if (!url) continue;
    const name = url.split('/').slice(-2).join('_').replace(/[^a-zA-Z0-9_.-]/g, '');
    if (!fs.existsSync('public/fonts/' + name)) fs.writeFileSync('public/fonts/' + name, Buffer.from(await (await fetch(url, { headers: UA })).arrayBuffer()));
    css += '/* ' + b.replace(url, name);
  }
  console.log(fam);
}
fs.writeFileSync('public/fonts/fonts.css', css);
