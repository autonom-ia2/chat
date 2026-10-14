import { computed } from 'vue';
import { useStore } from 'vuex';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// Quando o link de agenda (#1190) pode aparecer: a flag da conta
// `crm_booking_v2`, o calendário de reuniões da instalação e quem vê os cards
// do CRM. O BookingInviteButton e o card do funil (#1423) usam a mesma régua,
// para o card não mostrar um lugar de "Enviar link" sem o botão.
export const BOOKING_INVITE_FLAG = 'crm_booking_v2';

export const useBookingInviteAvailable = () => {
  const store = useStore();
  const { canViewCrm } = useCrmPermissions();
  return computed(
    () =>
      window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true' &&
      store.getters['accounts/isFeatureEnabledonAccount'](
        store.getters.getCurrentAccountId,
        BOOKING_INVITE_FLAG
      ) &&
      canViewCrm.value
  );
};
