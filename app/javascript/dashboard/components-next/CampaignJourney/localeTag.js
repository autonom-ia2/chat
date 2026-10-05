// The app's locale names use "_" ("pt_BR"); Intl and toLocale*String need a BCP-47 tag
// ("pt-BR") and throw "Invalid language tag: pt_BR" otherwise (#993, found by #1007). Every
// journey screen that formats a date or a number goes through here.
export const toLocaleTag = locale =>
  String(locale || 'en')
    .split('_')
    .join('-');
