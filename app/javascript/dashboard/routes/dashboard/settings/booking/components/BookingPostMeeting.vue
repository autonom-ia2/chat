<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingChoiceCards from './BookingChoiceCards.vue';

// "Depois da reunião" (#1193, J4-A7), na prévia: quando o agente marca
// "Aconteceu", para qual etapa o card vai e se o sistema pergunta antes ou move
// sozinho. Sem etapa, o card fica onde está. Salva sozinho (PATCH só com
// `post_meeting`) e devolve a página atualizada.
const props = defineProps({
  pageId: { type: Number, required: true },
  // { mode: 'ask'|'auto', stage_id, pipeline_id } da página.
  postMeeting: { type: Object, default: () => ({}) },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const MODES = ['ask', 'auto'];
const pipelines = ref([]);
const stagesByPipeline = ref({});
const loaded = ref(false);
const failed = ref(false);
const editing = ref(false);
const saving = ref(false);
const saveFailed = ref(false);
const formRef = ref(null);
const draft = ref({ mode: 'ask', pipelineId: null, stageId: null });

const loadStages = async pipelineId => {
  if (!pipelineId || stagesByPipeline.value[pipelineId]) return;
  try {
    const { data } = await CrmKanbanAPI.getStages(pipelineId);
    stagesByPipeline.value = {
      ...stagesByPipeline.value,
      [pipelineId]: data.payload || [],
    };
  } catch {
    failed.value = true;
  }
};

onMounted(async () => {
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    // Funil arquivado não recebe card: o servidor recusa a etapa dele.
    pipelines.value = (data.payload || []).filter(
      item => item.status !== 'archived'
    );
  } catch {
    failed.value = true;
  }
  await loadStages(props.postMeeting?.pipeline_id);
  loaded.value = true;
});

const mode = computed(() =>
  MODES.includes(props.postMeeting?.mode) ? props.postMeeting.mode : 'ask'
);
const stageName = computed(
  () =>
    (stagesByPipeline.value[props.postMeeting?.pipeline_id] || []).find(
      stage => stage.id === props.postMeeting?.stage_id
    )?.name || ''
);

const sentence = computed(() => {
  if (!loaded.value) return '';
  if (!props.postMeeting?.stage_id) return t('BOOKING.POST_MEETING.OFF');
  const stage = stageName.value || t('BOOKING.POST_MEETING.SOME_STAGE');
  return t(`BOOKING.POST_MEETING.SUMMARY_${mode.value.toUpperCase()}`, {
    stage,
  });
});

const modeOptions = computed(() =>
  MODES.map(value => ({
    value,
    label: t(`BOOKING.POST_MEETING.MODES.${value.toUpperCase()}.LABEL`),
    hint: t(`BOOKING.POST_MEETING.MODES.${value.toUpperCase()}.HINT`),
  }))
);
const pipelineOptions = computed(() =>
  pipelines.value.map(item => ({ value: item.id, label: item.name }))
);
const stageOptions = computed(() =>
  (stagesByPipeline.value[draft.value.pipelineId] || []).map(item => ({
    value: item.id,
    label: item.name,
  }))
);

const startEditing = async () => {
  draft.value = {
    mode: mode.value,
    pipelineId: props.postMeeting?.pipeline_id ?? null,
    stageId: props.postMeeting?.stage_id ?? null,
  };
  saveFailed.value = false;
  editing.value = true;
  await nextTick();
  formRef.value?.querySelector('button, input')?.focus();
};

const choosePipeline = async pipelineId => {
  draft.value = { ...draft.value, pipelineId, stageId: null };
  await loadStages(pipelineId);
};

const save = async postMeeting => {
  saving.value = true;
  saveFailed.value = false;
  try {
    const { data } = await BookingPagesAPI.update(props.pageId, {
      post_meeting: postMeeting,
    });
    emit('saved', data.payload);
    editing.value = false;
  } catch {
    saveFailed.value = true;
  } finally {
    saving.value = false;
  }
};

const saveDraft = () =>
  save({ mode: draft.value.mode, stage_id: draft.value.stageId });
const turnOff = () => save({ stage_id: null });
</script>

<template>
  <section
    data-post-meeting
    class="flex flex-col gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col flex-1 gap-1 min-w-60">
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('BOOKING.POST_MEETING.TITLE') }}
        </p>
        <p data-post-meeting-sentence class="m-0 text-base text-n-slate-12">
          {{ sentence }}
        </p>
      </div>
      <button
        v-if="canManage && !editing"
        type="button"
        data-post-meeting-alter
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-semibold text-n-blue-11 ring-1 ring-inset ring-n-blue-7 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="startEditing"
      >
        <span class="i-lucide-pencil size-4" aria-hidden="true" />
        {{ t('BOOKING.PREVIEW.ALTER') }}
      </button>
    </div>
    <p v-if="failed" role="status" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.PREVIEW.PIPELINES_ERROR') }}
    </p>
    <div
      v-if="editing"
      ref="formRef"
      data-post-meeting-form
      class="flex flex-col gap-4"
    >
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.PREVIEW.PIPELINE_LABEL') }}
          </p>
          <ChoiceSelect
            data-post-meeting-pipeline
            :model-value="draft.pipelineId ?? ''"
            :options="pipelineOptions"
            :aria-label="t('BOOKING.PREVIEW.PIPELINE_LABEL')"
            @update:model-value="choosePipeline"
          />
        </div>
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.POST_MEETING.STAGE_LABEL') }}
          </p>
          <ChoiceSelect
            data-post-meeting-stage
            :model-value="draft.stageId ?? ''"
            :options="stageOptions"
            :aria-label="t('BOOKING.POST_MEETING.STAGE_LABEL')"
            @update:model-value="draft = { ...draft, stageId: $event }"
          />
        </div>
      </div>
      <BookingChoiceCards
        :legend="t('BOOKING.POST_MEETING.MODE_LABEL')"
        :options="modeOptions"
        :model-value="draft.mode"
        @update:model-value="draft = { ...draft, mode: $event }"
      />
      <p v-if="saveFailed" role="alert" class="m-0 text-base text-n-ruby-11">
        {{ t('BOOKING.POST_MEETING.SAVE_ERROR') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-post-meeting-save
          :disabled="saving || !draft.stageId"
          class="inline-flex items-center min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          @click="saveDraft"
        >
          {{ t('BOOKING.PREVIEW.SAVE') }}
        </button>
        <button
          v-if="postMeeting.stage_id"
          type="button"
          data-post-meeting-off
          :disabled="saving"
          class="inline-flex items-center min-h-11 px-5 rounded-xl text-base font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak disabled:opacity-60"
          @click="turnOff"
        >
          {{ t('BOOKING.POST_MEETING.TURN_OFF') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center min-h-11 px-5 rounded-xl text-base font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak"
          @click="editing = false"
        >
          {{ t('BOOKING.PREVIEW.CANCEL') }}
        </button>
      </div>
    </div>
  </section>
</template>
