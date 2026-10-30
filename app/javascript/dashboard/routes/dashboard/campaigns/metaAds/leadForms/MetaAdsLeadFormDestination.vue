<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// Para onde vai quem preenche um formulário (#2195): funil, etapa e, na primeira vez, se quem já preencheu nos
// últimos 90 dias também entra. Com muita gente, a caixa nasce desmarcada: são cards de uma vez, sem desfazer.
// Formulário arquivado não recebe ninguém novo: a única ação é trazer quem já preencheu, com o número no botão,
// sem guardar destino e sem ligar a Página.
const props = defineProps({
  form: { type: Object, required: true },
  pipelines: { type: Array, required: true },
  api: { type: Object, required: true },
  // Página parada: salvar volta a ligar a Página e os outros formulários dela.
  resumesPage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved', 'removed', 'close']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LEAD_FORMS.DESTINATION';
const BRING = 'CRM_KANBAN.META_ADS_HUB.LEAD_FORMS.BRING';
const PAST_CHECKED_UP_TO = 50;
const { t } = useI18n();

const dialog = ref(null);
const confirmRemove = ref(null);
// Qual das duas janelas está aberta: fechar a da vez fecha tudo; trocar de uma para a outra, não.
const step = ref('edit');
const closed = current => {
  if (step.value === current) emit('close');
};
const pipelineId = ref(
  props.form.destination?.pipeline_id ?? props.pipelines[0]?.id ?? null
);
const stageId = ref(props.form.destination?.stage_id ?? null);
const archived = props.form.status !== 'ACTIVE';
const pastCount = computed(() =>
  props.form.destination || archived ? 0 : props.form.past_count || 0
);
// A contagem parou no teto de leitura: o número é "N ou mais".
const shownCount = count =>
  props.form.past_count_truncated
    ? t('CRM_KANBAN.META_ADS_HUB.LEAD_FORMS.OR_MORE', { count })
    : count;
const texts = computed(() =>
  archived
    ? {
        title: t(
          `${BRING}.TITLE`,
          { count: shownCount(props.form.past_count), form: props.form.name },
          props.form.past_count
        ),
        hint: t(`${BRING}.HINT`),
        confirm: t(
          `${BRING}.CONFIRM`,
          { count: shownCount(props.form.past_count) },
          props.form.past_count
        ),
      }
    : {
        title: t(`${KEY}.TITLE`, { form: props.form.name }),
        hint: t(`${KEY}.HINT`),
        confirm: t(`${KEY}.SAVE`),
      }
);
const importPast = ref(
  pastCount.value > 0 && pastCount.value <= PAST_CHECKED_UP_TO
);
const saving = ref(false);
const failed = ref(false);

const pipelineOptions = computed(() =>
  props.pipelines.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const stages = computed(
  () => props.pipelines.find(item => item.id === pipelineId.value)?.stages || []
);
const stageOptions = computed(() =>
  stages.value.map(stage => ({ value: stage.id, label: stage.name }))
);

watch(
  pipelineId,
  () => {
    if (!stages.value.some(stage => stage.id === stageId.value)) {
      stageId.value = stages.value[0]?.id ?? null;
    }
  },
  { immediate: true }
);

const save = async () => {
  saving.value = true;
  failed.value = false;
  try {
    const choice = { pipelineId: pipelineId.value, stageId: stageId.value };
    const response = archived
      ? await props.api.bringPast(props.form.id, choice)
      : await props.api.saveDestination(props.form.id, {
          ...choice,
          importPast: importPast.value,
        });
    dialog.value?.close();
    emit('saved', { form: props.form, archived, ...response.data });
  } catch {
    failed.value = true;
  } finally {
    saving.value = false;
  }
};

const askRemove = () => {
  step.value = 'confirm';
  dialog.value?.close();
  confirmRemove.value?.open();
};

const remove = async () => {
  saving.value = true;
  failed.value = false;
  try {
    await props.api.removeDestination(props.form.id);
    emit('removed', props.form);
  } catch {
    step.value = 'edit';
    confirmRemove.value?.close();
    failed.value = true;
    dialog.value?.open();
  } finally {
    saving.value = false;
  }
};

onMounted(() => dialog.value?.open());
</script>

<template>
  <div class="contents">
    <Dialog
      ref="dialog"
      :title="texts.title"
      :description="texts.hint"
      :confirm-button-label="texts.confirm"
      :cancel-button-label="t(`${KEY}.CANCEL`)"
      :is-loading="saving"
      :disable-confirm-button="!pipelineId || !stageId"
      @confirm="save"
      @close="closed('edit')"
    >
      <div class="flex flex-col gap-4" data-lead-destination>
        <p
          v-if="resumesPage && !archived"
          data-lead-destination-resumes
          class="flex items-start gap-2 px-3 py-2 m-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
        >
          <span
            class="flex-none mt-0.5 i-lucide-circle-play size-4"
            aria-hidden="true"
          />
          {{ t(`${KEY}.RESUMES_PAGE`) }}
        </p>
        <div class="flex flex-col gap-1.5">
          <label
            for="lead-destination-pipeline"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ t(`${KEY}.PIPELINE`) }}
          </label>
          <ChoiceSelect
            v-model="pipelineId"
            trigger-id="lead-destination-pipeline"
            class="w-full"
            :options="pipelineOptions"
            :aria-label="t(`${KEY}.PIPELINE`)"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label
            for="lead-destination-stage"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ t(`${KEY}.STAGE`) }}
          </label>
          <ChoiceSelect
            v-model="stageId"
            trigger-id="lead-destination-stage"
            class="w-full"
            :options="stageOptions"
            :aria-label="t(`${KEY}.STAGE`)"
          />
        </div>
        <label
          v-if="pastCount"
          class="flex items-start gap-3 px-3 py-3 rounded-xl bg-n-alpha-1 min-h-11"
          data-lead-destination-past
        >
          <input
            v-model="importPast"
            type="checkbox"
            class="mt-0.5 size-4 flex-none accent-n-brand"
          />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{
                t(`${KEY}.PAST`, { count: shownCount(pastCount) }, pastCount)
              }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t(`${KEY}.PAST_HINT`) }}
            </span>
          </span>
        </label>
        <p
          v-if="failed"
          role="alert"
          class="px-3 py-2 m-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
        >
          {{ t('CRM_KANBAN.META_ADS_HUB.LEAD_FORMS.ACTION_FAILED') }}
        </p>
        <button
          v-if="form.destination"
          type="button"
          data-lead-destination-remove
          class="self-start px-0 text-sm font-medium bg-transparent border-0 min-h-11 text-n-ruby-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :disabled="saving"
          @click="askRemove"
        >
          {{ t(`${KEY}.REMOVE`) }}
        </button>
      </div>
    </Dialog>
    <Dialog
      ref="confirmRemove"
      type="alert"
      :title="t(`${KEY}.REMOVE_TITLE`, { form: form.name })"
      :description="t(`${KEY}.REMOVE_HINT`)"
      :confirm-button-label="t(`${KEY}.REMOVE_CONFIRM`)"
      :cancel-button-label="t(`${KEY}.REMOVE_KEEP`)"
      :is-loading="saving"
      @confirm="remove"
      @close="closed('confirm')"
    />
  </div>
</template>
