import { computed, watch } from 'vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { GATILHOS } from './gatilhosDemo';
import { useEscolhasDosGatilhos } from './useEscolhasDosGatilhos';

// #2499 (F6+F8) — os gatilhos novos que o editor oferece, com a flag. Os de
// card só para quem pode mexer no funil, pela mesma regra do servidor
// (crm_permission?: conta o crm_admin, nega o agente comum); o servidor recusa
// o resto ao salvar. A flag é lida de forma reativa: abrindo a tela direto pela
// URL, a conta chega depois do setup. As escolhas (funis, etapas) só são lidas
// com a flag ligada.
// PROTÓTIPO: a lista vem do adaptador falso (gatilhosDemo).
export function useGatilhosNovos(isCloudFeatureEnabled) {
  const { canManagePipelines } = useCrmPermissions();
  const { escolhas, carregar } = useEscolhasDosGatilhos();
  const ligada = computed(() =>
    isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_GATILHOS)
  );

  const gatilhosNovos = computed(() =>
    ligada.value
      ? GATILHOS.filter(item => !item.crm || canManagePipelines.value)
      : null
  );

  const carregarGatilhos = () => {
    watch(
      ligada,
      valor => {
        if (valor) carregar();
      },
      { immediate: true, once: true }
    );
  };

  return {
    gatilhosNovos,
    escolhasDoGatilho: escolhas,
    carregarGatilhos,
  };
}
