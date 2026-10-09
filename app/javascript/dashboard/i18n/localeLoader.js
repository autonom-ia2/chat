import { toLocaleTag } from '../helper/localeTag';

const DEFAULT_LOCALE = 'en';
// The legacy European Portuguese catalogue is mostly untranslated English, so
// preferences saved as `pt` are served in Brazilian Portuguese (issue #881).
const LOCALE_ALIASES = { pt: 'pt_BR' };
const localeLoaders = import.meta.glob('./locale/*/index.js');
const localeChanges = new WeakMap();

const normalizeLocale = locale => {
  const normalizedLocale = String(locale || DEFAULT_LOCALE).replace('-', '_');
  return LOCALE_ALIASES[normalizedLocale] || normalizedLocale;
};

const localePath = locale => `./locale/${normalizeLocale(locale)}/index.js`;

const resolveLocale = locale => {
  const normalizedLocale = normalizeLocale(locale);
  return localeLoaders[localePath(normalizedLocale)]
    ? normalizedLocale
    : DEFAULT_LOCALE;
};

export const loadDashboardLocale = async locale => {
  const resolvedLocale = resolveLocale(locale);
  const localeModule = await localeLoaders[localePath(resolvedLocale)]();

  return {
    locale: resolvedLocale,
    messages: localeModule.default || localeModule,
  };
};

export const buildDashboardI18nMessages = async locale => {
  const fallbackLocale = await loadDashboardLocale(DEFAULT_LOCALE);
  const currentLocale =
    resolveLocale(locale) === DEFAULT_LOCALE
      ? fallbackLocale
      : await loadDashboardLocale(locale);

  return {
    locale: currentLocale.locale,
    fallbackLocale: fallbackLocale.locale,
    messages: {
      [fallbackLocale.locale]: fallbackLocale.messages,
      [currentLocale.locale]: currentLocale.messages,
    },
  };
};

export const setDashboardLocale = async (composer, locale) => {
  const request = Symbol();
  localeChanges.set(composer, request);

  const { locale: resolvedLocale, messages } =
    await loadDashboardLocale(locale);

  if (localeChanges.get(composer) !== request) return;

  if (!composer.availableLocales.includes(resolvedLocale)) {
    composer.setLocaleMessage(resolvedLocale, messages);
  }

  composer.locale.value = resolvedLocale;
  document.documentElement.lang = toLocaleTag(resolvedLocale);
};
