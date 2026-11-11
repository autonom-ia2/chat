import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { camadasDoPacote } from 'dashboard/i18n/pacotesDoPainel';

// #2889 — a conta atual tem a porta da Automação ligada, e de que segmento ela é (camadas do pacote #1550). Lido do
// store, como o useVitrineLigada (#2858): a lista e a tela do Guia também são montadas sem conta no store (specs).
// A porta só vale com o editor da Automação livre: "Montar do zero" e o modo manual vão para ele.
export function usePorta() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  const atual = computed(() =>
    typeof conta.value === 'function' ? conta.value(contaId.value) : null
  );
  const tem = flag => atual.value?.features?.[flag] === true;
  return {
    ligada: computed(
      () =>
        tem(FEATURE_FLAGS.AUTOMACAO_PORTA) &&
        tem(FEATURE_FLAGS.AUTOMACAO_EDITOR)
    ),
    camadas: computed(() => camadasDoPacote(atual.value?.autonomia_pacote)),
  };
}
