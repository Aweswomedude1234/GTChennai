// Day/night cycle tuned to Chennai light (STYLE_BIBLE §Light): harsh white noon haze,
// golden 17:30–18:15 evenings, short dusk, orange-brown light-polluted night sky.
import * as THREE from 'three/webgpu';
import { SkyMesh } from 'three/addons/objects/SkyMesh.js';
import { positionWorldDirection, vec3, mix, smoothstep, uniform, float, hash, floor, step, pow, max } from 'three/tsl';
import { settings } from '../engine/settings';

interface Key { h: number; sun: string; si: number; sky: string; gnd: string; hemi: number; fog: string; fd: number; exp: number }
// fd = fog density (FogExp2), exp = tone-mapping exposure
const KEYS: Key[] = [
  { h: 0, sun: '#8ea2c8', si: 0.12, sky: '#2a3048', gnd: '#2a2018', hemi: 0.5, fog: '#2a2a30', fd: 0.0028, exp: 1.5 },
  { h: 4.8, sun: '#8ea2c8', si: 0.1, sky: '#2a3048', gnd: '#2a2018', hemi: 0.5, fog: '#2e2d34', fd: 0.003, exp: 1.5 },
  { h: 5.7, sun: '#d08a68', si: 0.3, sky: '#5c6684', gnd: '#3a3028', hemi: 0.6, fog: '#76707a', fd: 0.0035, exp: 1.3 },
  { h: 6.4, sun: '#ffa868', si: 1.6, sky: '#9cb0cc', gnd: '#6a5848', hemi: 0.8, fog: '#d6b49c', fd: 0.0032, exp: 1.05 },
  { h: 8.0, sun: '#ffe6c4', si: 2.8, sky: '#a9c2dc', gnd: '#7a6a58', hemi: 0.9, fog: '#cfd2d2', fd: 0.0022, exp: 0.95 },
  { h: 12.0, sun: '#fff8ee', si: 3.6, sky: '#bccfe0', gnd: '#8a7a66', hemi: 1.0, fog: '#d9dad6', fd: 0.0018, exp: 0.85 },
  { h: 15.5, sun: '#ffefd6', si: 3.2, sky: '#b4c8dc', gnd: '#8a7660', hemi: 0.95, fog: '#d8d4cc', fd: 0.0019, exp: 0.9 },
  { h: 17.3, sun: '#ffc27a', si: 2.4, sky: '#a8b8cc', gnd: '#7a6048', hemi: 0.85, fog: '#e2c09a', fd: 0.0022, exp: 0.95 },
  { h: 18.1, sun: '#ff8a48', si: 1.0, sky: '#7a7c98', gnd: '#5a4434', hemi: 0.7, fog: '#b48a78', fd: 0.0026, exp: 1.1 },
  { h: 18.8, sun: '#b06850', si: 0.25, sky: '#454a68', gnd: '#382a22', hemi: 0.55, fog: '#5a4c52', fd: 0.0028, exp: 1.35 },
  { h: 19.8, sun: '#8ea2c8', si: 0.12, sky: '#2a3048', gnd: '#2a2018', hemi: 0.5, fog: '#2c2a30', fd: 0.0028, exp: 1.5 },
  { h: 24, sun: '#8ea2c8', si: 0.12, sky: '#2a3048', gnd: '#2a2018', hemi: 0.5, fog: '#2a2a30', fd: 0.0028, exp: 1.5 },
];

const c1 = new THREE.Color(), c2 = new THREE.Color();
function lerpKey(h: number) {
  let i = 0; while (i < KEYS.length - 2 && KEYS[i + 1].h <= h) i++;
  const a = KEYS[i], b = KEYS[i + 1], t = (h - a.h) / (b.h - a.h || 1);
  const col = (x: string, y: string) => c1.set(x).lerp(c2.set(y), t).clone();
  const n = (x: number, y: number) => x + (y - x) * t;
  return { sun: col(a.sun, b.sun), si: n(a.si, b.si), sky: col(a.sky, b.sky), gnd: col(a.gnd, b.gnd), hemi: n(a.hemi, b.hemi), fog: col(a.fog, b.fog), fd: n(a.fd, b.fd), exp: n(a.exp, b.exp) };
}

export class Sky {
  hour = 17.6;            // game clock, 0..24
  daySpeed = 1 / 60;      // game hours per real second (1 game day = 24 real minutes)
  paused = false;
  readonly sun = new THREE.DirectionalLight(0xffffff, 3);
  readonly hemi = new THREE.HemisphereLight(0xbccfe0, 0x8a7a66, 1);
  readonly sky = new SkyMesh();
  readonly night: THREE.Mesh;
  readonly sunDir = new THREE.Vector3();
  /** 0 = full day, 1 = full night; drives street lights, shop tubes, window glow */
  nightFactor = 0;
  readonly uNight = uniform(0);
  readonly uWet = uniform(0);
  weatherDim = 1;      // multiplied into sun intensity by weather
  weatherFog = 1;      // multiplied into fog density by weather
  private fog = new THREE.FogExp2(0xd9dad6, 0.0018);
  private shadowRange: number;

  constructor(private scene: THREE.Scene) {
    scene.add(this.sun, this.sun.target, this.hemi);
    this.sky.scale.setScalar(4500);
    this.sky.turbidity.value = 6; this.sky.rayleigh.value = 1.6;
    this.sky.mieCoefficient.value = 0.008; this.sky.mieDirectionalG.value = 0.82;
    this.sky.cloudCoverage.value = 0.32; this.sky.cloudDensity.value = 0.35;
    scene.add(this.sky);
    // Night dome: murky blue overhead, sodium-orange city glow on the horizon, sparse stars
    const nm = new THREE.MeshBasicNodeMaterial({ side: THREE.BackSide, transparent: true, depthWrite: false, fog: false });
    const d = positionWorldDirection;
    const up = max(d.y, 0);
    const glow = pow(float(1).sub(up), 6);
    const base = mix(vec3(0.016, 0.02, 0.04), vec3(0.11, 0.065, 0.04), glow);
    const cell = floor(d.mul(420));
    const star = step(0.9975, hash(cell.x.add(cell.y.mul(57)).add(cell.z.mul(113)))).mul(smoothstep(0.15, 0.5, up)).mul(0.6);
    nm.colorNode = base.add(vec3(star));
    nm.opacityNode = this.uNight;
    this.night = new THREE.Mesh(new THREE.SphereGeometry(4400, 24, 12), nm);
    this.night.renderOrder = -1;
    scene.add(this.night);
    scene.fog = this.fog;
    this.shadowRange = settings.quality === 'ultra' ? 110 : 80;
    const sz = settings.quality === 'low' ? 1024 : settings.quality === 'medium' ? 2048 : 4096;
    this.sun.castShadow = settings.shadows;
    this.sun.shadow.mapSize.set(sz, sz);
    const sc = this.sun.shadow.camera;
    sc.left = -this.shadowRange; sc.right = this.shadowRange; sc.top = this.shadowRange; sc.bottom = -this.shadowRange;
    sc.near = 1; sc.far = 600;
    this.sun.shadow.bias = -0.0004; this.sun.shadow.normalBias = 0.04;
  }

  update(dt: number, focus: THREE.Vector3, exposure: { value: number }, renderer: THREE.WebGPURenderer) {
    if (!this.paused) this.hour = (this.hour + dt * this.daySpeed) % 24;
    const h = this.hour;
    // Sun path: rises ~06:05 in the east (+x), sets ~18:15 in the west; Chennai is 13°N so the sun
    // passes close to overhead with a slight southern (+z) tilt.
    const th = ((h - 6.08) / 12.15) * Math.PI;
    this.sunDir.set(Math.cos(th), Math.sin(th), 0.28 * Math.max(0.2, Math.sin(th))).normalize();
    const k = lerpKey(h);
    const below = this.sunDir.y < 0.02;
    const lightDir = below ? this.sunDir.clone().multiplyScalar(-1).setY(Math.abs(this.sunDir.y) + 0.45).normalize() : this.sunDir; // moon
    this.sun.color.copy(k.sun);
    this.sun.intensity = k.si * this.weatherDim;
    const snap = 4; // snap shadow camera to texel grid to avoid shimmering
    const fx = Math.round(focus.x / snap) * snap, fz = Math.round(focus.z / snap) * snap;
    this.sun.position.set(fx + lightDir.x * 300, lightDir.y * 300, fz + lightDir.z * 300);
    this.sun.target.position.set(fx, 0, fz);
    this.hemi.color.copy(k.sky); this.hemi.groundColor.copy(k.gnd); this.hemi.intensity = k.hemi * (0.6 + 0.4 * this.weatherDim);
    this.fog.color.copy(k.fog).multiplyScalar(0.75 + 0.25 * this.weatherDim);
    this.fog.density = k.fd * this.weatherFog;
    exposure.value = k.exp;
    renderer.toneMappingExposure = k.exp;
    this.sky.sunPosition.value.copy(this.sunDir).multiplyScalar(1000);
    this.sky.position.set(focus.x, 0, focus.z);
    this.night.position.set(focus.x, 0, focus.z);
    this.nightFactor = THREE.MathUtils.smoothstep(-this.sunDir.y, -0.08, 0.12);
    this.uNight.value = this.nightFactor;
    (this.scene.background as unknown) = null;
  }
  /** street lights on 18:20–06:00, shop tubes 17:45–22:30 etc. */
  get streetLightsOn() { return this.hour > 18.3 || this.hour < 6.0; }
  formatClock(): string {
    const hh = Math.floor(this.hour), mm = Math.floor((this.hour - hh) * 60);
    return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
  }
}
