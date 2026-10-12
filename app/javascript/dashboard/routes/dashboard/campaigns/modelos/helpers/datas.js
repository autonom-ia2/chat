// Datas em linguagem de gente: "há 12 minutos", "16:40", "10/11".
const MINUTO_MS = 60 * 1000;
const HORA_MS = 60 * MINUTO_MS;
const DIA_MS = 24 * HORA_MS;

// 'pt_BR' (vue-i18n) → 'pt-BR' (Intl).
export const localeDoIntl = locale => (locale || 'en').split('_').join('-');

export const haQuantoTempo = (iso, locale) => {
  const formato = new Intl.RelativeTimeFormat(localeDoIntl(locale), {
    numeric: 'auto',
  });
  const diferenca = new Date(iso).getTime() - Date.now();
  const distancia = Math.abs(diferenca);
  if (distancia < HORA_MS) {
    return formato.format(Math.round(diferenca / MINUTO_MS), 'minute');
  }
  if (distancia < DIA_MS) {
    return formato.format(Math.round(diferenca / HORA_MS), 'hour');
  }
  return formato.format(Math.round(diferenca / DIA_MS), 'day');
};

export const hora = (iso, locale) =>
  new Date(iso).toLocaleTimeString(localeDoIntl(locale), {
    hour: '2-digit',
    minute: '2-digit',
  });

export const diaEMes = (iso, locale) =>
  new Date(iso).toLocaleDateString(localeDoIntl(locale), {
    day: '2-digit',
    month: '2-digit',
  });

export const numero = (valor, locale) =>
  new Intl.NumberFormat(localeDoIntl(locale)).format(valor);
