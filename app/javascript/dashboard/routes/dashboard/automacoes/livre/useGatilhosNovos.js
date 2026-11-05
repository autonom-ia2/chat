import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { useEscolhasDosGatilhos } from './useEscolhasDosGatilhos';

// #2499 — os gatilhos que o editor oferece, pelo próprio catálogo: o que pede
// uma flag (`requer`) só com ela ligada na conta, e o de card (`funil`) só para
// quem pode mexer no funil, pela mesma regra do servidor (crm_manage_pipelines:
// conta o crm_admin, nega o agente comum). O servidor recusa o resto ao salvar.
// A flag é lida de forma reativa: abrindo a tela pela URL, a conta chega depois.
// Os funis e as etapas só são lidos quando algum gatilho oferecido pede um.
export function useGatilhosNovos(isCloudFeatureEnabled, catalogo) {
  const { t } = useI18n();
  const { canManagePipelines } = useCrmPermissions();
  const { escolhas, carregar } = useEscolhasDosGatilhos();

  const liberado = item =>
    (!item.requer || isCloudFeatureEnabled(item.requer)) &&
    (!item.funil || canManagePipelines.value);

  const gatilhos = computed(() =>
    catalogo.value ? catalogo.value.gatilhos.filter(liberado) : null
  );
  const pedeEscolhas = computed(() =>
    (gatilhos.value || []).some(item => item.parametros?.length)
  );

  // Uma vez, quando passa a pedir. Se a carga falhar, avisa: sem as etapas, o
  // gatilho de etapa não salva; abrir o editor de novo tenta outra vez.
  let carregou = false;
  watch(
    pedeEscolhas,
    async pede => {
      if (!pede || carregou) return;
      carregou = true;
      try {
        await carregar();
      } catch {
        useAlert(t('AUTOMACAO_LIVRE.GATILHO_DO_CARD.ERRO_FUNIS'));
      }
    },
    { immediate: true }
  );

  return { gatilhos, escolhasDoGatilho: escolhas };
}
