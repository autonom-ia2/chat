// #2202 — apoio dos specs da lista: o `t` do catálogo pt_BR, como a pessoa lê.
import { createI18n } from 'vue-i18n';
import listaPtBR from 'dashboard/i18n/locale/pt_BR/listaDeConversas.json';

export const FUSO = 'America/Sao_Paulo';

export const criarI18n = (extras = {}) =>
  createI18n({
    legacy: false,
    locale: 'pt_BR',
    missingWarn: false,
    fallbackWarn: false,
    messages: { pt_BR: { ...listaPtBR, ...extras } },
  });

export const t = criarI18n().global.t;

// Segundos de uma hora local de São Paulo (UTC-3, sem horário de verão).
export const emSaoPaulo = (ano, mes, dia, hora = 0, minuto = 0) =>
  Date.UTC(ano, mes - 1, dia, hora + 3, minuto) / 1000;
