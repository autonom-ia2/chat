import { computed } from 'vue';
import { useMenuNovo } from 'dashboard/components-next/sidebar/fork/useMenuNovo';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import { useQuemVeNumeros } from './useQuemVeNumeros';

export const ROTA_NUMEROS = 'crm_dashboard_index';

// Aba "Números" do CRM (#1617): a página que era CRM › Dashboard, ao lado de Kanban, Lista e Calendário.
// Só com o menu novo. Quem vê: a mesma regra do item Dashboard (Sidebar.vue canViewCrmReports, useQuemVeNumeros:
// com `crm_numeros_lentes`, também quem só trabalha no CRM) e a permissão da própria rota.
export function useAbaNumeros() {
  const { ligado } = useMenuNovo();
  const { podeAbrir } = usePodeAbrir();
  const { abreNumeros: veRelatoriosDoCrm } = useQuemVeNumeros();

  const mostrar = computed(
    () =>
      ligado.value &&
      veRelatoriosDoCrm.value &&
      podeAbrir({ name: ROTA_NUMEROS })
  );

  return { ligado, mostrar };
}
