<script setup>
import { computed, ref, watch, nextTick, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmOpportunityContactPicker from './CrmOpportunityContactPicker.vue';

const props = defineProps({
  pipelines: { type: Array, required: true },
  pipelineId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['save']);
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.OPPORTUNITY.${key}`);
const formId = `crm-opportunity-${useId()}`;
const element = ref(null);
const mode = ref('existing');
const contact = ref(null);
const more = ref(false);
const sending = ref(false);
const error = ref('');
const stageError = ref(false);
const stageRequest = useAbortableRequest();
const loadedStages = ref(props.stages);
const form = ref({
  title: '',
  pipelineId: props.pipelineId,
  stageId: props.stages[0]?.id || '',
  valueAmount: '',
  ownerId: '',
  currency: 'BRL',
  description: '',
  priority: 'medium',
  expectedCloseAt: '',
  score: 0,
  inboxId: '',
});
const initial = JSON.stringify(form.value);
const dirty = computed(
  () => Boolean(contact.value) || JSON.stringify(form.value) !== initial
);
const pipelineOptions = computed(() =>
  props.pipelines.map(item => ({ value: item.id, label: item.name }))
);
const stageOptions = computed(() =>
  loadedStages.value.map(item => ({ value: item.id, label: item.name }))
);
const ownerOptions = computed(() => [
  { value: '', label: t('CRM_KANBAN.DRAWER.USE_CURRENT_USER') },
  ...props.agents.map(item => ({ value: item.id, label: item.name })),
]);
const inboxOptions = computed(() => [
  { value: '', label: t('CRM_KANBAN.DRAWER.NO_INBOX') },
  ...props.inboxes.map(item => ({ value: item.id, label: item.name })),
]);
const priorityOptions = computed(() =>
  ['low', 'medium', 'high', 'urgent'].map(value => ({
    value,
    label: t(`CRM_KANBAN.PRIORITY.${value.toUpperCase()}`),
  }))
);
const canSave = computed(
  () =>
    props.canManage &&
    !sending.value &&
    !stageRequest.isPending.value &&
    !stageError.value &&
    Boolean(form.value.title.trim()) &&
    pipelineOptions.value.some(
      item => String(item.value) === String(form.value.pipelineId)
    ) &&
    stageOptions.value.some(
      item => String(item.value) === String(form.value.stageId)
    ) &&
    (mode.value === 'none' || Boolean(contact.value?.id))
);
const summary = computed(() =>
  label(mode.value === 'none' ? 'SUMMARY_NONE' : 'SUMMARY_EXISTING')
);
const loadStages = async () => {
  stageError.value = false;
  loadedStages.value = [];
  form.value.stageId = '';
  try {
    const response = await stageRequest.run(() =>
      CrmKanbanAPI.getStages(form.value.pipelineId)
    );
    if (!response) return;
    loadedStages.value = response.data.payload;
    form.value.stageId = loadedStages.value[0]?.id || '';
  } catch {
    stageError.value = true;
  }
};
watch(() => form.value.pipelineId, loadStages, { flush: 'sync' });
watch(
  () => props.stages,
  stages => {
    if (String(form.value.pipelineId) !== String(props.pipelineId)) return;
    loadedStages.value = stages;
    if (!stages.some(item => item.id === form.value.stageId))
      form.value.stageId = '';
  }
);
const changeMode = next => {
  if (sending.value) return;
  mode.value = next;
  contact.value = null;
  error.value = '';
};
let requestKey = crypto.randomUUID();
let submitted = '';
const submit = async () => {
  if (!canSave.value) return;
  if (element.value.querySelector(':invalid')) {
    more.value = true;
    await nextTick();
    element.value.reportValidity();
    return;
  }
  const data = form.value;
  const payload = {
    title: data.title.trim(),
    description: data.description.trim(),
    pipeline_id: data.pipelineId,
    stage_id: data.stageId,
    value_cents: Math.round(Number(data.valueAmount || 0) * 100),
    currency: data.currency.trim() || 'BRL',
    priority: data.priority,
    score: Number(data.score || 0),
    expected_close_at: data.expectedCloseAt || null,
    ...(data.ownerId ? { owner_id: data.ownerId } : {}),
    ...(data.inboxId ? { inbox_id: data.inboxId } : {}),
    ...(mode.value === 'existing' && contact.value
      ? { contact_id: contact.value.id }
      : {}),
  };
  const fingerprint = JSON.stringify(payload);
  if (submitted && fingerprint !== submitted) requestKey = crypto.randomUUID();
  submitted = fingerprint;
  sending.value = true;
  error.value = '';
  emit('save', { ...payload, idempotencyKey: requestKey }, () => {
    sending.value = false;
    error.value = label('SAVE_ERROR');
  });
};
defineExpose({ dirty, sending, canSave, formId, summary });
</script>

<template>
  <form
    :id="formId"
    ref="element"
    class="grid min-w-0 gap-6"
    data-crm-opportunity-form
    novalidate
    @submit.prevent="submit"
  >
    <div
      v-if="error"
      role="alert"
      class="rounded-xl bg-n-ruby-3 p-4 text-sm leading-6 text-n-ruby-11"
    >
      {{ error }}
    </div>
    <fieldset :disabled="sending" class="m-0 grid min-w-0 gap-6 border-0 p-0">
      <section class="grid min-w-0 gap-4" data-opportunity-relationship>
        <header class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex items-center gap-3">
            <div
              class="flex size-7 items-center justify-center rounded-full bg-n-brand/10 text-sm font-semibold text-n-blue-11"
              aria-hidden="true"
            >
              {{ label('STEP_ONE') }}
            </div>
            <h3 class="m-0 text-base font-semibold text-n-slate-12">
              {{ label('RELATIONSHIP') }}
            </h3>
          </div>
          <Button
            v-if="mode !== 'none'"
            type="button"
            sm
            ghost
            slate
            :label="label('CONTINUE_NONE')"
            :disabled="sending"
            @click="changeMode('none')"
          />
        </header>
        <div
          v-if="mode === 'none'"
          class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          data-opportunity-unlinked
        >
          <span
            class="i-lucide-info mt-0.5 size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <div class="grid gap-2">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{ label('NO_LINK_TITLE') }}
            </p>
            <p class="m-0 text-sm leading-6 text-n-slate-11">
              {{ label('NO_LINK_HELP') }}
            </p>
            <Button
              type="button"
              sm
              link
              icon="i-lucide-link-2"
              class="justify-self-start"
              :label="label('USE_EXISTING')"
              :disabled="sending"
              @click="changeMode('existing')"
            />
          </div>
        </div>
        <CrmOpportunityContactPicker
          v-else
          v-model="contact"
          :disabled="sending"
        />
      </section>
      <section
        class="grid min-w-0 gap-4 border-t border-n-weak pt-5"
        data-opportunity-details
      >
        <header class="flex items-center gap-3">
          <div
            class="flex size-7 items-center justify-center rounded-full bg-n-brand/10 text-sm font-semibold text-n-blue-11"
            aria-hidden="true"
          >
            {{ label('STEP_TWO') }}
          </div>
          <h3 class="m-0 text-base font-semibold text-n-slate-12">
            {{ label('OPPORTUNITY') }}
          </h3>
        </header>
        <Input
          v-model="form.title"
          required
          :label="t('CRM_KANBAN.DRAWER.TITLE_LABEL')"
          :placeholder="t('CRM_KANBAN.DRAWER.TITLE_PLACEHOLDER')"
          :disabled="sending"
        />
        <div class="grid min-w-0 grid-cols-1 gap-4 min-[440px]:grid-cols-2">
          <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
            <span>{{ label('PIPELINE') }}</span>
            <ChoiceSelect
              v-model="form.pipelineId"
              :options="pipelineOptions"
              :aria-label="label('PIPELINE')"
              :disabled="sending"
            />
          </label>
          <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
            <span>{{ t('CRM_KANBAN.DRAWER.STAGE') }}</span>
            <ChoiceSelect
              v-model="form.stageId"
              :options="stageOptions"
              :aria-label="t('CRM_KANBAN.DRAWER.STAGE')"
              :placeholder="
                label(
                  stageRequest.isPending.value
                    ? 'LOADING_STAGES'
                    : 'SELECT_STAGE'
                )
              "
              :disabled="sending || stageRequest.isPending.value"
            />
          </label>
          <Input
            v-model="form.valueAmount"
            type="number"
            min="0"
            step="0.01"
            :label="t('CRM_KANBAN.DRAWER.VALUE')"
            :placeholder="t('CRM_KANBAN.DRAWER.VALUE_PLACEHOLDER')"
            :disabled="sending"
          />
          <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
            <span>{{ t('CRM_KANBAN.DRAWER.OWNER') }}</span>
            <ChoiceSelect
              v-model="form.ownerId"
              :options="ownerOptions"
              :aria-label="t('CRM_KANBAN.DRAWER.OWNER')"
              :disabled="sending || !canManage"
            />
          </label>
        </div>
        <div
          v-if="stageError"
          role="alert"
          class="flex flex-wrap items-center gap-2 text-sm text-n-ruby-11"
        >
          <span>{{ label('STAGE_ERROR') }}</span>
          <Button
            type="button"
            sm
            ghost
            :label="label('RETRY')"
            :disabled="sending"
            @click="loadStages"
          />
        </div>
        <section class="rounded-xl border border-n-weak bg-n-solid-1">
          <button
            type="button"
            class="flex min-h-12 w-full items-center gap-2 p-4 text-start text-sm font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-n-brand"
            :aria-expanded="more"
            :aria-controls="`${formId}-options`"
            :disabled="sending"
            @click="more = !more"
          >
            <span
              class="i-lucide-sliders-horizontal size-4 text-n-slate-11"
              aria-hidden="true"
            />
            <span>{{ label('MORE_OPTIONS') }}</span>
            <span
              class="i-lucide-chevron-down ms-auto size-4 text-n-slate-11"
              :class="{ 'rotate-180': more }"
              aria-hidden="true"
            />
          </button>
          <div
            v-show="more"
            :id="`${formId}-options`"
            class="grid min-w-0 gap-4 border-t border-n-weak p-4"
          >
            <TextArea
              :id="`${formId}-description`"
              v-model="form.description"
              :label="t('CRM_KANBAN.DRAWER.DESCRIPTION_LABEL')"
              :placeholder="t('CRM_KANBAN.DRAWER.DESCRIPTION_PLACEHOLDER')"
              :disabled="sending"
              auto-height
            />
            <div class="grid min-w-0 grid-cols-1 gap-4 min-[440px]:grid-cols-2">
              <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
                <!-- Preserve every native priority, including urgent. -->
                <span>{{ t('CRM_KANBAN.DRAWER.PRIORITY') }}</span>
                <ChoiceSelect
                  v-model="form.priority"
                  :options="priorityOptions"
                  :aria-label="t('CRM_KANBAN.DRAWER.PRIORITY')"
                  :disabled="sending"
                />
              </label>
              <Input
                v-model="form.expectedCloseAt"
                type="date"
                :label="t('CRM_KANBAN.DRAWER.EXPECTED_CLOSE_AT')"
                :disabled="sending"
              />
              <Input
                v-model="form.score"
                type="number"
                min="0"
                max="100"
                step="1"
                :label="t('CRM_KANBAN.DRAWER.SCORE')"
                :disabled="sending"
              />
              <Input
                v-model="form.currency"
                :label="label('CURRENCY')"
                :disabled="sending"
              />
            </div>
            <label
              v-if="inboxes.length"
              class="grid min-w-0 gap-2 text-sm text-n-slate-12"
            >
              <!-- Inbox selection remains optional; it does not start a conversation. -->
              <span>{{ t('CRM_KANBAN.DRAWER.INBOX') }}</span>
              <ChoiceSelect
                v-model="form.inboxId"
                :options="inboxOptions"
                :aria-label="t('CRM_KANBAN.DRAWER.INBOX')"
                :disabled="sending"
              />
            </label>
          </div>
        </section>
      </section>
    </fieldset>
  </form>
</template>
