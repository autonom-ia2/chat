import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { camadasDoPacote } from 'dashboard/i18n/pacotesDoPainel';

// #2776 — a vitrine (protótipo) está ligada na conta? Lida do store, como o useFerramentasDelegadas: a gaveta de
// ferramentas é montada também fora de uma rota (specs), então não depende de useRoute.
export function useVitrineLigada() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  const atual = computed(() =>
    typeof conta.value === 'function' ? conta.value(contaId.value) : null
  );
  return {
    contaId,
    ligada: computed(
      () =>
        atual.value?.features?.[FEATURE_FLAGS.AGENTE_VITRINE_FERRAMENTAS] ===
        true
    ),
    // Camadas do pacote da conta (#1550): o ramo que põe cartões em destaque e escolhe as sugestões do protótipo.
    camadas: computed(() => camadasDoPacote(atual.value?.autonomia_pacote)),
  };
}
