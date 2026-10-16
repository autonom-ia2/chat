import { computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';

// #1648 — a aba "Agente de IA" por caixa ligada na conta (`autonomia_agente_ia_por_caixa` da conta; piloto 1, 16 e
// 18). Ligada: aba Agente de IA, aba Usuários, agentes de outro sistema na lista de Agentes e área com agente de outro
// sistema. Desligada: tudo como antes.
export const agenteIaPorCaixaLigado = conta =>
  conta?.autonomia_agente_ia_por_caixa === true;

export function useAgenteIaPorCaixa() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  // Mesma leitura do useFase2: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      agenteIaPorCaixaLigado(conta.value(contaId.value))
  );
}

// Nas entradas das rotas (como o useJornadaAtiva): decide uma vez, no setup, pela store.
export function useAgenteIaPorCaixaNaEntrada() {
  const { getters } = useStore();
  const conta = getters['accounts/getAccount']?.(getters.getCurrentAccountId);
  return agenteIaPorCaixaLigado(conta);
}
