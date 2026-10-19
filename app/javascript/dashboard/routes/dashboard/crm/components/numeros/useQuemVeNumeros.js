import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  CRM_ADMIN_PERMISSION,
  CRM_VIEW_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
} from 'dashboard/constants/permissions';

// Quem vê o quê em CRM › Números (#1897), a mesma régua da Crm::NumerosPolicy e da
// Crm::ReportPolicy no servidor:
// - equipe: administrador e função com crm_view_reports (ou crm_admin); sem a flag
//   `crm_numeros_lentes`, também o agente sem função (como antes);
// - "Só eu" (só com a flag): administrador, agente sem função e função com crm_view.
export function useQuemVeNumeros() {
  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const currentRole = useMapGetter('getCurrentRole');
  const currentCustomRoleId = useMapGetter('getCurrentCustomRoleId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );

  const ligado = computed(() =>
    Boolean(
      isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.CRM_NUMEROS_LENTES
      )
    )
  );
  const administrador = computed(() => currentRole.value === 'administrator');
  const semFuncao = computed(() => !currentCustomRoleId.value);
  const temChave = chave => {
    const chaves = getUserPermissions(currentUser.value, accountId.value);
    return chaves.includes(CRM_ADMIN_PERMISSION) || chaves.includes(chave);
  };

  const veEquipe = computed(() => {
    if (administrador.value) return true;
    if (semFuncao.value) return !ligado.value;
    return temChave(CRM_VIEW_REPORTS_PERMISSION);
  });
  const veSoEu = computed(
    () =>
      ligado.value &&
      (administrador.value || semFuncao.value || temChave(CRM_VIEW_PERMISSION))
  );
  const abreNumeros = computed(() => veEquipe.value || veSoEu.value);

  return { ligado, administrador, veEquipe, veSoEu, abreNumeros };
}
