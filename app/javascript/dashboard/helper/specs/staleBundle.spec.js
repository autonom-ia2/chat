import { mount } from '@vue/test-utils';

const NOW = 1_800_000_000_000;

// Cada teste carrega o módulo de novo: o estado (aviso e "já recarregando")
// vive no módulo, como numa página nova depois do reload.
const loadModule = async () => {
  vi.resetModules();
  return import('../staleBundle');
};

const fakeRouter = () => {
  const handlers = [];
  return {
    onError: handler => handlers.push(handler),
    fail: (error, to) => handlers.forEach(handler => handler(error, to)),
  };
};

const preloadError = payload => {
  const event = new Event('vite:preloadError', { cancelable: true });
  event.payload = payload;
  window.dispatchEvent(event);
};

describe('staleBundle', () => {
  const reload = vi.fn();
  const assign = vi.fn();
  const originalLocation = window.location;
  const listeners = [];
  const originalAddEventListener = window.addEventListener;

  beforeEach(() => {
    reload.mockClear();
    assign.mockClear();
    window.sessionStorage.clear();
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { ...originalLocation, reload, assign },
    });
    // Guarda os ouvintes para tirá-los depois; cada teste instala os seus.
    window.addEventListener = (type, handler, options) => {
      listeners.push([type, handler]);
      originalAddEventListener.call(window, type, handler, options);
    };
  });

  afterEach(() => {
    listeners
      .splice(0)
      .forEach(([type, handler]) => window.removeEventListener(type, handler));
    window.addEventListener = originalAddEventListener;
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: originalLocation,
    });
    vi.useRealTimers();
  });

  describe('recoverFromStaleBundle', () => {
    it('reloads once going to the target route and stamps the session', async () => {
      const { recoverFromStaleBundle, isPanelOutdated, STALE_RELOAD_KEY } =
        await loadModule();

      recoverFromStaleBundle('/app/accounts/1/settings/inboxes/new', NOW);

      expect(assign).toHaveBeenCalledWith(
        '/app/accounts/1/settings/inboxes/new'
      );
      expect(reload).not.toHaveBeenCalled();
      expect(window.sessionStorage.getItem(STALE_RELOAD_KEY)).toBe(String(NOW));
      expect(isPanelOutdated.value).toBe(false);
    });

    it('reloads the current page when there is no target route', async () => {
      const { recoverFromStaleBundle } = await loadModule();

      recoverFromStaleBundle(undefined, NOW);

      expect(reload).toHaveBeenCalledTimes(1);
      expect(assign).not.toHaveBeenCalled();
    });

    it('does not reload twice in the same page', async () => {
      const { recoverFromStaleBundle, isPanelOutdated } = await loadModule();

      recoverFromStaleBundle('/app/a', NOW);
      recoverFromStaleBundle('/app/b', NOW);

      expect(assign).toHaveBeenCalledTimes(1);
      expect(isPanelOutdated.value).toBe(false);
    });

    it('shows the notice instead of reloading when it fails again within a minute', async () => {
      const first = await loadModule();
      first.recoverFromStaleBundle('/app/a', NOW);

      const afterReload = await loadModule();
      afterReload.recoverFromStaleBundle('/app/a', NOW + 30 * 1000);

      expect(assign).toHaveBeenCalledTimes(1);
      expect(reload).not.toHaveBeenCalled();
      expect(afterReload.isPanelOutdated.value).toBe(true);
    });

    it('reloads again when the last reload is older than a minute', async () => {
      const first = await loadModule();
      first.recoverFromStaleBundle('/app/a', NOW);

      const later = await loadModule();
      later.recoverFromStaleBundle(
        '/app/a',
        NOW + later.STALE_RELOAD_WINDOW_MS + 1
      );

      expect(assign).toHaveBeenCalledTimes(2);
      expect(later.isPanelOutdated.value).toBe(false);
    });

    it('shows the notice when the session cannot be stamped, so it never loops', async () => {
      const { recoverFromStaleBundle, isPanelOutdated } = await loadModule();
      const setItem = vi
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(() => {
          throw new Error('blocked');
        });

      recoverFromStaleBundle('/app/a', NOW);

      expect(assign).not.toHaveBeenCalled();
      expect(isPanelOutdated.value).toBe(true);
      setItem.mockRestore();
    });
  });

  describe('isStaleBundleError', () => {
    it('recognises failed dynamic imports and ignores other errors', async () => {
      const { isStaleBundleError } = await loadModule();

      expect(
        isStaleBundleError(
          new TypeError(
            'Failed to fetch dynamically imported module: https://x/vite/assets/FinishSetup-BNUw-pmv.js'
          )
        )
      ).toBe(true);
      expect(
        isStaleBundleError(new TypeError('Importing a module script failed.'))
      ).toBe(true);
      expect(isStaleBundleError(new Error('Request failed with 500'))).toBe(
        false
      );
      expect(isStaleBundleError(undefined)).toBe(false);
    });
  });

  describe('installStaleBundleRecovery', () => {
    it('reloads to the destination once when a lazy route fails to load', async () => {
      vi.useFakeTimers();
      const { installStaleBundleRecovery } = await loadModule();
      const router = fakeRouter();
      installStaleBundleRecovery(router);
      const error = new Error('chunk 404');

      preloadError(error);
      router.fail(error, { fullPath: '/app/accounts/1/inboxes/new/finish' });
      vi.runAllTimers();

      expect(assign).toHaveBeenCalledTimes(1);
      expect(assign).toHaveBeenCalledWith('/app/accounts/1/inboxes/new/finish');
      expect(reload).not.toHaveBeenCalled();
    });

    it('reloads the page on a preload failure outside navigation', async () => {
      vi.useFakeTimers();
      const { installStaleBundleRecovery } = await loadModule();
      installStaleBundleRecovery(fakeRouter());

      preloadError(new Error('chunk 404'));
      vi.runAllTimers();

      expect(reload).toHaveBeenCalledTimes(1);
    });

    it('ignores navigation errors that are not about loading the dashboard', async () => {
      const { installStaleBundleRecovery, isPanelOutdated } =
        await loadModule();
      const router = fakeRouter();
      installStaleBundleRecovery(router);

      router.fail(new Error('guard failed'), { fullPath: '/app/x' });

      expect(assign).not.toHaveBeenCalled();
      expect(reload).not.toHaveBeenCalled();
      expect(isPanelOutdated.value).toBe(false);
    });

    it('shows the notice on the second failure after the reload', async () => {
      const first = await loadModule();
      const firstRouter = fakeRouter();
      first.installStaleBundleRecovery(firstRouter);
      firstRouter.fail(new TypeError('Importing a module script failed.'), {
        fullPath: '/app/x',
      });

      const afterReload = await loadModule();
      const router = fakeRouter();
      afterReload.installStaleBundleRecovery(router);
      router.fail(new TypeError('Importing a module script failed.'), {
        fullPath: '/app/x',
      });

      expect(assign).toHaveBeenCalledTimes(1);
      expect(afterReload.isPanelOutdated.value).toBe(true);
    });
  });

  describe('StaleBundleBanner', () => {
    const mountBanner = async () => {
      const { default: StaleBundleBanner } = await import(
        '../../components/app/StaleBundleBanner.vue'
      );
      // O i18n global dos specs não tem mensagens: aparece a chave.
      return mount(StaleBundleBanner);
    };

    it('stays hidden until the dashboard gives up reloading, then reloads on click', async () => {
      const { isPanelOutdated } = await loadModule();
      const wrapper = await mountBanner();
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);

      isPanelOutdated.value = true;
      await wrapper.vm.$nextTick();

      expect(wrapper.text()).toContain(
        'GENERAL_SETTINGS.PANEL_OUTDATED.MESSAGE'
      );
      await wrapper.find('button').trigger('click');
      expect(reload).toHaveBeenCalledTimes(1);
    });
  });
});
