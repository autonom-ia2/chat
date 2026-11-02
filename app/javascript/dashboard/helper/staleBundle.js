import { ref } from 'vue';

// #2478: uma aba aberta antes de um deploy pede pedaços do painel (chunks do
// Vite) que não existem mais. A navegação falha e a tela parece não fazer
// nada. Na navegação, recarregar já na rota de destino traz o painel novo.
// Fora da navegação a página não recarrega sozinha (perderia o que a pessoa
// digitou): só aparece o aviso para ela recarregar quando quiser.
//
// Mesma regra do localeLoader (#1380): uma recarga automática por sessão da
// aba, liberada de novo quando uma navegação dá certo. A marca é separada da
// do idioma: o idioma carrega no início de toda página e apagaria esta marca
// logo depois da recarga, abrindo caminho para um laço.
export const STALE_RELOAD_KEY = 'dashboard:stale-bundle-reloaded';

// Texto do erro de import() dinâmico em Chrome, Safari e Firefox. Só para
// falhas que não passaram pelo evento `vite:preloadError`.
const FAILED_IMPORT_MESSAGES = [
  'Failed to fetch dynamically imported module',
  'Importing a module script failed',
  'error loading dynamically imported module',
];

export const isPanelOutdated = ref(false);

const preloadErrors = new WeakSet();
let isReloading = false;

// true quando a marca foi gravada agora; false se já existia ou se não há
// como gravar (sem marca não há como evitar o laço).
const claimReload = () => {
  try {
    if (window.sessionStorage.getItem(STALE_RELOAD_KEY)) return false;
    window.sessionStorage.setItem(STALE_RELOAD_KEY, '1');
    return true;
  } catch {
    return false;
  }
};

const forgetReload = () => {
  try {
    window.sessionStorage.removeItem(STALE_RELOAD_KEY);
  } catch {
    // Sem storage a marca nunca existiu.
  }
};

export const isStaleBundleError = error => {
  if (!error || typeof error !== 'object') return false;
  if (preloadErrors.has(error)) return true;
  const message = String(error.message || '');
  return FAILED_IMPORT_MESSAGES.some(text => message.includes(text));
};

// Navegação que falhou por pedaço velho: recarrega uma vez indo para o
// destino; se já recarregou nesta sessão, fica o aviso.
export const reloadToRoute = target => {
  if (isReloading) return;
  if (!claimReload()) {
    isPanelOutdated.value = true;
    return;
  }
  isReloading = true;
  window.location.assign(target);
};

export const installStaleBundleRecovery = router => {
  window.addEventListener('vite:preloadError', event => {
    if (event.payload && typeof event.payload === 'object') {
      preloadErrors.add(event.payload);
    }
    isPanelOutdated.value = true;
  });

  router.onError((error, to) => {
    if (!isStaleBundleError(error)) {
      // Com um onError registrado o vue-router não loga mais o erro.
      // eslint-disable-next-line no-console
      console.error(error);
      return;
    }
    reloadToRoute(to.fullPath);
  });

  router.afterEach((_to, _from, failure) => {
    if (!failure) forgetReload();
  });
};
