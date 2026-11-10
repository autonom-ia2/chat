import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { AUTONOMIA_TOOLS_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { camadasDoPacote } from 'dashboard/i18n/pacotesDoPainel';

// #2858 F2 — a vitrine de ferramentas prontas vale para esta pessoa nesta conta? As duas flags na conta
// (agente_ferramentas_prontas e agente_ferramentas_prontas_vitrine) e quem cuida das ferramentas: o administrador ou
// quem tem a chave "Ferramentas dos agentes" (autonomia_tools_manage). É a mesma regra do servidor
// (FerramentasProntasController). Lida do store, como o useFerramentasDelegadas: a gaveta de ferramentas é montada
// também fora de uma rota (specs), então não depende de useRoute.
export const vitrineNaConta = conta =>
  conta?.features?.[FEATURE_FLAGS.AGENTE_FERRAMENTAS_PRONTAS] === true &&
  conta?.features?.[FEATURE_FLAGS.AGENTE_FERRAMENTAS_PRONTAS_VITRINE] === true;

// #2858 F3 — o Construtor escolhe as prontas do agente novo, e o agente que já existe recebe o cartão "pode ganhar".
export const construtorNaConta = conta =>
  vitrineNaConta(conta) &&
  conta?.features?.[FEATURE_FLAGS.AGENTE_FERRAMENTAS_PRONTAS_CONSTRUTOR] ===
    true;

export function useVitrineLigada() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  const temChave = usePermissionGranted(AUTONOMIA_TOOLS_MANAGE_PERMISSION);
  const atual = computed(() =>
    typeof conta.value === 'function' ? conta.value(contaId.value) : null
  );
  return {
    contaId,
    ligada: computed(() => vitrineNaConta(atual.value) && temChave.value),
    // F3: a flag do Construtor na conta (`construtorNaConta`) e, para incluir, também a chave da pessoa (`construtor`).
    construtorNaConta: computed(() => construtorNaConta(atual.value)),
    construtor: computed(
      () => construtorNaConta(atual.value) && temChave.value
    ),
    // Camadas do pacote da conta (#1550): o ramo que põe cartões em destaque.
    camadas: computed(() => camadasDoPacote(atual.value?.autonomia_pacote)),
  };
}
