<script setup>
// Janela "Enviar ao CRM" (#680), a mesma na busca, no painel do lead e em
// Listas. Como no Orth: com um funil só, ele já vem escolhido; com mais de um,
// fica vazio de propósito para ninguém mandar para o funil errado. O destino
// da busca ou da conta entra como sugestão quando ainda existe. Manda em lotes
// de até 30 e termina num resumo do que aconteceu com cada lead.
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import CrmSendSummary from './CrmSendSummary.vue';
import { sendInBatches } from '../../utils/crmSend';

const props = defineProps({
  leads: { type: Array, required: true },
  suggestedPipelineId: { type: [String, Number], default: '' },
  suggestedStageId: { type: [String, Number], default: '' },
});

const emit = defineEmits(['close', 'sent']);

// A janela cobre a tela inteira, inclusive o canto do lançador do Guia (#646).
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const route = useRoute();
const titleId = useId();

const phase = ref('loading');
const pipelines = ref([]);
const stages = ref([]);
const pipelineId = ref('');
const stageId = ref('');
const sentCount = ref(0);
const summary = ref(null);

const sameId = (left, right) => String(left) === String(right);
const crmUrl = computed(() => `/app/accounts/${route.params.accountId}/crm`);
const toChoices = items =>
  items.map(item => ({ value: item.id, label: item.name }));
const pipelineChoices = computed(() => toChoices(pipelines.value));
const stageChoices = computed(() => toChoices(stages.value));
const selectedPipeline = computed(() =>
  pipelines.value.find(item => sameId(item.id, pipelineId.value))
);
const selectedStage = computed(() =>
  stages.value.find(item => sameId(item.id, stageId.value))
);
const canSend = computed(() =>
  Boolean(selectedPipeline.value && selectedStage.value)
);
const isSending = computed(() => phase.value === 'sending');

const loadStages = async preferredStageId => {
  stages.value = [];
  stageId.value = '';
  if (!pipelineId.value) return;

  const { data } = await CrmKanbanAPI.getStages(pipelineId.value);
  stages.value = data.payload || [];
  const preferred = stages.value.find(item =>
    sameId(item.id, preferredStageId)
  );
  stageId.value = (preferred || stages.value[0])?.id ?? '';
};

const initialPipelineId = () => {
  const suggested = pipelines.value.find(item =>
    sameId(item.id, props.suggestedPipelineId)
  );
  if (suggested) return suggested.id;
  return pipelines.value.length === 1 ? pipelines.value[0].id : '';
};

onMounted(async () => {
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    pipelines.value = data.payload || [];
    if (!pipelines.value.length) {
      phase.value = 'empty';
      return;
    }
    pipelineId.value = initialPipelineId();
    await loadStages(props.suggestedStageId);
    phase.value = 'form';
  } catch {
    phase.value = 'error';
  }
});

const changePipeline = async () => {
  try {
    await loadStages('');
  } catch {
    phase.value = 'error';
  }
};

const send = async () => {
  if (!canSend.value || isSending.value) return;

  phase.value = 'sending';
  sentCount.value = 0;
  const leadIds = props.leads.map(lead => lead.id);
  const request = batch =>
    AutonomiaProspectingAPI.createCrmCards({
      leadIds: batch,
      pipelineId: selectedPipeline.value.id,
      stageId: selectedStage.value.id,
    });

  summary.value = await sendInBatches(leadIds, request, done => {
    sentCount.value = done;
  });
  phase.value = 'done';
  emit('sent', summary.value);
};

const close = () => {
  if (!isSending.value) emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/30 px-4"
    @click.self="close"
  >
    <section
      role="dialog"
      aria-modal="true"
      :aria-labelledby="titleId"
      class="grid max-h-[90vh] w-full max-w-md gap-4 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="flex items-start justify-between gap-3">
        <h2 :id="titleId" class="text-base font-semibold text-n-slate-12">
          {{ t('PROSPECTING.CRM_SEND.TITLE') }}
        </h2>
        <button
          type="button"
          data-test="crm-send-close"
          class="flex size-11 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
          :aria-label="t('PROSPECTING.CRM_SEND.CLOSE')"
          :disabled="isSending"
          @click="close"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </header>

      <p v-if="phase === 'loading'" class="text-sm text-n-slate-11">
        {{ t('PROSPECTING.CRM_SEND.LOADING') }}
      </p>

      <div
        v-else-if="phase === 'empty' || phase === 'error'"
        class="grid gap-3 rounded-md border border-n-weak bg-n-solid-2 p-4"
      >
        <template v-if="phase === 'empty'">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('PROSPECTING.CRM_SEND.EMPTY_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ t('PROSPECTING.CRM_SEND.EMPTY_DESCRIPTION') }}
          </p>
        </template>
        <p v-else role="alert" class="text-sm text-n-slate-11">
          {{ t('PROSPECTING.CRM_SEND.LOAD_ERROR') }}
        </p>
        <a
          :href="crmUrl"
          data-test="crm-send-create-pipeline"
          class="inline-flex min-h-11 w-fit items-center gap-2 rounded-md bg-n-brand px-3 text-sm font-medium text-white"
        >
          {{ t('PROSPECTING.CRM_SEND.CREATE_PIPELINE') }}
        </a>
      </div>

      <CrmSendSummary
        v-else-if="phase === 'done'"
        :summary="summary"
        :leads="leads"
      />

      <template v-else>
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('PROSPECTING.CRM_SEND.PIPELINE') }}
          </span>
          <ChoiceSelect
            v-model="pipelineId"
            :options="pipelineChoices"
            :placeholder="t('PROSPECTING.CRM_SEND.PIPELINE_PLACEHOLDER')"
            :aria-label="t('PROSPECTING.CRM_SEND.PIPELINE')"
            :disabled="isSending"
            @change="changePipeline"
          />
        </label>
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('PROSPECTING.CRM_SEND.STAGE') }}
          </span>
          <ChoiceSelect
            v-model="stageId"
            :options="stageChoices"
            :placeholder="t('PROSPECTING.CRM_SEND.STAGE_PLACEHOLDER')"
            :aria-label="t('PROSPECTING.CRM_SEND.STAGE')"
            :disabled="isSending || !stageChoices.length"
          />
        </label>
        <p class="text-sm text-n-slate-12" aria-live="polite">
          {{
            isSending
              ? t('PROSPECTING.CRM_SEND.SENDING', {
                  done: sentCount,
                  total: leads.length,
                })
              : canSend
                ? t('PROSPECTING.CRM_SEND.CONFIRMATION', {
                    count: leads.length,
                    pipeline: selectedPipeline.name,
                    stage: selectedStage.name,
                  })
                : t('PROSPECTING.CRM_SEND.CHOOSE_DESTINATION')
          }}
        </p>
      </template>

      <footer class="flex justify-end gap-2">
        <button
          v-if="phase !== 'done'"
          type="button"
          data-test="crm-send-cancel"
          class="min-h-11 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="isSending"
          @click="close"
        >
          {{ t('PROSPECTING.CRM_SEND.CANCEL') }}
        </button>
        <button
          v-if="phase === 'form' || phase === 'sending'"
          type="button"
          data-test="crm-send-submit"
          class="min-h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!canSend || isSending"
          @click="send"
        >
          {{ t('PROSPECTING.CRM_SEND.SEND') }}
        </button>
        <button
          v-if="phase === 'done'"
          type="button"
          class="min-h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white"
          @click="close"
        >
          {{ t('PROSPECTING.CRM_SEND.CLOSE') }}
        </button>
      </footer>
    </section>
  </div>
</template>
