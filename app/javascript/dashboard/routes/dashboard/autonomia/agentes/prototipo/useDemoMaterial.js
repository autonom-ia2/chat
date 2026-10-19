import { useRoute } from 'vue-router';

// #1426/#1427 — o mockup do material só liga no painel de desenvolvimento e com `?demo=material` na
// URL da página do agente. No build de produção `import.meta.env.DEV` é falso: a página fica igual
// à main, mesmo com o parâmetro.
export const DEMO_MATERIAL = 'material';

export function useDemoMaterial() {
  if (!import.meta.env.DEV) return false;
  return useRoute()?.query?.demo === DEMO_MATERIAL;
}
