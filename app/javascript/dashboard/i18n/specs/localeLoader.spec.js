import { createApp, h, nextTick } from 'vue';
import { createI18n, useI18n } from 'vue-i18n';
import {
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
});
