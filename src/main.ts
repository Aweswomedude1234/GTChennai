import { urlParams } from './engine/settings';

const canvas = document.getElementById('game') as HTMLCanvasElement;
async function boot() {
  if (urlParams.get('mode') === 'spike') { const { runSpike } = await import('./spike'); await runSpike(canvas); return; }
  const { Game } = await import('./game/game');
  const game = new Game(canvas);
  (window as unknown as { game: unknown }).game = game;
  await game.start();
}
boot().catch((e) => {
  console.error(e);
  const m = document.querySelector('#loading .msg'); if (m) m.textContent = 'Error: ' + (e?.message || e);
});
