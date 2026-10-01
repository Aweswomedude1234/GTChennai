// Renderer bootstrap: WebGPU first, automatic WebGL2 fallback, TSL post-processing chain.
import * as THREE from 'three/webgpu';
import { pass, mrt, output, normalView, packNormalToRGB, unpackRGBToNormal, vec4, float, uniform, sample, renderOutput } from 'three/tsl';
import { fxaa } from 'three/addons/tsl/display/FXAANode.js';
import { ao } from 'three/addons/tsl/display/GTAONode.js';
import { bloom } from 'three/addons/tsl/display/BloomNode.js';
import { settings, urlParams } from './settings';

export interface RenderCtx {
  renderer: THREE.WebGPURenderer;
  pipeline: THREE.RenderPipeline | null;
  backend: 'webgpu' | 'webgl2';
  exposure: { value: number };
  bloomStrength: { value: number };
  aoIntensity: { value: number };
  render: () => void;
  resize: () => void;
}

export async function createRenderer(canvas: HTMLCanvasElement, scene: THREE.Scene, camera: THREE.PerspectiveCamera): Promise<RenderCtx> {
  const forceWebGL = urlParams.get('backend') === 'webgl' || !('gpu' in navigator);
  const usePost = urlParams.get('post') !== '0' && (settings.ssao || settings.bloom);
  // With post-processing the scene pass is single-sampled and FXAA runs at the end.
  let renderer = new THREE.WebGPURenderer({ canvas, antialias: !usePost && settings.quality !== 'low', forceWebGL, powerPreference: 'high-performance', alpha: false });
  try { await renderer.init(); } catch (e) {
    console.warn('WebGPU init failed, falling back to WebGL2', e);
    renderer.dispose();
    renderer = new THREE.WebGPURenderer({ canvas, antialias: true, forceWebGL: true });
    await renderer.init();
  }
  const backend = (renderer.backend as unknown as { isWebGPUBackend?: boolean }).isWebGPUBackend ? 'webgpu' : 'webgl2';
  renderer.toneMapping = THREE.AgXToneMapping;
  renderer.toneMappingExposure = 1;
  renderer.shadowMap.enabled = settings.shadows;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.info.autoReset = false;

  const exposure = uniform(1.0);
  const bloomStrength = uniform(0.25);
  const aoIntensity = uniform(1.0);
  let pipeline: THREE.RenderPipeline | null = null;
  if (usePost) {
    pipeline = new THREE.RenderPipeline(renderer);
    const scenePass = pass(scene, camera);
    let col = scenePass.getTextureNode('output') as unknown as THREE.Node;
    if (settings.ssao) {
      scenePass.setMRT(mrt({ output, normal: packNormalToRGB(normalView) }));
      const depth = scenePass.getTextureNode('depth');
      const normalTex = scenePass.getTextureNode('normal');
      const normal = sample((uv) => unpackRGBToNormal(normalTex.sample(uv)));
      const aoPass = ao(depth, normal, camera);
      aoPass.resolutionScale = 0.5;
      aoPass.radius.value = 0.6;
      const aoV = aoPass.getTextureNode().r;
      const c = scenePass.getTextureNode('output');
      col = vec4(c.rgb.mul(float(1).sub(float(1).sub(aoV).mul(aoIntensity))), c.a) as unknown as THREE.Node;
    }
    if (settings.bloom) {
      const b = bloom(col as never, 0.25, 0.35, 0.85);
      b.strength = bloomStrength as never;
      col = (col as unknown as { add: (n: unknown) => THREE.Node }).add(b);
    }
    pipeline.outputColorTransform = false;
    pipeline.outputNode = fxaa(renderOutput(col as never)) as never;
  }

  const resize = () => {
    const w = canvas.clientWidth || window.innerWidth, h = canvas.clientHeight || window.innerHeight;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2) * settings.renderScale);
    renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.updateProjectionMatrix();
  };
  resize();
  window.addEventListener('resize', resize);
  return {
    renderer, pipeline, backend, exposure, bloomStrength, aoIntensity, resize,
    render: () => { renderer.info.reset(); if (pipeline) pipeline.render(); else renderer.render(scene, camera); },
  };
}
