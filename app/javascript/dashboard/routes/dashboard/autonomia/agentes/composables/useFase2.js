import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// #1433 (tema 13) — a Fase 2 dos Agentes ligada na conta (`autonomia_agents_fase2` da conta, que o
// servidor só manda true com os Agentes ligados; piloto 1, 16 e 18). Só ela mostra o agente da equipe.
export const fase2Ligada = conta => conta?.autonomia_agents_fase2 === true;

export function useFase2() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  return computed(() => fase2Ligada(conta.value?.(contaId.value)));
}
