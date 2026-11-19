// #3057 — "Criar o funil de renovações para mim", em "Ajustar renovações" da
// conta que ainda não tem funil. Não é um caminho novo: é o mesmo do CRM
// quando alguém cria um funil pelo modelo "Renovação" na gaveta de funil
// (crm/components/CrmPipelineDrawer.vue). As etapas, os nomes dos desfechos
// ("Renovou" / "Não renovou"), o "Quando usar" e as categorias saem do modelo
// (useFunilModelo + funil.js, MODELOS.RENOVACAO), o pedido sai de
// payloadDoFunil e quem grava é a ação do CRM `crmKanban/savePipelineWithStages`.
// A frase de cada etapa para a IA fica com o servidor, que grava a padrão do
// modelo quando ela não vem (Crm::Ai::DefaultStageCriteria).
// O modelo tem a camada da corretora (`camadas`), mas isso só decide se ele
// aparece na lista de modelos do CRM: escolhido pela chave, vale para qualquer
// conta com a carteira, e os textos dele (CRM_FUNIL.MODELOS.RENOVACAO) estão
// no catálogo base do CRM, em todo idioma.
// `podeCriar` é a regra do botão "Criar funil" do CRM (canManagePipelines).
// `criar()` devolve o funil criado ({ id, name, … }) ou lança o erro do pedido.
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useFunilModelo } from 'dashboard/routes/dashboard/crm/components/funil/useFunilModelo';
import {
  lerGoogleSync,
  lerMetaSync,
  lerResultados,
  payloadDoFunil,
} from 'dashboard/routes/dashboard/crm/components/funil/funilForm';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

export const MODELO_DAS_RENOVACOES = 'RENOVACAO';
// A IA da etapa fica com o padrão do servidor: nada de frase pedida daqui.
const SEM_IA = computed(() => false);

export const useCriarFunilDeRenovacoes = () => {
  const store = useStore();
  const { t } = useI18n();
  const { canManagePipelines } = useCrmPermissions();
  // O pacote da conta escolhe a variante do modelo, como na gaveta do CRM.
  const pacote = computed(
    () =>
      store.getters['accounts/getAccount']?.(store.getters.getCurrentAccountId)
        ?.autonomia_pacote || null
  );
  // O formulário de um funil novo, como a gaveta do CRM o começa.
  const form = reactive({
    name: '',
    description: t('CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_DESCRIPTION'),
    whenToUse: '',
    monthlyTarget: '',
    countsAsSale: true,
    outcomeLabels: lerResultados(),
    stages: [],
    metaSync: lerMetaSync(),
    googleSync: lerGoogleSync(),
  });
  const { modelo, escolherModelo } = useFunilModelo({
    t,
    ia: SEM_IA,
    form,
    editorSession: ref(0),
    pacote,
  });
  const criando = ref(false);

  const criar = async () => {
    criando.value = true;
    try {
      escolherModelo(MODELO_DAS_RENOVACOES);
      return await store.dispatch(
        'crmKanban/savePipelineWithStages',
        payloadDoFunil({
          form,
          pipeline: null,
          editando: false,
          ia: false,
          modelo: modelo.value,
        })
      );
    } finally {
      criando.value = false;
    }
  };

  return { podeCriar: canManagePipelines, criando, criar };
};
