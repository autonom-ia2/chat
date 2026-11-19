import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// #1461 — quem vê "Novo lembrete" na ficha: o CRM ligado na instalação, a flag
// crm_lembretes_v2 na conta e quem pode mexer em cards. #3071 — a mesma regra
// vale para a ficha nova de Relacionamentos, que desenha o próprio botão.
export const usePodeCriarLembrete = () => {
  const { isCloudFeatureEnabled } = useAccount();
  const { canViewCrm, canManageCards } = useCrmPermissions();
  return computed(
    () =>
      window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
      isCloudFeatureEnabled(FEATURE_FLAGS.CRM_LEMBRETES_V2) &&
      canViewCrm.value &&
      canManageCards.value
  );
};
