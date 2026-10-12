import { createApp, h, nextTick } from 'vue';
import { createI18n, useI18n } from 'vue-i18n';
import {
  RELOAD_FLAG,
  buildDashboardI18nMessages,
  setDashboardLocale,
} from '../localeLoader';

const delayedFrench = vi.hoisted(() => {
  let release;
  const waiting = new Promise(resolve => {
    release = resolve;
  });
  return { waiting, release };
});

vi.mock('../locale/fr/index.js', async importOriginal => {
  await delayedFrench.waiting;
  return importOriginal();
});

// Fork (#1380): a catalogue whose download fails (the browser then keeps the
// failure for the whole page).
vi.mock('../locale/ja/index.js', () => {
  throw new Error('Failed to fetch dynamically imported module');
});

describe('dashboard language catalogue loading', () => {
  // The legacy European Portuguese catalogue is mostly English copies, so a
  // profile or account saved as `pt` must show Brazilian Portuguese instead.
  it.each(['en', 'pt'])(
    'shows Brazilian Portuguese for a pt preference after a %s bootstrap',
    async bootstrapLanguage => {
      const i18n = createI18n({
        legacy: false,
        ...(await buildDashboardI18nMessages(bootstrapLanguage)),
      });
      await setDashboardLocale(i18n.global, 'pt');
      expect(i18n.global.locale.value).toBe('pt_BR');
      expect(i18n.global.availableLocales).not.toContain('pt');
      expect(i18n.global.t('CANNED_MGMT.SEARCH_PLACEHOLDER')).toBe(
        'Pesquisar respostas prontas...'
      );
      expect(i18n.global.t('DATA_IMPORTS.HEADER')).toBe('Dados');
      expect(i18n.global.t('RELATIONSHIPS.TITLE')).toBe('Relacionamentos');
    }
  );

  it('bootstraps a pt preference straight into Brazilian Portuguese', async () => {
    const { locale, messages } = await buildDashboardI18nMessages('pt');
    expect(locale).toBe('pt_BR');
    expect(Object.keys(messages)).toEqual(['en', 'pt_BR']);
  });

  it.each(['pt_BR', 'es'])(
    'renders %s after an English-only bootstrap with the real global composer',
    async language => {
      const i18n = createI18n({
        legacy: false,
        ...(await buildDashboardI18nMessages('en')),
      });
      const root = document.createElement('div');
      const app = createApp({
        setup() {
          const composer = useI18n({ useScope: 'global' });
          return { composer };
        },
        render() {
          return h('p', this.composer.t('PROFILE_SETTINGS.TITLE'));
        },
      });
      app.use(i18n);
      const instance = app.mount(root);
      try {
        expect(i18n.global.availableLocales).toEqual(['en']);
        // In composition mode the injected facade cannot register messages.
        expect(instance.$i18n.setLocaleMessage).toBeUndefined();
        await setDashboardLocale(instance.composer, language);
        await nextTick();
        expect(i18n.global.locale.value).toBe(language);
        expect(i18n.global.availableLocales).toContain(language);
        expect(root.textContent).toBe(
          i18n.global.getLocaleMessage(language).PROFILE_SETTINGS.TITLE
        );
        expect(root.textContent).not.toBe(
          i18n.global.getLocaleMessage('en').PROFILE_SETTINGS.TITLE
        );
      } finally {
        app.unmount();
      }
    }
  );

  it('keeps the latest choice when an earlier catalogue arrives afterwards', async () => {
    const i18n = createI18n({
      legacy: false,
      ...(await buildDashboardI18nMessages('en')),
    });
    const earlierChoice = setDashboardLocale(i18n.global, 'fr');
    await setDashboardLocale(i18n.global, 'en');
    delayedFrench.release();
    await earlierChoice;
    expect(i18n.global.locale.value).toBe('en');
    expect(i18n.global.t('PROFILE_SETTINGS.TITLE')).toBe('Profile Settings');
  });

  describe('when the catalogue download fails', () => {
    const reload = vi.fn();
    const originalLocation = window.location;

    beforeEach(() => {
      reload.mockClear();
      window.sessionStorage.clear();
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: { ...originalLocation, reload },
      });
    });

    afterEach(() => {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    });

    it('reloads the page once, and a second failure keeps English without a loop', async () => {
      const i18n = createI18n({
        legacy: false,
        ...(await buildDashboardI18nMessages('en')),
      });

      const pending = setDashboardLocale(i18n.global, 'ja');
      await new Promise(resolve => {
        setTimeout(resolve, 0);
      });
      expect(reload).toHaveBeenCalledTimes(1);
      expect(window.sessionStorage.getItem(RELOAD_FLAG)).toBe('1');
      expect(pending).toBeInstanceOf(Promise);

      await expect(setDashboardLocale(i18n.global, 'ja')).rejects.toThrow();
      expect(reload).toHaveBeenCalledTimes(1);
      expect(i18n.global.locale.value).toBe('en');
    });

    it('boots in English instead of a blank page when the reload already happened', async () => {
      window.sessionStorage.setItem(RELOAD_FLAG, '1');
      const { locale } = await buildDashboardI18nMessages('ja');
      expect(locale).toBe('en');
      expect(reload).not.toHaveBeenCalled();
    });

    it('forgets the reload after a catalogue loads', async () => {
      window.sessionStorage.setItem(RELOAD_FLAG, '1');
      await buildDashboardI18nMessages('pt_BR');
      expect(window.sessionStorage.getItem(RELOAD_FLAG)).toBeNull();
    });
  });
});
