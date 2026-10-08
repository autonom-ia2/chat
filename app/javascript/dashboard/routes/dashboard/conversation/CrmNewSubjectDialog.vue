<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// Novo assunto na conversa (#1143): escolher o funil e dar um nome ao assunto. O card nasce na primeira etapa do
// funil e vira o assunto atual. Sempre pede um card novo (new_subject): este diálogo nunca reaproveita um existente.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const emit = defineEmits(['created']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const pipelineId = ref(null);
const title = ref('');
const isLoadingPipelines = ref(false);
const isCreating = ref(false);

const pipelines = computed(() => store.getters['crmKanban/getPipelines'] || []);
const canCreate = computed(
  () =>
    pipelines.value.some(pipeline => pipeline.id === pipelineId.value) &&
    Boolean(title.value.trim()) &&
    !isCreating.value
);

const loadPipelines = async () => {
  isLoadingPipelines.value = true;
  try {
    const records = await store.dispatch('crmKanban/fetchPipelines');
    if (!pipelineId.value && records.length === 1) {
      pipelineId.value = records[0].id;
    }
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.LOAD_ERROR'));
  } finally {
    isLoadingPipelines.value = false;
  }
};

const open = async () => {
  title.value = '';
  pipelineId.value = null;
  dialogRef.value?.open();
  await loadPipelines();
};

const create = async () => {
  if (!canCreate.value) return;
  isCreating.value = true;
  try {
    const card = await store.dispatch('crmKanban/createCardFromConversation', {
      conversation_display_id: props.conversationId,
      pipeline_id: pipelineId.value,
      title: title.value.trim(),
      new_subject: true,
    });
    useAlert(t('CRM_KANBAN.CONVERSATION.SUBJECTS.CREATED'));
    dialogRef.value?.close();
    emit('created', card);
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CRM_KANBAN.CONVERSATION.SUBJECTS.NEW_TITLE')"
    :description="t('CRM_KANBAN.CONVERSATION.SUBJECTS.NEW_DESCRIPTION')"
    :confirm-button-label="t('CRM_KANBAN.CONVERSATION.SUBJECTS.CREATE')"
    :disable-confirm-button="!canCreate"
    :is-loading="isCreating"
    @confirm="create"
  >
    <fieldset class="grid gap-2">
      <legend class="mb-2 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.PIPELINE_QUESTION') }}
      </legend>
      <p
        v-if="isLoadingPipelines && !pipelines.length"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.LOADING') }}
      </p>
      <p v-else-if="!pipelines.length" class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_KANBAN.CONVERSATION.NO_PIPELINES') }}
      </p>
      <div v-else class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label
          v-for="pipeline in pipelines"
          :key="pipeline.id"
          class="flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border px-3 py-2 text-sm text-n-slate-12 transition focus-within:outline focus-within:outline-2 focus-within:outline-n-brand"
          :class="
            pipelineId === pipeline.id
              ? 'border-n-brand bg-n-blue-2'
              : 'border-n-weak hover:border-n-strong'
          "
        >
          <input
            v-model="pipelineId"
            type="radio"
            name="crm-new-subject-pipeline"
            class="size-4 accent-n-brand"
            :value="pipeline.id"
          />
          <span class="truncate">{{ pipeline.name }}</span>
        </label>
      </div>
    </fieldset>
    <Input
      v-model="title"
      :label="t('CRM_KANBAN.CONVERSATION.SUBJECTS.TITLE_LABEL')"
      :placeholder="t('CRM_KANBAN.CONVERSATION.SUBJECTS.TITLE_PLACEHOLDER')"
    />
  </Dialog>
</template>
