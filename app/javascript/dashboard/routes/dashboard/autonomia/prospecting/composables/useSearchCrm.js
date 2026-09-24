// Destino no CRM: funil e estágio dos resultados abertos e a configuração de
// CRM de cada busca do histórico.
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { alertError } from './searchAlerts';

export const useSearchCrm = state => {
  const { t } = useI18n();
  const {
    settings,
    crmPipelines,
    crmStages,
    crmForm,
    searchConfigStages,
    searchConfigForm,
    editingSearchConfigId,
    searches,
    selectedSearchId,
  } = state;

  const fetchCrmStages = async (pipelineId, preferredStageId = '') => {
    crmStages.value = [];
    crmForm.value.stage_id = '';
    if (!pipelineId) return;

    const { data } = await CrmKanbanAPI.getStages(pipelineId);
    crmStages.value = data.payload || [];
    crmForm.value.stage_id =
      preferredStageId ||
      settings.value?.default_crm_stage_id ||
      crmStages.value[0]?.id ||
      '';
  };

  const fetchCrmPipelines = async () => {
    try {
      const { data } = await CrmKanbanAPI.getPipelines();
      crmPipelines.value = data.payload || [];
      crmForm.value.pipeline_id = settings.value?.default_crm_pipeline_id || '';
      await fetchCrmStages(
        crmForm.value.pipeline_id,
        settings.value?.default_crm_stage_id
      );
    } catch {
      crmPipelines.value = [];
      crmStages.value = [];
    }
  };

  const applyCrmTarget = async search => {
    const pipelineId =
      search?.crm_pipeline_id || settings.value?.default_crm_pipeline_id || '';
    const stageId =
      search?.crm_stage_id || settings.value?.default_crm_stage_id || '';

    crmForm.value.pipeline_id = pipelineId;
    await fetchCrmStages(pipelineId, stageId);
  };

  const fetchSearchConfigStages = async (pipelineId, options = {}) => {
    searchConfigStages.value = [];
    if (!options.keepStage) searchConfigForm.value.crm_stage_id = '';
    if (!pipelineId) return;

    const { data } = await CrmKanbanAPI.getStages(pipelineId);
    searchConfigStages.value = data.payload || [];
    searchConfigForm.value.crm_stage_id =
      searchConfigForm.value.crm_stage_id ||
      searchConfigStages.value[0]?.id ||
      '';
  };

  const openSearchConfig = async search => {
    editingSearchConfigId.value = search.id;
    searchConfigForm.value = {
      crm_pipeline_id:
        search.crm_pipeline_id || settings.value?.default_crm_pipeline_id || '',
      crm_stage_id:
        search.crm_stage_id || settings.value?.default_crm_stage_id || '',
    };
    await fetchSearchConfigStages(searchConfigForm.value.crm_pipeline_id, {
      keepStage: true,
    });
  };

  const saveSearchConfig = async search => {
    if (!search?.id) return;

    try {
      const { data } = await AutonomiaProspectingAPI.updateSearch(search.id, {
        crm_pipeline_id: searchConfigForm.value.crm_pipeline_id,
        crm_stage_id: searchConfigForm.value.crm_stage_id,
      });
      searches.value = searches.value.map(item =>
        item.id === search.id ? data.payload : item
      );
      editingSearchConfigId.value = null;
      if (selectedSearchId.value === search.id) {
        await applyCrmTarget(data.payload);
      }
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.UPDATE_SEARCH'));
    }
  };

  return {
    fetchCrmPipelines,
    applyCrmTarget,
    fetchSearchConfigStages,
    openSearchConfig,
    saveSearchConfig,
  };
};
