// #2202 — a lista "Quem está esperando" fica atrás da chave lista_quem_espera da conta
// (feature_flags_ext_2, posição pela ordem de chegada à main). Desligada, a lista de sempre.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export function useListaNova() {
  const contaId = useMapGetter('getCurrentAccountId');
  const chaveLigada = useMapGetter('accounts/isFeatureEnabledonAccount');
  return computed(() =>
    Boolean(
      contaId.value &&
        chaveLigada.value(contaId.value, FEATURE_FLAGS.LISTA_QUEM_ESPERA)
    )
  );
}
