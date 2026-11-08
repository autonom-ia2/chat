import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

// #2414 F1.3: com a flag `automacao_fundacao`, criar, editar e apagar automação de etapa pede também a chave das
// regras automáticas (admin sempre). Sem a flag, a tela segue como antes.
export function usePodeMontarAutomacao() {
  const { isCloudFeatureEnabled } = useAccount();
  const temAChave = usePermissionGranted('automation_manage');

  return computed(
    () => !isCloudFeatureEnabled('automacao_fundacao') || temAChave.value
  );
}
