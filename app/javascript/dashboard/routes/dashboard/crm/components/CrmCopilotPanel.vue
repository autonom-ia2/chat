<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const loadingTask = ref('');
const result = ref('');
const tone = ref('professional');
const refineText = ref('');
const toneOptions = computed(() => [
  { value: 'professional', label: t('CRM_KANBAN.COPILOT.TONE_PROFESSIONAL') },
  { value: 'casual', label: t('CRM_KANBAN.COPILOT.TONE_CASUAL') },
  { value: 'friendly', label: t('CRM_KANBAN.COPILOT.TONE_FRIENDLY') },
  { value: 'confident', label: t('CRM_KANBAN.COPILOT.TONE_CONFIDENT') },
  { value: 'direct', label: t('CRM_KANBAN.COPILOT.TONE_DIRECT') },
]);

const isLoading = computed(() => !!loadingTask.value);

const run = async (task, opts = {}) => {
  if (isLoading.value) return;
  loadingTask.value = task;
  try {
    const { data } = await AutonomiaCopilotAPI.run(props.conversationId, {
      task,
      ...opts,
    });
    if (data.available && data.text) {
      result.value = data.text;
    } else {
      useAlert(t('CRM_KANBAN.COPILOT.UNAVAILABLE'));
    }
  } catch {
    useAlert(t('CRM_KANBAN.COPILOT.ERROR'));
  } finally {
    loadingTask.value = '';
  }
};

const rewrite = () => run('rewrite', { draft: result.value, tone: tone.value });

const refine = () => {
  if (!refineText.value.trim()) return;
  run('refine', { draft: result.value, instruction: refineText.value.trim() });
};

const insert = () => {
  if (!result.value) return;
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, result.value);
  useAlert(t('CRM_KANBAN.COPILOT.INSERTED'));
};
</script>

<template>
  <section class="my-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-3">
    <div class="mb-1 flex items-center gap-2">
      <span class="i-lucide-sparkles text-n-slate-11" />
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.COPILOT.TITLE') }}
      </p>
    </div>
    <p class="mb-3 text-xs leading-5 text-n-slate-11">
      {{ t('CRM_KANBAN.COPILOT.HELP') }}
    </p>

    <div class="flex flex-wrap gap-2">
      <Button
        :label="t('CRM_KANBAN.COPILOT.SUMMARIZE')"
        icon="i-lucide-list"
        xs
        slate
        faded
        :is-loading="loadingTask === 'summarize'"
        :disabled="isLoading"
        @click="run('summarize')"
      />
      <Button
        :label="t('CRM_KANBAN.COPILOT.DRAFT')"
        icon="i-lucide-pencil-line"
        xs
        faded
        :is-loading="loadingTask === 'draft'"
        :disabled="isLoading"
        @click="run('draft')"
      />
    </div>

    <div v-if="result" class="mt-3 grid gap-2">
      <div
        class="max-h-60 overflow-y-auto whitespace-pre-wrap rounded-lg border border-n-weak bg-n-solid-1 p-2.5 text-sm text-n-slate-12"
      >
        {{ result }}
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <Button
          :label="t('CRM_KANBAN.COPILOT.INSERT')"
          icon="i-lucide-corner-down-left"
          xs
          @click="insert"
        />
        <ChoiceSelect
          v-model="tone"
          :options="toneOptions"
          :aria-label="t('CRM_KANBAN.COPILOT.TONE')"
          compact
          class="w-32"
        />
        <Button
          :label="t('CRM_KANBAN.COPILOT.REWRITE')"
          icon="i-lucide-wand-2"
          xs
          slate
          faded
          :is-loading="loadingTask === 'rewrite'"
          :disabled="isLoading"
          @click="rewrite"
        />
      </div>

      <div class="flex items-center gap-2">
        <input
          v-model="refineText"
          :placeholder="t('CRM_KANBAN.COPILOT.REFINE_PLACEHOLDER')"
          class="reset-base !mb-0 h-8 flex-1 rounded-lg border-0 bg-n-alpha-black2 px-2.5 text-xs text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
          @keydown.enter.prevent="refine"
        />
        <Button
          :label="t('CRM_KANBAN.COPILOT.REFINE')"
          icon="i-lucide-sparkles"
          xs
          slate
          faded
          :is-loading="loadingTask === 'refine'"
          :disabled="isLoading || !refineText.trim()"
          @click="refine"
        />
      </div>
    </div>
  </section>
</template>
