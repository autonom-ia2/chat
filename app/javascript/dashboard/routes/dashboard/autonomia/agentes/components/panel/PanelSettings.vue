<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import SettingsIdentity from './SettingsIdentity.vue';
import SettingsInstructions from './SettingsInstructions.vue';
import SettingsActuation from './SettingsActuation.vue';
import SettingsSpeech from './SettingsSpeech.vue';
import SettingsHandoff from './SettingsHandoff.vue';
import SettingsAudience from './SettingsAudience.vue';
import SettingsSchedule from './SettingsSchedule.vue';
import SettingsVersions from './SettingsVersions.vue';
import SettingsLifecycle from './SettingsLifecycle.vue';
import SettingsQuote from './SettingsQuote.vue';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  resumeBuild: { type: Boolean, default: false },
});

const emit = defineEmits(['agentUpdated', 'continue', 'deleted']);
const { t } = useI18n();
const currentAgent = ref(props.agent);

watch(
  () => props.agent,
  agent => {
    currentAgent.value = agent;
  },
  { immediate: true }
);

const isQuote = computed(
  () => currentAgent.value?.agent_type === 'insurance_quote'
);
const isInternal = computed(() => currentAgent.value?.actuation === 'internal');
const isBoth = computed(() => currentAgent.value?.actuation === 'both');
const copilotAvailable = computed(
  () => currentAgent.value?.copilot_available?.available !== false
);

const mergeAgent = updated => {
  if (!updated) {
    emit('deleted');
    return;
  }

  if (updated.id || updated.name || updated.mode || updated.config) {
    currentAgent.value = {
      ...currentAgent.value,
      ...updated,
      config: {
        ...(currentAgent.value.config || {}),
        ...(updated.config || {}),
      },
    };
  } else if (updated.quote_choices) {
    currentAgent.value = {
      ...currentAgent.value,
      quote_choices: updated.quote_choices,
    };
  }
  emit('agentUpdated', currentAgent.value);
};
</script>

<template>
  <div
    data-test="panel-settings"
    class="flex flex-col w-full max-w-4xl gap-6 px-6 py-6 mx-auto"
  >
    <header class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.TITLE') }}
      </h1>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.DESCRIPTION') }}
      </p>
    </header>

    <SettingsIdentity
      :agent-id="Number(agentId)"
      :agent="currentAgent"
      :can-manage="canManage"
      @saved="mergeAgent"
    />

    <template v-if="isQuote">
      <SettingsQuote
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        @saved="mergeAgent"
      />
      <SettingsHandoff
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        quote
        @saved="mergeAgent"
      />
      <SettingsAudience
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        @saved="mergeAgent"
      />
      <SettingsSchedule
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        @saved="mergeAgent"
      />
    </template>

    <template v-else>
      <SettingsInstructions
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        :resume-build="resumeBuild"
        @saved="mergeAgent"
      />
      <SettingsActuation
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        :copilot-available="copilotAvailable"
        @saved="mergeAgent"
      />
      <SettingsSpeech
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        :is-internal="isInternal"
        @saved="mergeAgent"
      />

      <div
        v-if="isBoth"
        class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl bg-n-iris-2 text-n-iris-11"
        data-test="both-notice"
      >
        <i class="flex-shrink-0 mt-0.5 i-lucide-info size-4" />
        <span>
          {{
            t('AGENTS.PANEL.REDESIGN_SETTINGS.CUSTOMER_ONLY_NOTICE', {
              name: currentAgent.name,
            })
          }}
        </span>
      </div>

      <template v-if="!isInternal">
        <SettingsHandoff
          :agent-id="Number(agentId)"
          :agent="currentAgent"
          :can-manage="canManage"
          @saved="mergeAgent"
        />
        <SettingsAudience
          :agent-id="Number(agentId)"
          :agent="currentAgent"
          :can-manage="canManage"
          @saved="mergeAgent"
        />
        <SettingsSchedule
          :agent-id="Number(agentId)"
          :agent="currentAgent"
          :can-manage="canManage"
          @saved="mergeAgent"
        />
      </template>

      <SettingsVersions
        :agent-id="Number(agentId)"
        :agent="currentAgent"
        :can-manage="canManage"
        @saved="mergeAgent"
      />
    </template>

    <SettingsLifecycle
      :agent-id="Number(agentId)"
      :agent="currentAgent"
      :can-manage="canManage"
      @saved="mergeAgent"
      @continue="emit('continue')"
    />
  </div>
</template>
