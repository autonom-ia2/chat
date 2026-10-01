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
  it.each(['en', 'pt'])(
    'fills missing Portuguese strings in Brazilian Portuguese after a %s bootstrap',
    async bootstrapLanguage => {
      const i18n = createI18n({
        legacy: false,
        ...(await buildDashboardI18nMessages(bootstrapLanguage)),
      });
      await setDashboardLocale(i18n.global, 'pt');
      expect(i18n.global.locale.value).toBe('pt');
      expect(i18n.global.t('PROFILE_SETTINGS.TITLE')).toBe(
        i18n.global.getLocaleMessage('pt').PROFILE_SETTINGS.TITLE
      );
      expect(i18n.global.t('RELATIONSHIPS.TITLE')).toBe('Relacionamentos');
      expect(i18n.global.t('CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.FULL_VIEW')).toBe(
        'Visão completa'
      );
    }
  );
  it.each(['pt_BR', 'pt', 'es'])(
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
