export const TRANSLATION_PROVIDERS = {
  CAPTAIN: 'captain',
  GOOGLE: 'google_translate',
};

// Fork (upgrade 4.19.1, #3119): with no provider saved it is Google Translate, as on the server
// (`Enterprise::Account#translation_service`). Captain only when the account picks it.
export const translationProvider = settings =>
  settings?.translation_provider || TRANSLATION_PROVIDERS.GOOGLE;
