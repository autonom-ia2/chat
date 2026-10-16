<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({ agent: { type: Object, required: true } });
const { t } = useI18n();
const store = useStore();
const busy = computed(
  () => store.getters['autonomiaAgents/getUIFlags'].updatingItem
);
const form = reactive({
  name: '',
  company_name: '',
  supplemental_instruction: '',
  greeting: '',
  fallback_message: '',
  tone: 'friendly',
});
watch(
  () => props.agent,
  agent => {
    form.name = agent.name;
    form.company_name = agent.company_name || '';
    form.supplemental_instruction = agent.supplemental_instruction || '';
    form.greeting = agent.greeting || '';
    form.fallback_message = agent.fallback_message || '';
    form.tone = agent.tone || 'friendly';
  },
  { immediate: true }
);
const save = async () => {
  if (busy.value || !form.name.trim()) return;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: props.agent.id,
      ...form,
    });
    useAlert(t('AGENTS.TUNE.SAVE_SUCCESS'));
  } catch {
    useAlert(t('AGENTS.TUNE.SAVE_ERROR'));
  }
};
const tones = computed(() => [
  { value: 'friendly', label: t('AGENTS.TUNE.TONE_OPTIONS.FRIENDLY') },
  { value: 'professional', label: t('AGENTS.TUNE.TONE_OPTIONS.PROFESSIONAL') },
  { value: 'neutral', label: t('AGENTS.TUNE.TONE_OPTIONS.NEUTRAL') },
  { value: 'playful', label: t('AGENTS.TUNE.TONE_OPTIONS.PLAYFUL') },
]);
</script>

<template>
  <form
    class="flex flex-col min-w-0 max-w-3xl gap-5 p-6"
    @submit.prevent="save"
  >
    <Input
      v-model="form.name"
      :label="t('AGENTS.CONTRACTED.NAME')"
      required
      :maxlength="255"
    />
    <Input
      v-model="form.company_name"
      :label="t('AGENTS.CONTRACTED.COMPANY')"
      :maxlength="255"
    />
    <TextArea
      :id="`store-agent-complements-${agent.id}`"
      v-model="form.supplemental_instruction"
      :label="t('AGENTS.CONTRACTED.COMPLEMENTS')"
      :max-length="50000"
      show-character-count
      custom-text-area-class="min-h-32"
    />
    <Input v-model="form.greeting" :label="t('AGENTS.TUNE.GREETING')" />
    <Input v-model="form.fallback_message" :label="t('AGENTS.TUNE.FALLBACK')" />
    <label class="flex flex-col gap-2 text-sm text-n-slate-12">
      {{ t('AGENTS.TUNE.TONE') }}
      <ChoiceSelect
        v-model="form.tone"
        :options="tones"
        :aria-label="t('AGENTS.TUNE.TONE')"
      />
    </label>
    <Button
      type="submit"
      icon="i-lucide-save"
      :label="t('AGENTS.CONTRACTED.SAVE')"
      :disabled="busy || !form.name.trim()"
    />
  </form>
</template>
