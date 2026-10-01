const DEFAULT_LOCALE = 'en';
const PORTUGUESE_FALLBACK_LOCALE = 'pt_BR';
const localeLoaders = import.meta.glob('./locale/*/index.js');
const localeChanges = new WeakMap();

const normalizeLocale = locale =>
  String(locale || DEFAULT_LOCALE).replace('-', '_');

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
  const portugueseFallback =
    currentLocale.locale === 'pt'
      ? await loadDashboardLocale(PORTUGUESE_FALLBACK_LOCALE)
      : null;

  return {
    locale: currentLocale.locale,
    fallbackLocale: {
      pt: [PORTUGUESE_FALLBACK_LOCALE, DEFAULT_LOCALE],
      default: [DEFAULT_LOCALE],
    },
    messages: {
      [fallbackLocale.locale]: fallbackLocale.messages,
      [currentLocale.locale]: currentLocale.messages,
      ...(portugueseFallback && {
        [portugueseFallback.locale]: portugueseFallback.messages,
      }),
    },
  };
};

export const setDashboardLocale = async (composer, locale) => {
  const request = Symbol();
  localeChanges.set(composer, request);

  const { locale: resolvedLocale, messages } =
    await loadDashboardLocale(locale);
  const portugueseFallback =
    resolvedLocale === 'pt'
      ? await loadDashboardLocale(PORTUGUESE_FALLBACK_LOCALE)
      : null;

  if (localeChanges.get(composer) !== request) return;

  if (
    portugueseFallback &&
    !composer.availableLocales.includes(portugueseFallback.locale)
  ) {
    composer.setLocaleMessage(
      portugueseFallback.locale,
      portugueseFallback.messages
    );
  }

  if (!composer.availableLocales.includes(resolvedLocale)) {
    composer.setLocaleMessage(resolvedLocale, messages);
  }

  composer.locale.value = resolvedLocale;
};
