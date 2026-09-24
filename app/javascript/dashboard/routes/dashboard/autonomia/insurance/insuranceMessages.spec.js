import { describe, expect, it } from 'vitest';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/insurance.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/insurance.json';

// Em produção o vue-i18n compila cada mensagem na primeira leitura; um "@" ou "|" solto vira
// SyntaxError ("Invalid linked format") e a componente inteira não monta — foi o que apagou a aba
// Conexões em 03/09. Este teste renderiza TODAS as chaves com o parser real, nos dois idiomas.
const leaves = (obj, prefix = '') =>
  Object.entries(obj).flatMap(([key, value]) =>
    typeof value === 'string'
      ? [`${prefix}${key}`]
      : leaves(value, `${prefix}${key}.`)
  );

const LOCALES = { en, pt_BR: ptBR };

describe.each(Object.keys(LOCALES))('INSURANCE i18n messages (%s)', locale => {
  const messages = LOCALES[locale];
  const i18n = createI18n({
    legacy: false,
    locale,
    messages: { [locale]: messages },
    missingWarn: false,
    fallbackWarn: false,
  });

  it.each(leaves(messages))('compiles %s', key => {
    const rendered = i18n.global.t(key, {
      count: 3,
      installationName: 'Hub2You',
    });
    expect(typeof rendered).toBe('string');
    expect(rendered).not.toBe(key);
    expect(rendered).not.toMatch(/^\s*$/);
  });

  it('keeps the e-mail placeholder readable after escaping @', () => {
    expect(
      i18n.global.t('INSURANCE.CONNECTION.FORM.USERNAME_PLACEHOLDER')
    ).toBe('corretora@exemplo.com.br');
  });

  // Hub2You numa stack, Autonomia na outra: marca escrita no texto aparece errada numa delas.
  it('never writes a brand name, only the installation name', () => {
    leaves(messages).forEach(key => {
      const rendered = i18n.global.t(key, {
        count: 3,
        installationName: 'Hub2You',
      });
      expect(rendered, key).not.toContain('Autonom');
    });
    [
      'INSURANCE.CONNECTION.ENCRYPTION_UNAVAILABLE',
      'INSURANCE.CONNECTION.FAILURES.INTEGRATION_OUTDATED',
      'INSURANCE.CONNECTION.FAILURES.MISCONFIGURED',
      'INSURANCE.CONNECTION.LAYERS.RUNTIME',
      'INSURANCE.CAPABILITIES.FOOTER',
      'INSURANCE.AGENT.DESCRIPTION',
      'INSURANCE.AGENT.LOCKED_NOTE',
    ].forEach(key =>
      expect(
        i18n.global.t(key, { installationName: 'Hub2You' }),
        key
      ).toContain('Hub2You')
    );
  });
});

describe('INSURANCE locales', () => {
  it('pt_BR and en have the same keys', () => {
    expect(leaves(ptBR).sort()).toEqual(leaves(en).sort());
  });

  it('en is in English, not a copy of pt_BR', () => {
    expect(en.INSURANCE.TABS.CONNECTIONS).not.toBe(
      ptBR.INSURANCE.TABS.CONNECTIONS
    );
  });
});
