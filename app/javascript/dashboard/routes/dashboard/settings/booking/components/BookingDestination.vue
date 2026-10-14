<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// "Quem marcar vai para o funil X, etapa Y, com Z." O padrão já vem escolhido
// (primeiro funil e primeira etapa); "Alterar" abre a escolha (J3-A10). A prévia
// também abre a escolha pelo "Resolver" quando falta o funil (startEditing).
const props = defineProps({
  pipelineId: { type: Number, default: null },
  stageId: { type: Number, default: null },
  peopleNames: { type: String, default: '' },
  canManage: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);
const { t } = useI18n();

const pipelines = ref([]);
const stagesByPipeline = ref({});
const failed = ref(false);
// Os funis já chegaram: antes disso a frase espera, para não mostrar um nome
// genérico no lugar do funil escolhido.
const loaded = ref(false);
const formRef = ref(null);
const editing = ref(false);
const draft = ref({ pipelineId: null, stageId: null });

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
    pipelines.value = data.payload || [];
  } catch {
    failed.value = true;
  }
  await loadStages(props.pipelineId);
  loaded.value = true;
});

const nameOf = (list, id) => list.find(item => item.id === id)?.name || '';
const pipelineName = computed(() => nameOf(pipelines.value, props.pipelineId));
const stageName = computed(() =>
  nameOf(stagesByPipeline.value[props.pipelineId] || [], props.stageId)
);
const people = computed(() => props.peopleNames || t('BOOKING.PREVIEW.NOBODY'));

const sentence = computed(() => {
  if (!loaded.value) return '';
  if (!props.pipelineId) {
    return t('BOOKING.PREVIEW.DESTINATION_NO_PIPELINE', {
      people: people.value,
    });
  }
  return t('BOOKING.PREVIEW.DESTINATION', {
    pipeline: pipelineName.value || t('BOOKING.PREVIEW.DEFAULT_PIPELINE'),
    stage: stageName.value || t('BOOKING.PREVIEW.DEFAULT_STAGE'),
    people: people.value,
  });
});

const pipelineOptions = computed(() =>
  pipelines.value.map(item => ({ value: item.id, label: item.name }))
);
const stageOptions = computed(() =>
  (stagesByPipeline.value[draft.value.pipelineId] || []).map(item => ({
    value: item.id,
    label: item.name,
  }))
);

const firstStage = pipelineId =>
  stagesByPipeline.value[pipelineId]?.[0]?.id ?? null;

const startEditing = async () => {
  draft.value = { pipelineId: props.pipelineId, stageId: props.stageId };
  editing.value = true;
  await nextTick();
  formRef.value?.querySelector('button')?.focus();
};

defineExpose({ startEditing });

const choosePipeline = async pipelineId => {
  draft.value = { pipelineId, stageId: null };
  await loadStages(pipelineId);
  draft.value = { pipelineId, stageId: firstStage(pipelineId) };
};

const save = () => {
  emit('save', { ...draft.value });
  editing.value = false;
};

watch(
  () => props.pipelineId,
  pipelineId => loadStages(pipelineId)
);
</script>

<template>
  <section
    data-destination
    class="flex flex-col gap-4 p-5 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <p class="flex-1 m-0 text-base text-n-slate-12 min-w-60">
        {{ sentence }}
      </p>
      <button
        v-if="canManage && !editing"
        type="button"
        data-alter
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
      data-destination-form
      class="flex flex-col gap-4"
    >
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.PREVIEW.PIPELINE_LABEL') }}
          </p>
          <ChoiceSelect
            data-pipeline
            :model-value="draft.pipelineId ?? ''"
            :options="pipelineOptions"
            :aria-label="t('BOOKING.PREVIEW.PIPELINE_LABEL')"
            @update:model-value="choosePipeline"
          />
        </div>
        <div class="flex flex-col gap-2">
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('BOOKING.PREVIEW.STAGE_LABEL') }}
          </p>
          <ChoiceSelect
            data-stage
            :model-value="draft.stageId ?? ''"
            :options="stageOptions"
            :aria-label="t('BOOKING.PREVIEW.STAGE_LABEL')"
            @update:model-value="draft = { ...draft, stageId: $event }"
          />
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-destination-save
          :disabled="saving || !draft.pipelineId || !draft.stageId"
          class="inline-flex items-center min-h-11 px-5 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          @click="save"
        >
          {{ t('BOOKING.PREVIEW.SAVE') }}
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
