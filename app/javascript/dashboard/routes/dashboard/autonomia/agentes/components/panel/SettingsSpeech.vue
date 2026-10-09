<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  isInternal: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const greeting = ref('');
const fallback = ref('');
const tone = ref('Amigável');
const isSaving = ref(false);

const TONES = [
  { value: 'Amigável', legacy: 'friendly', key: 'FRIENDLY' },
  { value: 'Profissional', legacy: 'professional', key: 'PROFESSIONAL' },
  { value: 'Neutro', legacy: 'neutral', key: 'NEUTRAL' },
  { value: 'Descontraído', legacy: 'playful', key: 'PLAYFUL' },
];

const presetTone = computed(
  () => TONES.find(option => option.value === tone.value) || null
);

const sync = agent => {
  greeting.value = agent?.greeting || '';
  fallback.value = agent?.fallback_message || '';
  const currentTone = agent?.tone || '';
  tone.value =
    TONES.find(
      option => option.value === currentTone || option.legacy === currentTone
    )?.value ||
    currentTone ||
    TONES[0].value;
};

watch(
  [
    () => props.agentId,
    () => props.agent?.greeting,
    () => props.agent?.fallback_message,
    () => props.agent?.tone,
  ],
  () => sync(props.agent),
  { immediate: true }
);

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async () => {
  if (!props.canManage || isSaving.value) return;
  isSaving.value = true;
  try {
    const agent = {
      fallback_message: fallback.value,
      tone: tone.value,
    };
    if (!props.isInternal) agent.greeting = greeting.value;
    const response = await AutonomiaAgentsAPI.update(props.agentId, { agent });
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section
    data-test="settings-speech"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.DESCRIPTION') }}
      </p>
    </div>

    <TextArea
      v-if="!isInternal"
      v-model="greeting"
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.GREETING')"
      :placeholder="
        t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.GREETING_PLACEHOLDER')
      "
      :disabled="!canManage || isSaving"
      data-test="speech-greeting"
    />

    <TextArea
      v-model="fallback"
      :label="
        t(
          isInternal
            ? 'AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.FALLBACK_INTERNAL'
            : 'AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.FALLBACK'
        )
      "
      :placeholder="
        t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.FALLBACK_PLACEHOLDER')
      "
      :disabled="!canManage || isSaving"
      data-test="speech-fallback"
    />

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.TONE') }}
      </span>
      <div
        role="group"
        :aria-label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.TONE')"
        class="flex flex-wrap gap-2"
      >
        <button
          v-for="option in TONES"
          :key="option.value"
          type="button"
          class="min-h-11 px-4 text-sm border rounded-xl outline-none focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :class="
            tone === option.value
              ? 'border-n-blue-11 bg-n-blue-3 text-n-blue-12'
              : 'border-n-weak text-n-slate-11 hover:border-n-strong'
          "
          :aria-pressed="tone === option.value"
          :disabled="!canManage || isSaving"
          :data-test="`tone-${option.key.toLowerCase()}`"
          @click="tone = option.value"
        >
          {{ t(`AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.TONES.${option.key}`) }}
        </button>
        <button
          type="button"
          class="min-h-11 px-4 text-sm border rounded-xl outline-none focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :class="
            !presetTone
              ? 'border-n-blue-11 bg-n-blue-3 text-n-blue-12'
              : 'border-n-weak text-n-slate-11 hover:border-n-strong'
          "
          :aria-pressed="!presetTone"
          :disabled="!canManage || isSaving"
          data-test="tone-custom"
          @click="tone = presetTone ? '' : tone"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.CUSTOM') }}
        </button>
      </div>
      <Input
        v-model="tone"
        :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SPEECH.CUSTOM_LABEL')"
        maxlength="1000"
        :disabled="!canManage || isSaving"
        data-test="speech-tone"
      />
    </div>

    <Button
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
      :is-loading="isSaving"
      :disabled="!canManage || isSaving"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="speech-save"
      @click="save"
    />
  </section>
</template>
