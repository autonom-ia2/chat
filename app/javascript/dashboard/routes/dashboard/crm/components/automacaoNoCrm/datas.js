// #2414 F6.3 e #2710 — o dia e a hora curtos das automações no CRM: "15/11" e
// "15/11 às 10h". A hora cheia sai sem os minutos ("10h"); a quebrada, inteira.
const idioma = locale => String(locale || 'pt_BR').replace('_', '-');

const comoData = valor => {
  const data = valor instanceof Date ? valor : new Date(valor);
  return Number.isNaN(data.getTime()) ? null : data;
};

export const diaCurto = (valor, locale) => {
  const data = comoData(valor);
  if (!data) return '';
  return new Intl.DateTimeFormat(idioma(locale), {
    day: '2-digit',
    month: '2-digit',
  }).format(data);
};

export const horaCurta = (valor, { t, locale }) => {
  const data = comoData(valor);
  if (!data) return '';
  if (data.getMinutes() === 0)
    return t('AUTOMACAO_NO_CRM.DATA.HORA_CHEIA', { hora: data.getHours() });
  return new Intl.DateTimeFormat(idioma(locale), {
    hour: '2-digit',
    minute: '2-digit',
  }).format(data);
};

export const diaEHora = (valor, { t, locale }) => {
  if (!comoData(valor)) return '';
  return t('AUTOMACAO_NO_CRM.DATA.DIA_HORA', {
    dia: diaCurto(valor, locale),
    hora: horaCurta(valor, { t, locale }),
  });
};
