import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { isBookingV2Available } from 'dashboard/routes/dashboard/settings/booking/bookingAccess';

// #1253 — a conta tem a agenda nova (`crm_booking_v2` e o calendário da instalação), pela mesma regra
// do resto do agendamento (isBookingV2Available). A página do agente só mostra "Marca reuniões" com
// ela; a API de páginas responder erro continua escondendo (useAgendaDoAgente).
export function useAgendaNovaNaConta() {
  const contaAtual = useMapGetter('getCurrentAccountId');
  const conta = useMapGetter('accounts/getAccount');
  return computed(() =>
    Boolean(
      typeof conta.value === 'function' &&
        isBookingV2Available(conta.value(contaAtual.value))
    )
  );
}
