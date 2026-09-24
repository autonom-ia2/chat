<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const isOpen = ref(false);
const pipelineId = ref('');
const stageId = ref('');
const stages = ref([]);
const isLoadingPipelines = ref(false);
const isLoadingStages = ref(false);
const isCreatingCard = ref(false);

const accountId = computed(() => store.getters.getCurrentAccountId);
const globalConfig = computed(() => store.getters['globalConfig/get'] || {});
const pipelines = computed(() => store.getters['crmKanban/getPipelines'] || []);
const isEnabled = computed(
  () =>
    globalConfig.value.crmKanbanEnabled === true ||
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
);
const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const stageOptions = computed(() =>
  stages.value.map(stage => ({
    value: stage.id,
    label: stage.name,
  }))
);
const canCreateCard = computed(
  () =>
    isEnabled.value &&
    props.chat?.id &&
    pipelineId.value &&
    stageId.value &&
    !isCreatingCard.value &&
    !isLoadingPipelines.value &&
    !isLoadingStages.value
);

const loadPipelines = async () => {
  if (!isEnabled.value || isLoadingPipelines.value) return;
  isLoadingPipelines.value = true;
  try {
    const records = await store.dispatch('crmKanban/fetchPipelines');
    if (!pipelineId.value && records.length) {
      pipelineId.value = records[0].id;
    }
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.LOAD_ERROR'));
  } finally {
    isLoadingPipelines.value = false;
  }
};

const loadStages = async selectedPipelineId => {
  if (!selectedPipelineId) return;
  isLoadingStages.value = true;
  try {
    const response = await CrmKanbanAPI.getStages(selectedPipelineId);
    stages.value = response.data.payload || [];
    const stillAvailable = stages.value.some(
      stage => String(stage.id) === String(stageId.value)
    );
    if (!stillAvailable) {
      stageId.value = stages.value[0]?.id || '';
    }
  } catch {
    stages.value = [];
    stageId.value = '';
    useAlert(t('CRM_KANBAN.CONVERSATION.LOAD_ERROR'));
  } finally {
    isLoadingStages.value = false;
  }
};

const togglePanel = async () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) await loadPipelines();
};

const createCard = async () => {
  if (!canCreateCard.value) return;
  isCreatingCard.value = true;
  try {
    await store.dispatch('crmKanban/createCardFromConversation', {
      conversation_display_id: props.chat.id,
      pipeline_id: pipelineId.value,
      stage_id: stageId.value,
    });
    useAlert(t('CRM_KANBAN.CONVERSATION.CARD_READY'));
    isOpen.value = false;
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.CREATE_ERROR'));
  } finally {
    isCreatingCard.value = false;
  }
};

const openCrm = () => {
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: accountId.value },
  });
};

watch(pipelineId, newPipelineId => {
  if (newPipelineId) loadStages(newPipelineId);
});
</script>

<template>
  <div v-show="isEnabled" class="relative">
    <NextButton
      icon="i-lucide-kanban"
      :label="t('CRM_KANBAN.CONVERSATION.TITLE')"
      slate
      faded
      sm
      :title="t('CRM_KANBAN.CONVERSATION.DESCRIPTION')"
      @click="togglePanel"
    />
    <div
      v-if="isOpen"
      class="absolute right-0 top-10 z-50 w-80 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-lg"
    >
      <div class="mb-3 flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.CONVERSATION.TITLE') }}
          </p>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CRM_KANBAN.CONVERSATION.DESCRIPTION') }}
          </p>
        </div>
        <NextButton
          icon="i-lucide-external-link"
          xs
          ghost
          slate
          :title="t('CRM_KANBAN.CONVERSATION.OPEN_CRM')"
          @click="openCrm"
        />
      </div>

      <div v-if="pipelineOptions.length" class="grid gap-2">
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.CONVERSATION.PIPELINE') }}
          </span>
          <ChoiceSelect
            v-model="pipelineId"
            :options="pipelineOptions"
            :aria-label="t('CRM_KANBAN.CONVERSATION.PIPELINE')"
            class="w-full"
          />
        </label>

        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.CONVERSATION.STAGE') }}
          </span>
          <ChoiceSelect
            v-model="stageId"
            :options="stageOptions"
            :aria-label="t('CRM_KANBAN.CONVERSATION.STAGE')"
            :disabled="isLoadingStages"
            class="w-full"
          />
        </label>

        <NextButton
          :label="t('CRM_KANBAN.CONVERSATION.CREATE_CARD')"
          icon="i-lucide-plus"
          blue
          sm
          class="w-full justify-center"
          :disabled="!canCreateCard"
          :is-loading="isCreatingCard"
          @click="createCard"
        />
      </div>
      <p v-else class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('CRM_KANBAN.CONVERSATION.NO_PIPELINES') }}
      </p>
    </div>
  </div>
</template>
