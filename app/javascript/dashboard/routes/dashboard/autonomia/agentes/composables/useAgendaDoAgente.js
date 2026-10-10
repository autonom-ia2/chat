import { computed, ref, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { recebeAgenda as agenteRecebeAgenda } from '../utils/pagina';

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

  const nomeDaPagina = pagina => {
    const titulo = pagina.title || t('BOOKING.CARD.UNTITLED');
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
    nomeDaPagina,
    carregar,
  };
}
