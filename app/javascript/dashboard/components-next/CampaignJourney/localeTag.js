// The app's locale names use "_" ("pt_BR"); Intl and toLocale*String need a BCP-47 tag
// ("pt-BR") and throw "Invalid language tag: pt_BR" otherwise (#993, found by #1007). Every
// journey screen that formats a date or a number goes through here.
export const toLocaleTag = locale =>
  String(locale || 'en')
    .split('_')
    .join('-');

// Counts in the journey screens. vue-i18n's n() hands the raw "pt_BR" to Intl.NumberFormat
// and throws on the Brazilian account, so every count is formatted here.
export const formatNumber = (value, locale) =>
  new Intl.NumberFormat(toLocaleTag(locale)).format(Number(value || 0));
