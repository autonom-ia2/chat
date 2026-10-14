import { computed, ref, watch } from 'vue';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import {
  canSeeBookingSettings,
  isBookingV2Available,
} from '../../../settings/booking/bookingAccess';

// #1423 — como esta conta marca reunião, sabido ANTES de abrir qualquer
// janela. A mesma regra do CrmCalendarMeetingScheduler:
//   'pagina'     — agendamento novo ligado e há página publicada: a reunião
//                  é marcada na própria gaveta (CrmBookingAgendaForm); com
//                  caixa Google/Microsoft também, a tela deixa escolher;
//   'externa'    — sem página, mas com caixa Google/Microsoft: a reunião é
//                  marcada na gaveta pelo formulário do Google/Microsoft
//                  (CrmProviderMeetingForm, o mesmo da janela do calendário);
//   'falta'      — nenhum dos dois: a tela explica e oferece criar a página
//                  ou fazer só um lembrete;
//   'carregando' — ainda perguntando ao servidor.
// Qualquer erro ao perguntar (sem acesso, flag desligada no servidor, rede)
// conta como sem página: cai em 'externa' quando há caixa, ou em 'falta'.
const ROTA_PAGINAS = 'settings_booking';

export const useJeitoDeMarcar = ({ store, router, caixas, ligado }) => {
  const paginas = ref([]);
  const carregando = ref(false);
  const perguntou = ref(false);
  let pedido = 0;

  const contaId = () => store.getters.getCurrentAccountId;
  const agendamentoNovo = computed(() =>
    isBookingV2Available(store.getters['accounts/getAccount']?.(contaId()))
  );
  const temCaixaDeAgenda = computed(() =>
    (caixas.value || []).some(
      caixa => caixa.calendar_enabled || caixa.calendarEnabled
    )
  );
  const podeCriarPagina = computed(
    () =>
      agendamentoNovo.value &&
      canSeeBookingSettings({
        isAdministrator: store.getters.getCurrentRole === 'administrator',
        permissions: getUserPermissions(
          store.getters.getCurrentUser,
          contaId()
        ),
      }) &&
      router.hasRoute(ROTA_PAGINAS)
  );

  const carregar = async () => {
    pedido += 1;
    const meu = pedido;
    paginas.value = [];
    perguntou.value = false;
    if (!ligado.value || !agendamentoNovo.value) {
      perguntou.value = true;
      return;
    }
    carregando.value = true;
    try {
      const { data } = await crmBookingPagesAPI.bookable();
      if (meu === pedido) paginas.value = data?.payload || [];
    } catch {
      if (meu === pedido) paginas.value = [];
    } finally {
      if (meu === pedido) {
        carregando.value = false;
        perguntou.value = true;
      }
    }
  };
  watch(ligado, valor => valor && carregar(), { immediate: true });

  const jeito = computed(() => {
    if (!perguntou.value || carregando.value) return 'carregando';
    if (paginas.value.length) return 'pagina';
    if (temCaixaDeAgenda.value) return 'externa';
    return 'falta';
  });

  const abrirPaginas = () =>
    router.push({ name: ROTA_PAGINAS, params: { accountId: contaId() } });

  return {
    jeito,
    paginas,
    temPagina: computed(() => paginas.value.length > 0),
    temCaixa: temCaixaDeAgenda,
    podeCriarPagina,
    abrirPaginas,
    recarregar: carregar,
  };
};
