// #3099 — a hora das duas versões ("hoje, às 16:30", "amanhã, às 09:00", "em 25 de novembro, às 02:07") sempre no
// fuso da conta (fusoDaConta: o de Configurações, nunca o do aparelho). Serve ao Resultado da campanha, ao histórico
// da automação e ao aviso da lista de Campanhas.
import { computed, getCurrentInstance } from 'vue';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { toLocaleTag } from 'dashboard/components-next/CampaignJourney/localeTag';

const UM_DIA = 24 * 60 * 60 * 1000;
const NS = 'DUAS_VERSOES.QUANDO';

// O dia no fuso, para comparar ("2026-11-24").
const diaNoFuso = (data, fuso) =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: fuso,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(data);

export const quandoFalado = (
  epoch,
  { fuso, locale, t, agora = Date.now() }
) => {
  if (!epoch) return '';
  const data = new Date(epoch * 1000);
  const idioma = toLocaleTag(locale);
  const hora = new Intl.DateTimeFormat(idioma, {
    timeZone: fuso,
    hour: '2-digit',
    minute: '2-digit',
  }).format(data);
  const dia = diaNoFuso(data, fuso);
  if (dia === diaNoFuso(new Date(agora), fuso))
    return t(`${NS}.HOJE`, { hora });
  if (dia === diaNoFuso(new Date(agora + UM_DIA), fuso))
    return t(`${NS}.AMANHA`, { hora });
  const diaLongo = new Intl.DateTimeFormat(idioma, {
    timeZone: fuso,
    day: 'numeric',
    month: 'long',
  }).format(data);
  return t(`${NS}.DIA`, { dia: diaLongo, hora });
};

export const diaFalado = (epoch, { fuso, locale }) =>
  epoch
    ? new Intl.DateTimeFormat(toLocaleTag(locale), {
        timeZone: fuso,
        day: 'numeric',
        month: 'long',
      }).format(new Date(epoch * 1000))
    : '';

// O fuso da conta aberta, pela loja (como Event.vue e useDataFalada). Sem loja (spec que monta só o cartão), o fuso
// padrão do servidor (CRM_DEFAULT_TIMEZONE), que fusoDaConta já usa.
export const useFusoDaConta = () => {
  const store = getCurrentInstance()?.proxy?.$store;
  return computed(() => {
    const getters = store?.getters || {};
    const conta = getters['accounts/getAccount']?.(getters.getCurrentAccountId);
    return fusoDaConta(conta) || undefined;
  });
};
