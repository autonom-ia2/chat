<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  copilotAvailable: { type: Boolean, default: true },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const selected = ref('external');
const isSaving = ref(false);

const options = computed(() => [
  {
    value: 'external',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.EXTERNAL'),
    description: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.EXTERNAL_DESC'),
  },
  {
    value: 'internal',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.INTERNAL'),
    description: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.INTERNAL_DESC'),
  },
  {
    value: 'both',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.BOTH'),
    description: t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.BOTH_DESC'),
  },
]);

const channelsConnected = computed(() => (props.agent.channels_count || 0) > 0);

watch(
  [() => props.agentId, () => props.agent?.actuation],
  () => {
    selected.value = props.agent?.actuation || 'external';
  },
  { immediate: true }
);

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async () => {
  if (!props.canManage || isSaving.value) return;
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { actuation: selected.value },
    });
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
    data-test="settings-actuation"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-col gap-3">
      <RadioCard
        v-for="option in options"
        :id="`actuation-${option.value}`"
        :key="option.value"
        name="agent-actuation"
        :label="option.label"
        :description="option.description"
        :is-active="selected === option.value"
        :disabled="
          !canManage ||
          (!copilotAvailable && ['internal', 'both'].includes(option.value))
        "
        :disabled-label="
          t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.UNAVAILABLE_LABEL')
        "
        :disabled-message="
          t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.UNAVAILABLE')
        "
        @select="selected = option.value.replace('actuation-', '')"
      />
    </div>

    <p
      v-if="selected === 'internal' && channelsConnected"
      class="m-0 text-xs text-n-amber-11"
      data-test="actuation-channel-warning"
    >
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.ACTUATION.CHANNEL_WARNING') }}
    </p>

    <Button
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
      :is-loading="isSaving"
      :disabled="!canManage || isSaving"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="actuation-save"
      @click="save"
    />
  </section>
</template>
