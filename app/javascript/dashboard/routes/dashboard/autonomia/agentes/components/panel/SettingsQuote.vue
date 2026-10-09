<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const behavior = ref('consultivo');
const schedule = ref('');
const isSaving = ref(false);

const sync = agent => {
  const choices = agent?.quote_choices || {};
  behavior.value = choices.behavior || 'consultivo';
  schedule.value = choices.horario || '';
};

watch(
  [
    () => props.agentId,
    () => props.agent?.quote_choices?.behavior,
    () => props.agent?.quote_choices?.horario,
  ],
  () => sync(props.agent),
  { immediate: true }
);

const responseData = response =>
  response?.data?.payload || response?.data || response;

const save = async () => {
  if (!props.canManage || isSaving.value) return;
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.updateQuoteChoices(
      props.agentId,
      {
        behavior: behavior.value,
        horario: schedule.value,
      }
    );
    emit('saved', { quote_choices: responseData(response)?.quote_choices });
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
    data-test="settings-quote"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{
          t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.DESCRIPTION', {
            name: agent.name,
          })
        }}
      </p>
    </div>

    <div class="flex flex-col gap-3">
      <RadioCard
        id="quote-consultivo"
        name="quote-behavior"
        :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.CONSULTIVE')"
        :description="t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.CONSULTIVE_DESC')"
        :is-active="behavior === 'consultivo'"
        :disabled="!canManage"
        @select="behavior = 'consultivo'"
      />
      <RadioCard
        id="quote-objetivo"
        name="quote-behavior"
        :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.OBJECTIVE')"
        :description="t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.OBJECTIVE_DESC')"
        :is-active="behavior === 'objetivo'"
        :disabled="!canManage"
        @select="behavior = 'objetivo'"
      />
    </div>

    <Input
      v-model="schedule"
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.SCHEDULE')"
      :placeholder="
        t('AGENTS.PANEL.REDESIGN_SETTINGS.QUOTE.SCHEDULE_PLACEHOLDER')
      "
      :disabled="!canManage || isSaving"
      data-test="quote-schedule"
    />

    <Button
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
      :is-loading="isSaving"
      :disabled="!canManage || isSaving"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="quote-save"
      @click="save"
    />
  </section>
</template>
