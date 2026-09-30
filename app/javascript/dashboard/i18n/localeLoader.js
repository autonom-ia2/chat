const DEFAULT_LOCALE = 'en';
const localeLoaders = import.meta.glob('./locale/*/index.js');

const normalizeLocale = locale =>
  String(locale || DEFAULT_LOCALE).replace('-', '_');

const localePath = locale => `./locale/${normalizeLocale(locale)}/index.js`;

const resolveLocale = locale => {
  const normalizedLocale = normalizeLocale(locale);
  return localeLoaders[localePath(normalizedLocale)]
    ? normalizedLocale
    : DEFAULT_LOCALE;
};

const i18nTarget = i18n => i18n?.global || i18n;

const assignLocale = (target, locale) => {
  if (target?.locale && typeof target.locale === 'object') {
    target.locale.value = locale;
    return;
  }

  target.locale = locale;
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

export const setDashboardLocale = async (i18n, locale) => {
  if (!locale) return;

  const target = i18nTarget(i18n);
  if (!target) return;

  const { locale: resolvedLocale, messages } =
    await loadDashboardLocale(locale);

  if (
    target.setLocaleMessage &&
    !target.availableLocales?.includes?.(resolvedLocale)
  ) {
    target.setLocaleMessage(resolvedLocale, messages);
  }

  assignLocale(target, resolvedLocale);
};
