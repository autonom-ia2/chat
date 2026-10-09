import { computed, nextTick, ref } from 'vue';
import {
  cancelInvite,
  confirmInvite,
  getInvite,
  rescheduleInvite,
  stopInviteNotices,
} from '../api';
import { isValidTimeZone } from '../helpers/datetime';

// Gestão da reunião pelo link do cliente `/b/<code>` (#1192, contrato F2-A, J5): "Vou estar lá", mudar o horário,
// cancelar e parar avisos. As telas são passos do mesmo fluxo (`steps`), e o "voltar" do celular volta para a tela
// da reunião; ação concluída não se desfaz com o voltar. Toda ação responde o JSON do convite, que substitui o atual.
const ERROR_KEYS = {
  too_late: 'BOOKING_V2.MANAGE.ERRORS.TOO_LATE',
  not_changeable: 'BOOKING_V2.MANAGE.ERRORS.NOT_CHANGEABLE',
};
const FAILED_KEY = 'BOOKING_V2.MANAGE.ERRORS.FAILED';
const MINUTE_MS = 60 * 1000;

const focusHeading = () =>
  nextTick(() => document.querySelector('[data-step-heading]')?.focus());

export function useManage({
  steps,
  step,
  page,
  invite,
  history,
  goTo,
  finishOn,
  duration,
  durations,
  selectedDate,
  selectedSlot,
  slots,
  backToTimes,
  stopRequested,
}) {
  const isRescheduling = ref(false);
  const isWorking = ref(false);
  // Resultado da última ação ('confirmed' | 'rescheduled' | 'canceled' | 'stopped'): muda o título da tela.
  const notice = ref('');
  // Chave i18n do erro da tela: um único alerta por vez.
  const error = ref('');

  const meeting = computed(() => invite.meeting.value || {});
  const whatsappUrl = computed(
    () =>
      invite.invite.value?.contact_whatsapp_url ||
      page.value?.contact_whatsapp_url ||
      ''
  );
  const isCanceled = computed(() => meeting.value.status === 'canceled');
  const isScheduled = computed(() => meeting.value.status === 'scheduled');
  const minutes = computed(() => {
    const start = new Date(meeting.value.starts_at || '').getTime();
    const end = new Date(meeting.value.ends_at || '').getTime();
    return Math.round((end - start) / MINUTE_MS);
  });
  const hasStarted = computed(
    () => new Date(meeting.value.starts_at || '').getTime() <= Date.now()
  );
  const canChange = computed(
    () => isScheduled.value && !!meeting.value.can_change
  );
  const canConfirm = computed(
    () =>
      isScheduled.value &&
      meeting.value.confirmation_status !== 'confirmed' &&
      !hasStarted.value
  );
  // Remarcar usa os horários da página: só com a página aberta, fuso válido e a duração da reunião ainda oferecida
  // (o servidor recusa outra). Sem isso a pessoa ainda pode cancelar.
  const canReschedule = computed(
    () =>
      canChange.value &&
      !page.value?.paused &&
      isValidTimeZone(page.value?.timezone) &&
      durations.value.includes(minutes.value)
  );

  const show = () => {
    isRescheduling.value = false;
    error.value = '';
    goTo(steps.MANAGE);
  };

  // Volta para a tela da reunião tirando do histórico as telas que vieram depois dela.
  const returnToManage = () => {
    show();
    if (!history.home()) history.replace(steps.MANAGE);
  };

  // Primeira tela: com `?stop_notices=1` (link de "Parar avisos" das mensagens) já abre a confirmação de parar.
  // Parar exige um toque: a pré-visualização de link do WhatsApp (e de outros apps) abre a URL sozinha, e parar só
  // por abrir faria os avisos pararem sem a pessoa pedir.
  const open = () => {
    const askStop = stopRequested && !meeting.value.notices_stopped;
    finishOn(askStop ? steps.MANAGE_STOP : steps.MANAGE);
  };

  const openScreen = next => {
    error.value = '';
    notice.value = '';
    history.push(next);
    goTo(next);
  };

  // "Voltar" das telas da gestão: pelo histórico quando há; senão (a confirmação de parar abriu a página) direto.
  const back = () => {
    if (history.back()) return;
    returnToManage();
  };

  const startReschedule = () => {
    isRescheduling.value = true;
    duration.value = minutes.value;
    selectedDate.value = '';
    selectedSlot.value = '';
    openScreen(steps.DATE);
    slots.loadNextSlot();
  };

  // O convite pode ter mudado do outro lado (prazo, cancelada pelo agente): relê para a tela não mentir. Se a
  // releitura falhar, o recado da recusa já está na tela e os dados antigos ficam; não há o que somar a ele.
  const refresh = async () => {
    try {
      invite.invite.value = await getInvite(invite.invite.value.code);
    } catch (reloadError) {
      // Recado da recusa já mostrado (acima).
    }
  };

  const fail = async failure => {
    if (failure?.status === 404) return finishOn(steps.NOT_FOUND);
    const key = ERROR_KEYS[failure?.code];
    if (!key) {
      error.value = FAILED_KEY;
      return null;
    }
    returnToManage();
    error.value = key;
    return refresh();
  };

  const run = async (action, result) => {
    if (isWorking.value) return;
    isWorking.value = true;
    error.value = '';
    try {
      invite.invite.value = await action(invite.invite.value.code);
      const wasOnManage = step.value === steps.MANAGE;
      returnToManage();
      notice.value = result;
      if (wasOnManage) focusHeading();
    } catch (failure) {
      if (result === 'rescheduled' && failure?.code === 'slot_unavailable') {
        backToTimes();
      } else {
        await fail(failure);
      }
    } finally {
      isWorking.value = false;
    }
  };

  const confirm = () => run(confirmInvite, 'confirmed');
  const cancel = () => run(cancelInvite, 'canceled');
  const stopNotices = () => run(stopInviteNotices, 'stopped');
  const submitReschedule = () =>
    run(
      code =>
        rescheduleInvite(code, {
          starts_at: selectedSlot.value,
          duration: minutes.value,
        }),
      'rescheduled'
    );

  return {
    meeting,
    whatsappUrl,
    isCanceled,
    isRescheduling,
    isWorking,
    notice,
    error,
    canChange,
    canConfirm,
    canReschedule,
    open,
    show,
    back,
    returnToManage,
    startReschedule,
    openCancel: () => openScreen(steps.MANAGE_CANCEL),
    openStop: () => openScreen(steps.MANAGE_STOP),
    confirm,
    cancel,
    stopNotices,
    submitReschedule,
  };
}
