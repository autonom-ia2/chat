// #2084/#2085 — "Este contato é" fica atrás da chave `contato_relacao` da conta.
// Desligada, o painel e a ficha do contato ficam como antes.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export function useRelacaoLigada() {
  const contaId = useMapGetter('getCurrentAccountId');
  const chaveLigada = useMapGetter('accounts/isFeatureEnabledonAccount');
  return computed(() =>
    Boolean(
      contaId.value &&
        chaveLigada.value(contaId.value, FEATURE_FLAGS.CONTATO_RELACAO)
    )
  );
}
