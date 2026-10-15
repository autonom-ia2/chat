import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import {
  CRM_ADMIN_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
} from 'dashboard/constants/permissions';
import { useMenuNovo } from 'dashboard/components-next/sidebar/fork/useMenuNovo';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';

export const ROTA_NUMEROS = 'crm_dashboard_index';

// Aba "Números" do CRM (#1617): a página que era CRM › Dashboard, ao lado de Kanban, Lista e Calendário.
// Só com o menu novo. Quem vê: a mesma regra de hoje do item Dashboard (Sidebar.vue canViewCrmReports) e a
// permissão da própria rota.
export function useAbaNumeros() {
  const { ligado } = useMenuNovo();
  const { podeAbrir } = usePodeAbrir();
  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const currentRole = useMapGetter('getCurrentRole');
  const currentCustomRoleId = useMapGetter('getCurrentCustomRoleId');

  const veRelatoriosDoCrm = computed(() => {
    if (currentRole.value === 'administrator' || !currentCustomRoleId.value) {
      return true;
    }
    const chaves = getUserPermissions(currentUser.value, accountId.value);
    return [CRM_ADMIN_PERMISSION, CRM_VIEW_REPORTS_PERMISSION].some(chave =>
      chaves.includes(chave)
    );
  });

  const mostrar = computed(
    () =>
      ligado.value &&
      veRelatoriosDoCrm.value &&
      podeAbrir({ name: ROTA_NUMEROS })
  );

  return { ligado, mostrar };
}
