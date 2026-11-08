import { mount } from '@vue/test-utils';

// Cada teste carrega o módulo de novo: o estado (aviso e "já recarregando")
// vive no módulo, como numa página nova depois do reload.
const loadModule = async () => {
  vi.resetModules();
  return import('../staleBundle');
};

const fakeRouter = () => {
  const errorHandlers = [];
  const afterHandlers = [];
  return {
    onError: handler => errorHandlers.push(handler),
    afterEach: handler => afterHandlers.push(handler),
    fail: (error, to) => errorHandlers.forEach(handler => handler(error, to)),
    navigate: failure =>
      afterHandlers.forEach(handler => handler({}, {}, failure)),
  };
};

const preloadError = payload => {
  const event = new Event('vite:preloadError', { cancelable: true });
  event.payload = payload;
  window.dispatchEvent(event);
};

const nextTick = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

const staleError = () => new TypeError('Importing a module script failed.');

describe('staleBundle', () => {
  const reload = vi.fn();
  const assign = vi.fn();
  const originalLocation = window.location;
  const listeners = [];
  const originalAddEventListener = window.addEventListener;

  beforeEach(() => {
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
      expect(isStaleBundleError(staleError())).toBe(true);
      expect(isStaleBundleError(new Error('Request failed with 500'))).toBe(
        false
      );
      expect(isStaleBundleError(undefined)).toBe(false);
    });
  });

  describe('installStaleBundleRecovery', () => {
    it('reloads to the destination when a lazy route fails, even with the notice already shown', async () => {
      const { installStaleBundleRecovery, isPanelOutdated, STALE_RELOAD_KEY } =
        await loadModule();
      const router = fakeRouter();
      installStaleBundleRecovery(router);
      const error = new Error('chunk 404');

      preloadError(error);
      expect(isPanelOutdated.value).toBe(true);
      await nextTick();
      router.fail(error, { fullPath: '/app/accounts/1/inboxes/new/finish' });

      expect(assign).toHaveBeenCalledTimes(1);
      expect(assign).toHaveBeenCalledWith('/app/accounts/1/inboxes/new/finish');
      expect(reload).not.toHaveBeenCalled();
      expect(window.sessionStorage.getItem(STALE_RELOAD_KEY)).toBe('1');
    });

    it('does not reload twice in the same page', async () => {
      const { installStaleBundleRecovery } = await loadModule();
      const router = fakeRouter();
      installStaleBundleRecovery(router);

      router.fail(staleError(), { fullPath: '/app/a' });
      router.fail(staleError(), { fullPath: '/app/b' });

      expect(assign).toHaveBeenCalledTimes(1);
      expect(assign).toHaveBeenCalledWith('/app/a');
    });

    it('shows the notice and does not reload on a preload failure outside navigation', async () => {
      const { installStaleBundleRecovery, isPanelOutdated } =
        await loadModule();
      installStaleBundleRecovery(fakeRouter());

      preloadError(new Error('chunk 404'));
      await nextTick();

      expect(isPanelOutdated.value).toBe(true);
      expect(reload).not.toHaveBeenCalled();
      expect(assign).not.toHaveBeenCalled();
    });

    it('logs navigation errors that are not about loading the dashboard', async () => {
      const { installStaleBundleRecovery, isPanelOutdated } =
        await loadModule();
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});
      const router = fakeRouter();
      installStaleBundleRecovery(router);
      const error = new Error('guard failed');

      router.fail(error, { fullPath: '/app/x' });

      expect(consoleError).toHaveBeenCalledWith(error);
      expect(assign).not.toHaveBeenCalled();
      expect(isPanelOutdated.value).toBe(false);
      consoleError.mockRestore();
    });

    it('shows the notice instead of reloading on a second failure in the same tab session', async () => {
      const first = await loadModule();
      const firstRouter = fakeRouter();
      first.installStaleBundleRecovery(firstRouter);
      firstRouter.fail(staleError(), { fullPath: '/app/x' });

      const afterReload = await loadModule();
      const router = fakeRouter();
      afterReload.installStaleBundleRecovery(router);
      router.fail(staleError(), { fullPath: '/app/x' });

      expect(assign).toHaveBeenCalledTimes(1);
      expect(afterReload.isPanelOutdated.value).toBe(true);
    });

    it('allows a new reload after a successful navigation clears the session flag', async () => {
      const first = await loadModule();
      const firstRouter = fakeRouter();
      first.installStaleBundleRecovery(firstRouter);
      firstRouter.fail(staleError(), { fullPath: '/app/x' });

      const afterReload = await loadModule();
      const router = fakeRouter();
      afterReload.installStaleBundleRecovery(router);
      router.navigate(undefined);
      expect(
        window.sessionStorage.getItem(afterReload.STALE_RELOAD_KEY)
      ).toBeNull();
      router.fail(staleError(), { fullPath: '/app/y' });

      expect(assign).toHaveBeenCalledTimes(2);
      expect(assign).toHaveBeenLastCalledWith('/app/y');
      expect(afterReload.isPanelOutdated.value).toBe(false);
    });

    it('keeps the session flag when the navigation itself failed', async () => {
      const first = await loadModule();
      const router = fakeRouter();
      first.installStaleBundleRecovery(router);
      router.fail(staleError(), { fullPath: '/app/x' });

      router.navigate({ type: 4 });

      expect(window.sessionStorage.getItem(first.STALE_RELOAD_KEY)).toBe('1');
    });

    it('shows the notice when the session cannot be stamped, so it never loops', async () => {
      const { installStaleBundleRecovery, isPanelOutdated } =
        await loadModule();
      const router = fakeRouter();
      installStaleBundleRecovery(router);
      const setItem = vi
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(() => {
          throw new Error('blocked');
        });

      router.fail(staleError(), { fullPath: '/app/a' });

      expect(assign).not.toHaveBeenCalled();
      expect(isPanelOutdated.value).toBe(true);
      setItem.mockRestore();
    });
  });

  describe('StaleBundleBanner', () => {
    it('stays hidden until the dashboard is outdated, then reloads on click', async () => {
      const { isPanelOutdated } = await loadModule();
      const { default: StaleBundleBanner } = await import(
        '../../components/app/StaleBundleBanner.vue'
      );
      // O i18n global dos specs não tem mensagens: aparece a chave.
      const wrapper = mount(StaleBundleBanner);
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
