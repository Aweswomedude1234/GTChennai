// Deterministic hashing / PRNG helpers shared by main thread and workers.
export function hash32(n: number): number {
  n = (n ^ 61) ^ (n >>> 16); n = Math.imul(n, 9); n ^= n >>> 4; n = Math.imul(n, 0x27d4eb2d); n ^= n >>> 15; return n >>> 0;
}
export function hashf(n: number): number { return hash32(n) / 4294967296; }
export function hash2(a: number, b: number): number { return hashf(Math.imul(a | 0, 73856093) ^ Math.imul(b | 0, 19349663)); }
export type Rng = () => number;
export function mulberry(seed: number): Rng {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
export function pick<T>(r: Rng, arr: readonly T[]): T { return arr[Math.floor(r() * arr.length) % arr.length]; }
export function pickW(r: Rng, weights: readonly number[]): number {
  let t = r() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < weights.length; i++) { t -= weights[i]; if (t <= 0) return i; }
  return weights.length - 1;
}
export function range(r: Rng, a: number, b: number): number { return a + (b - a) * r(); }
