import { ref } from 'vue';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

// G44 (#2756) — as páginas de agendamento da conta, para o "Pôr um dado"
// oferecer o link de cada uma (`agenda.<id da página>`). Só para quem vê a tela
// de páginas (`agendamento_view`, o espelho de AccountUser#permission_granted?)
// e com o agendamento novo ligado. Quem autoriza é o salvar (Receita): a lista
// só oferece; sem ela, a escolha fica sem as páginas.
export function useAgendasDaConta() {
  const paginas = ref([]);
  const podeVer = usePermissionGranted('agendamento_view');
  const { isCloudFeatureEnabled } = useAccount();

  const carregarAgendas = async () => {
    if (!podeVer.value || !isCloudFeatureEnabled('crm_booking_v2')) return;
    const { data } = await CrmBookingPagesAPI.get();
    paginas.value = data?.payload || [];
  };

  return { paginas, carregarAgendas };
}
