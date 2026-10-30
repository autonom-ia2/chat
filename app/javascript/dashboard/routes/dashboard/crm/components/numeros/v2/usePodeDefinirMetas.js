import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  useCanManage,
  useHasCustomRolePermission,
} from 'dashboard/composables/useCanManage';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  CRM_ADMIN_PERMISSION,
  CRM_METAS_MANAGE_PERMISSION,
  CRM_VIEW_PERMISSION,
  SALES_VALUE_VIEW_PERMISSION,
} from 'dashboard/constants/permissions';

// Quem abre a gaveta "Metas do mês" (#1991), a régua da Crm::MetasPolicy:
// com a flag `crm_metas`, o administrador e a função com `crm_metas_manage`
// com acesso ao CRM (`crm_view`), ou `crm_admin`, sempre com os valores em R$
// (`sales_value_view`, #2075, que o `crm_admin` não liga). O agente sem função
// nunca: ele vê só a própria meta.
export function usePodeDefinirMetas() {
  const accountId = useMapGetter('getCurrentAccountId');
  const currentRole = useMapGetter('getCurrentRole');
  const customRoleId = useMapGetter('getCurrentCustomRoleId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const comChave = useCanManage(CRM_METAS_MANAGE_PERMISSION);
  const comCrm = useHasCustomRolePermission(CRM_VIEW_PERMISSION);
  const crmAdmin = useHasCustomRolePermission(CRM_ADMIN_PERMISSION);
  const comValores = useHasCustomRolePermission(SALES_VALUE_VIEW_PERMISSION);

  const ligado = computed(() =>
    Boolean(
      isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CRM_METAS)
    )
  );
  const temFuncao = computed(() => Boolean(customRoleId.value));

  return computed(() => {
    if (!ligado.value) return false;
    if (currentRole.value === 'administrator') return true;
    return (
      temFuncao.value &&
      comValores.value &&
      (crmAdmin.value || (comChave.value && comCrm.value))
    );
  });
}
