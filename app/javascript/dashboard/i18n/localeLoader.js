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

// Fork (#1380): the catalogue is a separate download. When it fails (a network
// blip, a deploy swapping chunks), the browser keeps the failed module for the
// whole page, so trying import() again in the same page fetches nothing and the
// screen stayed in English. The page is reloaded once instead (a new page asks
// for the file again); a second failure in the same session keeps English, so
// it never loops. Verified in Chrome with the first download answering 500.
export const RELOAD_FLAG = 'dashboard:locale-reloaded';
const reloadOnce = () => {
  try {
    if (window.sessionStorage.getItem(RELOAD_FLAG)) return false;
    window.sessionStorage.setItem(RELOAD_FLAG, '1');
  } catch {
    return false;
  }
  window.location.reload();
  return true;
};
const forgetReload = () => {
  try {
    window.sessionStorage.removeItem(RELOAD_FLAG);
  } catch {
    // Without storage the flag never existed.
  }
};
// Resolves with the catalogue; on failure reloads the page once (and never
// resolves, the page is going away) or rejects.
const loadOrReload = async locale => {
  try {
    const loaded = await loadDashboardLocale(locale);
    forgetReload();
    return loaded;
  } catch (error) {
    if (reloadOnce()) return new Promise(() => {});
    throw error;
  }
};

export const buildDashboardI18nMessages = async locale => {
  const fallbackLocale = await loadDashboardLocale(DEFAULT_LOCALE);
  // Fork: a failed catalogue keeps the dashboard in English instead of blank.
  const currentLocale =
    resolveLocale(locale) === DEFAULT_LOCALE
      ? fallbackLocale
      : await loadOrReload(locale).catch(() => fallbackLocale);

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

  const { locale: resolvedLocale, messages } = await loadOrReload(locale);

  if (localeChanges.get(composer) !== request) return;

  if (!composer.availableLocales.includes(resolvedLocale)) {
    composer.setLocaleMessage(resolvedLocale, messages);
  }

  composer.locale.value = resolvedLocale;
};
