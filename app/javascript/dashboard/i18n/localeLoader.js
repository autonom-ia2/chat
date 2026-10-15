import {
  camadasDoPacote,
  carregarPacote,
  composeMessages,
} from './pacotesDoPainel';

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

// #1550 — pacote de tradução da conta (payload `autonomia_pacote`). Trocar de
// conta recarrega a página, então basta guardar o nome antes do setLocale.
let pacoteDoPainel = null;
const bases = new Map();
const pacotesInstalados = new WeakMap();

export const definirPacoteDoPainel = nome => {
  pacoteDoPainel = nome || null;
};

// O pacote é composto numa cópia do catálogo e instalado com setLocaleMessage;
// o catálogo base nunca é alterado. Reinstala quando o pacote aplicado muda e
// devolve o base aos outros idiomas que tinham pacote.
export const setDashboardLocale = async (composer, locale) => {
  const request = Symbol();
  localeChanges.set(composer, request);
  const pacote = pacoteDoPainel;

  const { locale: resolvedLocale, messages } = await loadOrReload(locale);
  const overlays = await carregarPacote(
    resolvedLocale,
    camadasDoPacote(pacote)
  );

  if (localeChanges.get(composer) !== request) return;

  bases.set(resolvedLocale, messages);
  const instalados = pacotesInstalados.get(composer) || new Map();
  pacotesInstalados.set(composer, instalados);
  instalados.forEach((nome, outro) => {
    if (outro !== resolvedLocale && nome && bases.has(outro)) {
      composer.setLocaleMessage(outro, bases.get(outro));
      instalados.set(outro, null);
    }
  });

  const aplicado = overlays.length ? pacote : null;
  if (
    !composer.availableLocales.includes(resolvedLocale) ||
    (instalados.get(resolvedLocale) ?? null) !== aplicado
  ) {
    composer.setLocaleMessage(
      resolvedLocale,
      composeMessages(messages, overlays)
    );
    instalados.set(resolvedLocale, aplicado);
  }

  composer.locale.value = resolvedLocale;
};
