import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// Funis e etapas do CRM para as ações e condições de card da Automação. O estado fica no módulo:
// a tela de Automação carrega uma vez e os formulários de criar/editar só leem.
const pipelines = ref([]);
const stages = ref([]);
// Promessa da carga em andamento: a edição espera por ela antes de montar a regra salva.
let loading = Promise.resolve();

const CARD_STATUSES = ['open', 'won', 'lost'];

export const isCrmAutomationKey = key => key.includes('crm_');

const fetchCrmAutomationOptions = async () => {
  const { data } = await CrmKanbanAPI.getPipelines();
  const pipelineList = data.payload || [];
  const stageLists = await Promise.all(
    pipelineList.map(async pipeline => {
      const response = await CrmKanbanAPI.getStages(pipeline.id);
      return (response.data.payload || []).map(stage => ({
        id: stage.id,
        name: `${pipeline.name} › ${stage.name}`,
      }));
    })
  );
  pipelines.value = pipelineList.map(({ id, name }) => ({ id, name }));
  stages.value = stageLists.flat();
};

export const loadCrmAutomationOptions = () => {
  loading = fetchCrmAutomationOptions();
  return loading;
};

export const crmAutomationOptionsReady = () => loading.catch(() => {});

export function useCrmAutomationOptions() {
  const { t } = useI18n();

  const cardStatusOptions = computed(() =>
    CARD_STATUSES.map(id => ({
      id,
      name: t(`AUTOMATION.CRM_CARD_STATUS.${id.toUpperCase()}`),
    }))
  );

  return { pipelines, stages, cardStatusOptions };
}
