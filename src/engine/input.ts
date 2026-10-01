// Keyboard + mouse + gamepad input with remappable actions.
export type Action = 'forward' | 'back' | 'left' | 'right' | 'sprint' | 'jump' | 'enter' | 'camera' | 'horn' | 'handbrake'
  | 'radio' | 'map' | 'phone' | 'attack' | 'aim' | 'crouch' | 'debug' | 'pause' | 'lookBehind' | 'interact';

const DEFAULT_BINDINGS: Record<Action, string[]> = {
  forward: ['KeyW', 'ArrowUp'], back: ['KeyS', 'ArrowDown'], left: ['KeyA', 'ArrowLeft'], right: ['KeyD', 'ArrowRight'],
  sprint: ['ShiftLeft', 'ShiftRight'], jump: ['Space'], enter: ['KeyF'], camera: ['KeyV'], horn: ['KeyH'], handbrake: ['Space'],
  radio: ['KeyR'], map: ['KeyM'], phone: ['KeyP'], attack: ['Mouse0'], aim: ['Mouse2'], crouch: ['KeyC'], debug: ['F3', 'Backquote'],
  pause: ['Escape'], lookBehind: ['KeyB'], interact: ['KeyE'],
};

export class Input {
  bindings: Record<Action, string[]>;
  private down = new Set<string>();
  private pressed = new Set<string>();
  mouseDX = 0; mouseDY = 0; wheel = 0;
  pointerLocked = false;
  /** synthetic overrides used by the harness / autopilot */
  virtual = new Map<Action, number>();

  constructor(private el: HTMLElement) {
    let saved: Record<Action, string[]> | null = null;
    try { saved = JSON.parse(localStorage.getItem('gti.bindings') || 'null'); } catch { /* storage unavailable */ }
    this.bindings = { ...DEFAULT_BINDINGS, ...(saved || {}) };
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Tab' || e.code === 'F3') e.preventDefault();
      if (!this.down.has(e.code)) this.pressed.add(e.code);
      this.down.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.down.delete(e.code));
    window.addEventListener('blur', () => this.down.clear());
    el.addEventListener('mousedown', (e) => { const c = 'Mouse' + e.button; if (!this.down.has(c)) this.pressed.add(c); this.down.add(c); });
    window.addEventListener('mouseup', (e) => this.down.delete('Mouse' + e.button));
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('mousemove', (e) => { if (this.pointerLocked) { this.mouseDX += e.movementX; this.mouseDY += e.movementY; } });
    window.addEventListener('wheel', (e) => { this.wheel += Math.sign(e.deltaY); }, { passive: true });
    document.addEventListener('pointerlockchange', () => { this.pointerLocked = document.pointerLockElement === el; });
  }
  requestLock() { if (!this.pointerLocked) this.el.requestPointerLock?.()?.catch?.(() => {}); }
  private gp(): Gamepad | null { const g = navigator.getGamepads?.(); return g ? g.find((x) => !!x) ?? null : null; }
  /** analog value 0..1 */
  value(a: Action): number {
    const v = this.virtual.get(a); if (v !== undefined) return v;
    if (this.bindings[a].some((c) => this.down.has(c))) return 1;
    const g = this.gp(); if (!g) return 0;
    const ax = g.axes, b = g.buttons;
    switch (a) {
      case 'forward': return Math.max(0, -(ax[1] ?? 0) - 0.15, b[7]?.value ?? 0);
      case 'back': return Math.max(0, (ax[1] ?? 0) - 0.15, b[6]?.value ?? 0);
      case 'left': return Math.max(0, -(ax[0] ?? 0) - 0.15);
      case 'right': return Math.max(0, (ax[0] ?? 0) - 0.15);
      case 'sprint': return b[0]?.pressed ? 1 : 0;
      case 'jump': case 'handbrake': return b[0]?.pressed ? 1 : 0;
      case 'enter': return b[3]?.pressed ? 1 : 0;
      case 'horn': return b[10]?.pressed ? 1 : 0;
      default: return 0;
    }
  }
  held(a: Action) { return this.value(a) > 0.5; }
  justPressed(a: Action) { return this.bindings[a].some((c) => this.pressed.has(c)) || this.virtual.get(a) === 2; }
  gamepadLook(): [number, number] { const g = this.gp(); if (!g) return [0, 0]; const dz = (v: number) => Math.abs(v) < 0.15 ? 0 : v; return [dz(g.axes[2] ?? 0), dz(g.axes[3] ?? 0)]; }
  endFrame() { this.pressed.clear(); this.mouseDX = 0; this.mouseDY = 0; this.wheel = 0; for (const [k, v] of this.virtual) if (v === 2) this.virtual.delete(k); }
  rebind(a: Action, codes: string[]) { this.bindings[a] = codes; try { localStorage.setItem('gti.bindings', JSON.stringify(this.bindings)); } catch { /* ignore */ } }
}
