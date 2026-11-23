// Fork (upgrade 4.20.1, #3120): upstream #13856 replaced the per-locale
// index.js files with an eager glob of every JSON merged by a shallow spread.
// The fork keeps its index.js files: each one is a lazy chunk (#803, #1380)
// and they merge namespaces split across files (AUTOMACAO_LIVRE, #2569). This
// spec pins what each catalogue holds, so a future upgrade that swaps the
// loader again fails here instead of dropping keys in silence.
import languagesConfig from '../../../../../config/initializers/languages.rb?raw';
import registry from '../index';
import { loadDashboardLocale } from '../localeLoader';

const jsonFiles = import.meta.glob('../locale/{en,pt_BR,de}/*.json', {
  eager: true,
  import: 'default',
});

// Files present in the folder that the locale index.js never imported. Their
// keys fall back to English; a glob over the folder would load them and change
// the screen. A file leaving or joining this list is a decision, not a merge.
const NOT_LOADED = {
  en: ['webhooks.json'],
  pt_BR: [],
  de: [
    'contentTemplates.json',
    'snooze.json',
    'webhooks.json',
    'yearInReview.json',
  ],
};

const isObject = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

// Reference: every loaded file merged one namespace deep. Exact equality with
// the served catalogue proves no key is lost to a shallow spread.
const referenceCatalogue = locale =>
  Object.entries(jsonFiles)
    .filter(([path]) => path.split('/')[2] === locale)
    .filter(([path]) => !NOT_LOADED[locale].includes(path.split('/').at(-1)))
    .reduce(
      (catalogue, [, file]) =>
        Object.entries(file).reduce(
          (merged, [namespace, value]) => ({
            ...merged,
            [namespace]:
              isObject(value) && isObject(merged[namespace])
                ? { ...merged[namespace], ...value }
                : value,
          }),
          catalogue
        ),
      {}
    );

const enabledLocales = languagesConfig
  .split('\n')
  .filter(line => line.includes('enabled: true'))
  .map(line => line.split("iso_639_1_code: '")[1].split("'")[0]);

// Saved `pt` preferences are served as pt_BR (#881).
const LOCALE_ALIASES = { pt: 'pt_BR' };

describe('dashboard catalogue per locale', () => {
  it.each(Object.keys(NOT_LOADED))(
    'serves %s as the one-namespace-deep merge of its loaded files',
    async locale => {
      const { locale: served, messages } = await loadDashboardLocale(locale);

      expect(served).toBe(locale);
      expect(messages).toEqual(referenceCatalogue(locale));
    }
  );

  it.each(Object.keys(NOT_LOADED))(
    'never loads the files left out of the %s index',
    async locale => {
      const { messages } = await loadDashboardLocale(locale);
      const leftOut = Object.entries(jsonFiles).filter(([path]) =>
        NOT_LOADED[locale].some(name => path.endsWith(`/${locale}/${name}`))
      );

      expect(leftOut.map(([path]) => path.split('/').at(-1)).sort()).toEqual(
        [...NOT_LOADED[locale]].sort()
      );
      leftOut.forEach(([path, file]) => {
        Object.keys(file).forEach(namespace => {
          expect(messages[namespace], `${path} ${namespace}`).toBeUndefined();
        });
      });
    }
  );

  it.each(Object.keys(NOT_LOADED))(
    'keeps the eager registry equal to the lazy %s catalogue',
    async locale => {
      const { messages } = await loadDashboardLocale(locale);

      expect(registry[locale]).toEqual(messages);
    }
  );

  it('serves every locale enabled in the backend from its own catalogue', async () => {
    expect(enabledLocales.length).toBeGreaterThan(40);

    const served = await Promise.all(
      enabledLocales.map(async locale => [
        locale,
        (await loadDashboardLocale(locale)).locale,
      ])
    );

    served.forEach(([locale, servedLocale]) => {
      expect(servedLocale, locale).toBe(LOCALE_ALIASES[locale] || locale);
    });
  });
});
