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
// Os funis e as etapas só são lidos quando algum gatilho oferecido pede um; os
// campos de data, quando algum pede o campo.
// O que cada leitura traz, pelas peças que a pedem, e o aviso se ela falhar.
const LEITURAS = [
  { pecas: ['etapa', 'funil', 'selecao'], erro: 'GATILHO_DO_CARD.ERRO_FUNIS' },
  { pecas: ['campo'], erro: 'GATILHO_DE_TEMPO.ERRO_CAMPOS' },
  // G27: o "card atualizado" (mudanca) escolhe entre os campos do card.
  { pecas: ['mudanca'], erro: 'MUDANCA.ERRO_CAMPOS' },
];

export function useGatilhosNovos(isCloudFeatureEnabled, catalogo) {
  const { t } = useI18n();
  const { canManagePipelines } = useCrmPermissions();
  const { escolhas, carregar } = useEscolhasDosGatilhos();

  // G12: o de reunião (`reunioes`) só com as reuniões da instalação ligadas.
  const liberado = item =>
    (!item.requer || isCloudFeatureEnabled(item.requer)) &&
    (!item.funil || canManagePipelines.value) &&
    (!item.reunioes ||
      window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true');

  const gatilhos = computed(() =>
    catalogo.value ? catalogo.value.gatilhos.filter(liberado) : null
  );
  // As peças que os gatilhos oferecidos pedem (etapa, funil, campo...).
  const pecasPedidas = computed(() => [
    ...new Set(
      (gatilhos.value || []).flatMap(item =>
        (item.parametros || []).map(parametro => parametro.peca)
      )
    ),
  ]);

  // Cada leitura uma vez, quando alguma peça passa a pedi-la (a flag e a
  // permissão podem chegar depois). Se falhar, avisa: sem as etapas ou os
  // campos, o gatilho que os pede não salva; abrir o editor de novo tenta
  // outra vez.
  const feitas = new Set();
  const ler = async leitura => {
    feitas.add(leitura);
    try {
      await carregar(leitura.pecas);
    } catch {
      useAlert(t(`AUTOMACAO_LIVRE.${leitura.erro}`));
    }
  };
  watch(
    pecasPedidas,
    pecas =>
      LEITURAS.filter(
        leitura =>
          !feitas.has(leitura) &&
          leitura.pecas.some(peca => pecas.includes(peca))
      ).forEach(ler),
    { immediate: true }
  );

  return { gatilhos, escolhasDoGatilho: escolhas };
}
