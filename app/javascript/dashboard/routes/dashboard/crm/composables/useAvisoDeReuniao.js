import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// Aviso ao arquivar (#2091): arquivar não cancela a reunião marcada com o cliente (cancelar o avisaria). O diálogo de
// arquivar diz que ela continua. O servidor manda o início da próxima reunião de cada card, já no fuso da conta.
// O idioma do painel vem como `pt_BR`; o Intl só aceita `pt-BR`.
export const dataDaReuniao = (startsAt, timeZone, locale) =>
  new Intl.DateTimeFormat(String(locale).replace('_', '-'), {
    timeZone,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(startsAt));

// O botão Arquivar espera o aviso chegar (carregando), no máximo este tempo: depois libera, com ou sem aviso.
export const ESPERA_MAXIMA_MS = 4000;

export const useAvisoDeReuniao = () => {
  const { t, locale } = useI18n();
  const aviso = ref('');
  const carregando = ref(false);
  let pedido = 0;

  // Um card: a data da reunião. Vários: quantos têm reunião.
  const texto = ({ timezone, cards }, total) => {
    if (!cards?.length) return '';
    if (total === 1) {
      const quando = dataDaReuniao(cards[0].starts_at, timezone, locale.value);
      return t('CRM_CARD.ARQUIVAR.REUNIAO', { quando });
    }
    return t('CRM_KANBAN.BULK.DELETE_MEETINGS', { count: cards.length });
  };

  // O aviso é só informação: se a consulta ao servidor falhar, o diálogo segue sem ele e o arquivar funciona igual.
  const buscar = async ids => {
    try {
      const { data } = await CrmKanbanAPI.upcomingMeetings(ids);
      return data.payload || {};
    } catch {
      return {};
    }
  };

  const consultar = async ids => {
    pedido += 1;
    const este = pedido;
    aviso.value = '';
    carregando.value = Boolean(ids?.length);
    if (!ids?.length) return;
    const limite = setTimeout(() => {
      if (este === pedido) carregando.value = false;
    }, ESPERA_MAXIMA_MS);
    const proximas = await buscar(ids);
    clearTimeout(limite);
    if (este !== pedido) return;
    aviso.value = texto(proximas, ids.length);
    carregando.value = false;
  };

  return { aviso, carregando, consultar };
};
