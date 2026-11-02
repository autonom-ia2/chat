import { ref } from 'vue';

// #2478: uma aba aberta antes de um deploy pede pedaços do painel (chunks do
// Vite) que não existem mais. A navegação falha e a tela parece não fazer
// nada. Recarregar traz o painel novo; o carimbo na sessão impede o laço.
export const STALE_RELOAD_KEY = 'dashboard:stale-bundle-reloaded-at';
export const STALE_RELOAD_WINDOW_MS = 60 * 1000;

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

const readLastReload = () => {
  try {
    return Number(window.sessionStorage.getItem(STALE_RELOAD_KEY)) || 0;
  } catch {
    return 0;
  }
};

const saveReload = now => {
  try {
    window.sessionStorage.setItem(STALE_RELOAD_KEY, String(now));
    return true;
  } catch {
    return false;
  }
};

export const isStaleBundleError = error => {
  if (!error || typeof error !== 'object') return false;
  if (preloadErrors.has(error)) return true;
  const message = String(error.message || '');
  return FAILED_IMPORT_MESSAGES.some(text => message.includes(text));
};

// Recarrega uma vez (indo para `target`, quando é uma navegação). Se já
// recarregou há menos de um minuto, ou se não há como guardar o carimbo,
// mostra o aviso em vez de recarregar de novo.
export const recoverFromStaleBundle = (target, now = Date.now()) => {
  if (isReloading || isPanelOutdated.value) return;

  const lastReload = readLastReload();
  const reloadedRecently =
    lastReload && now - lastReload < STALE_RELOAD_WINDOW_MS;
  if (reloadedRecently || !saveReload(now)) {
    isPanelOutdated.value = true;
    return;
  }

  isReloading = true;
  if (target) {
    window.location.assign(target);
  } else {
    window.location.reload();
  }
};

export const installStaleBundleRecovery = router => {
  window.addEventListener('vite:preloadError', event => {
    if (event.payload && typeof event.payload === 'object') {
      preloadErrors.add(event.payload);
    }
    // Dá a vez ao router.onError, que recarrega já na rota de destino.
    setTimeout(() => recoverFromStaleBundle(), 0);
  });

  router.onError((error, to) => {
    if (isStaleBundleError(error)) recoverFromStaleBundle(to?.fullPath);
  });
};
