import { computed, ref, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { recebeAgenda as agenteRecebeAgenda } from '../utils/pagina';
import {
  estadoComLiberacao,
  estadoDaPagina,
  idsLiberados,
  pessoasDaPagina,
} from '../utils/agendaDaPagina';

// #1196 / #1253 — a página de agendamento que a IA usa para oferecer horários e marcar. Mesma regra
// no painel antigo (AgentBookingForm) e na página nova do agente (linha "Marca reuniões" e
// GavetaAgenda): some quando o agente não recebe a agenda (`booking_available: false`, o Agente de
// Cotação) e quando a API de páginas responde erro (a conta não tem a agenda nova ou a pessoa não
// pode ver Agendamento). O id da página é comparado como número: a config pode trazê-lo em texto.
export const SEM_PAGINA = '';

export const idDaPagina = valor => {
  const id = Number(valor);
  return Number.isInteger(id) && id > 0 ? id : SEM_PAGINA;
};

export const ESTADO_AGENDA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  INDISPONIVEL: 'indisponivel',
};

export function useAgendaDoAgente(agente) {
  const { t } = useI18n();
  const paginas = ref([]);
  const estado = ref(ESTADO_AGENDA.CARREGANDO);

  const recebeAgenda = computed(() => agenteRecebeAgenda(toValue(agente)));
  const disponivel = computed(
    () => recebeAgenda.value && estado.value === ESTADO_AGENDA.PRONTO
  );
  const paginaSalva = computed(() =>
    idDaPagina(toValue(agente)?.config?.booking_page_id)
  );

  const tituloDaPagina = pagina => pagina.title || t('BOOKING.CARD.UNTITLED');

  const nomeDaPagina = pagina => {
    const titulo = tituloDaPagina(pagina);
    return pagina.enabled
      ? titulo
      : t('BOOKING.AI_AGENT.PAUSED_PAGE', { title: titulo });
  };

  const opcoes = computed(() => [
    { value: SEM_PAGINA, label: t('BOOKING.AI_AGENT.OFF') },
    ...paginas.value.map(pagina => ({
      value: idDaPagina(pagina.id),
      label: nomeDaPagina(pagina),
    })),
  ]);

  const paginaDe = id =>
    id === SEM_PAGINA
      ? undefined
      : paginas.value.find(pagina => idDaPagina(pagina.id) === id);

  // #1307 — as pessoas da página `id` que este agente pode usar, como gravadas no agente.
  const liberadasDe = id =>
    idsLiberados(
      toValue(agente)?.config?.booking_agent_ids,
      pessoasDaPagina(paginaDe(id))
    );

  // #1181 (item A) — estado real da página `id` (utils/agendaDaPagina): nenhuma, não existe mais,
  // pausada, sem ninguém para atender ou ativa. #1307: com as pessoas liberadas (as da tela ou, sem
  // elas, as gravadas), ninguém liberado ou todos com a agenda pausada mudam o estado.
  const estadoDe = (id, liberadas = liberadasDe(id)) => {
    const pagina = paginaDe(id);
    return estadoComLiberacao(
      estadoDaPagina(id !== SEM_PAGINA, pagina),
      pessoasDaPagina(pagina),
      liberadas
    );
  };

  const carregar = async () => {
    if (!recebeAgenda.value) return;
    estado.value = ESTADO_AGENDA.CARREGANDO;
    try {
      const { data } = await CrmBookingPagesAPI.get();
      paginas.value = data.payload || [];
      estado.value = ESTADO_AGENDA.PRONTO;
    } catch {
      estado.value = ESTADO_AGENDA.INDISPONIVEL;
    }
  };

  return {
    paginas,
    estado,
    recebeAgenda,
    disponivel,
    paginaSalva,
    opcoes,
    paginaDe,
    estadoDe,
    liberadasDe,
    tituloDaPagina,
    nomeDaPagina,
    carregar,
  };
}
