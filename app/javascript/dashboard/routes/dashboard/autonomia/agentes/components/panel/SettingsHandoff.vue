<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  quote: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const strategy = ref('low_confidence');
const targetType = ref('any');
const targetId = ref('');
const members = ref([]);
const teams = ref([]);
const isLoadingTargets = ref(false);
const isSaving = ref(false);
const loadError = ref(false);
const { run, abort } = useAbortableRequest();

const strategies = computed(() => [
  {
    value: 'low_confidence',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_LOW'),
    description: t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_LOW_DESC'),
  },
  {
    value: 'always_ask',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_ALWAYS'),
    description: t(
      'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_ALWAYS_DESC'
    ),
  },
  {
    value: 'never',
    label: t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_NEVER'),
    description: t(
      'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.STRATEGY_NEVER_DESC'
    ),
  },
]);

const targetOptions = computed(() =>
  targetType.value === 'member'
    ? members.value.map(member => ({ value: member.id, label: member.name }))
    : teams.value.map(team => ({ value: team.id, label: team.name }))
);

const sync = agent => {
  strategy.value = agent?.config?.handoff_strategy || 'low_confidence';
  targetType.value = agent?.config?.handoff_target_type || 'any';
  targetId.value = agent?.config?.handoff_target_id || '';
};

watch(
  [
    () => props.agentId,
    () => props.agent?.config?.handoff_strategy,
    () => props.agent?.config?.handoff_target_type,
    () => props.agent?.config?.handoff_target_id,
  ],
  () => sync(props.agent),
  { immediate: true }
);

const loadTargets = async () => {
  if (!props.canManage) return;
  isLoadingTargets.value = true;
  loadError.value = false;
  try {
    const response = await run(signal =>
      AutonomiaAgentsAPI.getHandoffTargets(props.agentId, { signal })
    );
    if (!response) return;
    const data = response?.data || response || {};
    members.value = data.members || [];
    teams.value = data.teams || [];
  } catch (error) {
    if (isAbortError(error)) return;
    loadError.value = true;
  } finally {
    isLoadingTargets.value = false;
  }
};

const changeTargetType = value => {
  targetType.value = value;
  targetId.value = '';
};

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async () => {
  if (!props.canManage || isSaving.value) return;
  if (targetType.value !== 'any' && !targetId.value) {
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TARGET_REQUIRED'));
    return;
  }

  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: {
        config: {
          ...(props.quote ? {} : { handoff_strategy: strategy.value }),
          handoff_target_type: targetType.value,
          handoff_target_id:
            targetType.value === 'any' ? null : Number(targetId.value),
        },
      },
    });
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

watch(
  () => props.agentId,
  () => {
    abort();
    loadTargets();
  },
  { immediate: true }
);
</script>

<template>
  <section
    data-test="settings-handoff"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{
          t(
            props.quote
              ? 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.QUOTE_TITLE'
              : 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TITLE'
          )
        }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{
          t(
            props.quote
              ? 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.QUOTE_DESCRIPTION'
              : 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.DESCRIPTION'
          )
        }}
      </p>
    </div>

    <div v-if="!quote" class="flex flex-col gap-3">
      <RadioCard
        v-for="option in strategies"
        :id="`handoff-${option.value}`"
        :key="option.value"
        name="handoff-strategy"
        :label="option.label"
        :description="option.description"
        :is-active="strategy === option.value"
        :disabled="!canManage"
        @select="strategy = option.value.replace('handoff-', '')"
      />
    </div>

    <div class="flex flex-col gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TARGET_LABEL') }}
      </span>
      <div class="flex flex-wrap gap-2" role="radiogroup">
        <button
          v-for="option in [
            { value: 'any', key: 'ANY' },
            { value: 'member', key: 'MEMBER' },
            { value: 'team', key: 'TEAM' },
          ]"
          :key="option.value"
          type="button"
          role="radio"
          :aria-checked="targetType === option.value"
          :disabled="!canManage"
          class="min-h-11 px-4 text-sm border rounded-xl outline-none focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :class="
            targetType === option.value
              ? 'border-n-blue-11 bg-n-blue-3 text-n-blue-12'
              : 'border-n-weak text-n-slate-11 hover:border-n-strong'
          "
          :data-test="`target-${option.value}`"
          @click="changeTargetType(option.value)"
        >
          {{ t(`AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TARGET.${option.key}`) }}
        </button>
      </div>

      <ChoiceSelect
        v-if="targetType !== 'any'"
        v-model="targetId"
        :options="targetOptions"
        :aria-label="
          t(
            targetType === 'member'
              ? 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.MEMBER_LABEL'
              : 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TEAM_LABEL'
          )
        "
        :placeholder="
          t(
            targetType === 'member'
              ? 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.MEMBER_PLACEHOLDER'
              : 'AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.TEAM_PLACEHOLDER'
          )
        "
        :disabled="!canManage || isLoadingTargets || loadError"
        data-test="handoff-target"
      />
      <p v-if="isLoadingTargets" class="m-0 text-xs text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.LOADING_TARGETS') }}
      </p>
      <p v-else-if="loadError" class="m-0 text-xs text-n-ruby-11" role="alert">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.HANDOFF.LOAD_ERROR') }}
      </p>
    </div>

    <Button
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
      :is-loading="isSaving"
      :disabled="!canManage || isSaving"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="handoff-save"
      @click="save"
    />
  </section>
</template>
