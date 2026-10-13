import { relativeTimeFromISO } from 'shared/helpers/timeHelper';

// #1423 — datas e dinheiro no jeito de falar da casa: "hoje às 15:00",
// "amanhã às 10:00", "sexta, 17 de outubro às 10:00", "há 2 horas", "R$ 1.200".
export const useFormato = ({ t, locale }) => {
  const idioma = () => locale.value.replace('_', '-');
  const comoData = valor => {
    const data = valor instanceof Date ? valor : new Date(valor);
    return Number.isNaN(data.getTime()) ? null : data;
  };
  const hora = data =>
    new Intl.DateTimeFormat(idioma(), {
      hour: '2-digit',
      minute: '2-digit',
    }).format(data);
  const diaPorExtenso = data =>
    new Intl.DateTimeFormat(idioma(), {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    }).format(data);
  const diaCurto = data =>
    new Intl.DateTimeFormat(idioma(), {
      day: 'numeric',
      month: 'long',
      year:
        data.getFullYear() === new Date().getFullYear() ? undefined : 'numeric',
    }).format(data);

  const diferencaEmDias = (data, agora = new Date()) => {
    const a = new Date(data.getFullYear(), data.getMonth(), data.getDate());
    const b = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
    return Math.round((a - b) / 86400000);
  };

  // "hoje", "amanhã", "ontem" ou o dia por extenso.
  const dia = valor => {
    const data = comoData(valor);
    if (!data) return '';
    const dias = diferencaEmDias(data);
    if (dias === 0) return t('CRM_CARD.DATA.HOJE');
    if (dias === 1) return t('CRM_CARD.DATA.AMANHA');
    if (dias === -1) return t('CRM_CARD.DATA.ONTEM');
    return diaPorExtenso(data);
  };
  const quando = valor => {
    const data = comoData(valor);
    if (!data) return t('CRM_CARD.DATA.SEM_DATA');
    return t('CRM_CARD.DATA.DIA_HORA', { dia: dia(data), hora: hora(data) });
  };
  const ha = valor => {
    const data = comoData(valor);
    return data ? relativeTimeFromISO(data.toISOString(), locale.value) : '';
  };
  const dinheiro = (centavos, moeda = 'BRL') =>
    new Intl.NumberFormat(idioma(), {
      style: 'currency',
      currency: moeda || 'BRL',
      maximumFractionDigits: Number(centavos) % 100 ? 2 : 0,
    }).format(Number(centavos || 0) / 100);
  const juntar = nomes =>
    new Intl.ListFormat(idioma(), {
      style: 'long',
      type: 'conjunction',
    }).format(nomes);

  return { dia, quando, hora, ha, dinheiro, juntar, diaCurto, comoData };
};
