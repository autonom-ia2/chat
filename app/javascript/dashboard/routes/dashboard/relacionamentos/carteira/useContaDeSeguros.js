// #2897 — a conta aberta tem a carteira de seguros? A resposta é do servidor
// (o payload da conta) ou, na demonstração, do estado dela
// (fonte/modoCarteira.js). `demo` é o estado que a página leu do endereço.
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { contaDeSeguros } from '../fonte/modoCarteira';

export const useContaDeSeguros = demo => {
  const { currentAccount } = useAccount();
  return computed(() => contaDeSeguros(demo, currentAccount.value));
};
