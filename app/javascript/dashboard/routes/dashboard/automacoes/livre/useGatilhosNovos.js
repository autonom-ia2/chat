import { computed, ref } from 'vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { GATILHOS } from './gatilhosDemo';
import { useEscolhasDosGatilhos } from './useEscolhasDosGatilhos';

// #2499 (F6+F8) — os gatilhos novos que o editor oferece, com a flag. Os de
// card só para quem pode mexer no funil, pela mesma regra do servidor
// (crm_permission?: conta o crm_admin, nega o agente comum); o servidor recusa
// o resto ao salvar. Sem a flag na abertura da tela, nada do CRM é lido.
// PROTÓTIPO: a lista vem do adaptador falso (gatilhosDemo).
export function useGatilhosNovos(isCloudFeatureEnabled) {
  if (!isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_GATILHOS))
    return {
      gatilhosNovos: computed(() => null),
      escolhasDoGatilho: ref({}),
      carregarGatilhos: () => {},
    };

  const { canManagePipelines } = useCrmPermissions();
  const { escolhas, carregar } = useEscolhasDosGatilhos();
  const gatilhosNovos = computed(() =>
    GATILHOS.filter(item => !item.crm || canManagePipelines.value)
  );

  return {
    gatilhosNovos,
    escolhasDoGatilho: escolhas,
    carregarGatilhos: carregar,
  };
}
