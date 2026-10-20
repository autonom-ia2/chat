import parsePhoneNumber from 'libphonenumber-js';
import { intlLocale } from '../metaAdsHelpers';

// Anúncios sem login (#1960, degrau 0): o resultado sai do WhatsApp (de qual anúncio veio cada
// conversa), sem conta de anúncios conectada. Formatos e regras pequenas: a tela "pronto" e as pessoas do
// anúncio (MetaAdsAdDetail).

export const SEM_LOGIN = 'CRM_KANBAN.META_ADS_HUB.SEM_LOGIN';

// Telefone como a pessoa fala: "(11) 98888-7777" no Brasil, internacional fora dele.
export const phoneLabel = phone => {
  if (!phone) return null;
  const parsed = parsePhoneNumber(String(phone));
  if (!parsed) return String(phone);
  return parsed.country === 'BR'
    ? parsed.formatNational()
    : parsed.formatInternational();
};

// "12/10", no fuso da conta; null sem data válida.
export const dayMonth = (value, timeZone, locale) => {
  const date = new Date(value || '');
  if (!value || Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat(intlLocale(locale), {
    day: '2-digit',
    month: '2-digit',
    timeZone,
  }).format(date);
};

// Situação de quem veio do anúncio: venda e perda marcadas no card valem primeiro; depois, quem
// ainda espera resposta; o resto está conversando.
export const situation = person => {
  if (person?.status === 'won') return 'BOUGHT';
  if (person?.status === 'lost') return 'LOST';
  if (person?.answered === false) return 'NO_ANSWER';
  return 'TALKING';
};

export const SITUATION_CLASSES = {
  BOUGHT: 'bg-n-teal-3 text-n-teal-11',
  LOST: 'bg-n-alpha-2 text-n-slate-11',
  NO_ANSWER: 'bg-n-amber-3 text-n-amber-11',
  TALKING: 'bg-n-blue-3 text-n-blue-11',
};
