import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #2776 — a vitrine (protótipo) está ligada na conta? Lida do store, como o useFerramentasDelegadas: a gaveta de
// ferramentas é montada também fora de uma rota (specs), então não depende de useRoute.
export function useVitrineLigada() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  return {
    contaId,
    ligada: computed(
      () =>
        typeof conta.value === 'function' &&
        conta.value(contaId.value)?.features?.[
          FEATURE_FLAGS.AGENTE_VITRINE_FERRAMENTAS
        ] === true
    ),
  };
}
