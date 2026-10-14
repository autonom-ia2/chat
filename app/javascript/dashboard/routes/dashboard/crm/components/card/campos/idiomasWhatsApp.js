// #1423 — os idiomas que o WhatsApp aceita numa mensagem pronta (lista da
// Meta, "Supported languages" dos modelos de mensagem). O código é o que vai
// para o WhatsApp; o nome sai do navegador (Intl.DisplayNames), no idioma da
// tela. Código fora da lista continua valendo pelo "Outro idioma".
export const IDIOMAS_WHATSAPP = [
  'af',
  'sq',
  'ar',
  'ar_EG',
  'ar_AE',
  'ar_LB',
  'ar_MA',
  'ar_QA',
  'az',
  'be_BY',
  'bn',
  'bn_IN',
  'bg',
  'ca',
  'zh_CN',
  'zh_HK',
  'zh_TW',
  'hr',
  'cs',
  'da',
  'prs_AF',
  'nl',
  'nl_BE',
  'en',
  'en_GB',
  'en_US',
  'en_AE',
  'en_AU',
  'en_CA',
  'en_GH',
  'en_IE',
  'en_IN',
  'en_JM',
  'en_MY',
  'en_NZ',
  'en_QA',
  'en_SG',
  'en_UG',
  'en_ZA',
  'et',
  'fil',
  'fi',
  'fr',
  'fr_BE',
  'fr_CA',
  'fr_CH',
  'fr_CI',
  'fr_MA',
  'ka',
  'de',
  'de_AT',
  'de_CH',
  'el',
  'gu',
  'ha',
  'he',
  'hi',
  'hu',
  'id',
  'ga',
  'it',
  'ja',
  'kn',
  'kk',
  'rw_RW',
  'ko',
  'ky_KG',
  'lo',
  'lv',
  'lt',
  'mk',
  'ms',
  'ml',
  'mr',
  'nb',
  'ps_AF',
  'fa',
  'pl',
  'pt_BR',
  'pt_PT',
  'pa',
  'ro',
  'ru',
  'sr',
  'si_LK',
  'sk',
  'sl',
  'es',
  'es_AR',
  'es_CL',
  'es_CO',
  'es_CR',
  'es_DO',
  'es_EC',
  'es_HN',
  'es_MX',
  'es_PA',
  'es_PE',
  'es_ES',
  'es_UY',
  'sw',
  'sv',
  'ta',
  'te',
  'th',
  'tr',
  'uk',
  'ur',
  'uz',
  'vi',
  'zu',
];

// Os que aparecem primeiro na lista.
export const IDIOMAS_MAIS_USADOS = ['pt_BR', 'pt_PT', 'en_US', 'es'];

// O painel guarda o idioma da tela como "pt_BR"; o Intl só aceita "pt-BR".
export const paraBcp47 = codigo => String(codigo).split('_').join('-');

// "pt_BR" → "Português (Brasil)" no idioma da tela. Sem nome conhecido (ou
// código mal formado), devolve vazio: quem chama mostra o código.
export const nomeDoIdioma = (codigo, telaLocale) => {
  const limpo = String(codigo || '').trim();
  if (!limpo) return '';
  try {
    const nomes = new Intl.DisplayNames([paraBcp47(telaLocale || 'en')], {
      type: 'language',
    });
    const nome = nomes.of(paraBcp47(limpo));
    if (!nome || nome === paraBcp47(limpo)) return '';
    const maiuscula = nome
      .charAt(0)
      .toLocaleUpperCase(paraBcp47(telaLocale || 'en'));
    return maiuscula + nome.slice(1);
  } catch {
    return '';
  }
};
