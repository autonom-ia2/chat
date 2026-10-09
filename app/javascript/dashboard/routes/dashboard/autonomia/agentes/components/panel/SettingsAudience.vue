<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import AgentAudienceForm from '../../../components/panel/AgentAudienceForm.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const isSaving = ref(false);

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async ({ audience, audienceUnknownContact }) => {
  if (!props.canManage || isSaving.value) return;
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: {
        config: {
          audience,
          audience_unknown_contact: audienceUnknownContact,
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
</script>

<template>
  <section
    data-test="settings-audience"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.AUDIENCE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.AUDIENCE.DESCRIPTION') }}
      </p>
    </div>
    <AgentAudienceForm
      :agent="agent"
      :is-saving="isSaving || !canManage"
      @submit="save"
    />
  </section>
</template>
