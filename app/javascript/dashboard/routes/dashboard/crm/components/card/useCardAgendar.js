import { computed, ref, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useBookingInviteAvailable } from 'dashboard/components-next/Booking/useBookingInviteAvailable';
import { useJeitoDeMarcar } from './useJeitoDeMarcar';

// #1423 — marcar reunião e mandar o link da agenda, as duas como telas da
// própria gaveta. "Marcar reunião" abre pela página de agendamento ou pelo
// Google/Microsoft (useJeitoDeMarcar). O link tem a régua do próprio botão do
// cabeçalho da conversa; se o servidor disser que ele está desligado, some
// também do resumo até abrir outro card.
export const useCardAgendar = ({
  t,
  store,
  router,
  props,
  cardId,
  editando,
  podeGerenciar,
  tela,
  irPara,
  voltarSemGuarda,
  guardar,
  reuniao,
  telaReuniao,
  aoMudar,
}) => {
  const linkDaConta = useBookingInviteAvailable();
  const linkForaDoServidor = ref(false);
  watch(cardId, () => {
    linkForaDoServidor.value = false;
  });
  const linkAgenda = computed(
    () => linkDaConta.value && !linkForaDoServidor.value
  );

  const jeitoDeMarcar = useJeitoDeMarcar({
    store,
    router,
    caixas: computed(() => props.inboxes),
    ligado: computed(
      () =>
        props.show &&
        editando.value &&
        props.meetingsEnabled &&
        podeGerenciar.value
    ),
  });

  const marcarReuniao = () => {
    if (!podeGerenciar.value) return;
    if (['pagina', 'externa'].includes(jeitoDeMarcar.jeito.value))
      irPara('reuniao-nova');
  };
  const confirmarReuniao = () => telaReuniao.value?.marcar();
  // Pela página (#1265, `source: 'panel'`) não há convite por e-mail: outro aviso.
  const reuniaoMarcada = marcada => {
    useAlert(
      marcada?.source === 'panel'
        ? t('CRM_KANBAN.BOOKING_AGENDA.SUCCESS')
        : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SUCCESS')
    );
    reuniao.recarregar();
    aoMudar();
    voltarSemGuarda();
  };
  const abrirLink = () => podeGerenciar.value && irPara('link-agenda');
  const linkCaiu = () => {
    linkForaDoServidor.value = true;
    if (tela.value === 'link-agenda') voltarSemGuarda();
  };
  const criarPagina = () =>
    guardar(() => jeitoDeMarcar.abrirPaginas(), { leaving: true });

  return {
    linkAgenda,
    jeitoDeMarcar,
    marcarReuniao,
    confirmarReuniao,
    reuniaoMarcada,
    abrirLink,
    linkCaiu,
    criarPagina,
  };
};
