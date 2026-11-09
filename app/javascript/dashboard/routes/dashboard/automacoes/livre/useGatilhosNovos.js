import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { BOOKING_V2_FEATURE } from 'dashboard/routes/dashboard/settings/booking/constants';
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
  // G22: a seleção do recorrente pede também os campos de marcar do card.
  { pecas: ['campo', 'selecao'], erro: 'GATILHO_DE_TEMPO.ERRO_CAMPOS' },
  { pecas: ['pagina'], erro: 'GATILHO_DE_REUNIAO.ERRO_PAGINAS' },
];

export function useGatilhosNovos(isCloudFeatureEnabled, catalogo) {
  const { t } = useI18n();
  const { canManagePipelines } = useCrmPermissions();
  const { escolhas, carregar } = useEscolhasDosGatilhos();
  const veAgendamento = usePermissionGranted('agendamento_view');
  const mexeNoAgendamento = usePermissionGranted('agendamento_manage');

  // G12: o de reunião (`reunioes`) só com as reuniões da instalação ligadas.
  const liberado = item =>
    (!item.requer || isCloudFeatureEnabled(item.requer)) &&
    (!item.funil || canManagePipelines.value) &&
    (!item.reunioes ||
      window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true');

  // G32: a página de agendamento só com o agendamento novo da conta e para
  // quem pode ler as páginas (a mesma regra da API); sem isso o filtro some e
  // o gatilho vale para qualquer página.
  const lePaginas = computed(
    () =>
      isCloudFeatureEnabled(BOOKING_V2_FEATURE) &&
      (veAgendamento.value || mexeNoAgendamento.value)
  );
  const semPaginaSeNaoLe = item =>
    lePaginas.value || !(item.parametros || []).some(p => p.peca === 'pagina')
      ? item
      : {
          ...item,
          parametros: item.parametros.filter(p => p.peca !== 'pagina'),
        };

  const gatilhos = computed(() =>
    catalogo.value
      ? catalogo.value.gatilhos.filter(liberado).map(semPaginaSeNaoLe)
      : null
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
