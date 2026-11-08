// #2138 — o painel novo do contato e os itens novos do ⋯ do topo ficam atrás da
// chave `painel_contato_enxuto` da conta. Desligada, tudo fica como antes.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export function usePainelNovo() {
  const contaId = useMapGetter('getCurrentAccountId');
  const chaveLigada = useMapGetter('accounts/isFeatureEnabledonAccount');
  return computed(() =>
    Boolean(
      contaId.value &&
        chaveLigada.value(contaId.value, FEATURE_FLAGS.PAINEL_CONTATO_ENXUTO)
    )
  );
}
