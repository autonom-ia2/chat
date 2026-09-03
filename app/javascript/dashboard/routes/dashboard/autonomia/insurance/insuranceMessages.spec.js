import { describe, expect, it } from 'vitest';
import { createI18n } from 'vue-i18n';
import insurance from 'dashboard/i18n/locale/en/insurance.json';

// Em produção o vue-i18n compila cada mensagem na primeira leitura; um "@" ou "|" solto vira
// SyntaxError ("Invalid linked format") e a componente inteira não monta — foi o que apagou a aba
// Conexões em 03/09. Este teste renderiza TODAS as chaves com o parser real.
const leaves = (obj, prefix = '') =>
  Object.entries(obj).flatMap(([key, value]) =>
    typeof value === 'string'
      ? [`${prefix}${key}`]
      : leaves(value, `${prefix}${key}.`)
  );

describe('INSURANCE i18n messages', () => {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: insurance },
    missingWarn: false,
    fallbackWarn: false,
  });

  it.each(leaves(insurance))('compiles %s', key => {
    const rendered = i18n.global.t(key, { count: 3 });
    expect(typeof rendered).toBe('string');
    expect(rendered).not.toBe(key);
    expect(rendered).not.toMatch(/^\s*$/);
  });

  it('keeps the e-mail placeholder readable after escaping @', () => {
    expect(
      i18n.global.t('INSURANCE.CONNECTION.FORM.USERNAME_PLACEHOLDER')
    ).toBe('corretora@exemplo.com.br');
  });
});
