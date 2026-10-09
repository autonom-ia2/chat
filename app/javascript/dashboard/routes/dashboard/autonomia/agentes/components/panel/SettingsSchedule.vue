<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import { useAlert } from 'dashboard/composables';
import AgentScheduleForm from '../../../components/panel/AgentScheduleForm.vue';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const route = useRoute();
const channels = ref([]);
const isLoadingChannels = ref(false);
const channelError = ref(false);
const isSaving = ref(false);
const { run } = useAbortableRequest();

const channelsWithoutSchedule = computed(() =>
  channels.value.filter(channel => !channel.has_schedule)
);

const loadChannels = async () => {
  isLoadingChannels.value = true;
  channelError.value = false;
  try {
    const response = await run(signal =>
      AutonomiaChannelsAPI.get(props.agentId, { signal })
    );
    if (!response) return;
    channels.value = response.data.payload;
  } catch (error) {
    if (isAbortError(error)) return;
    channelError.value = true;
  } finally {
    isLoadingChannels.value = false;
  }
};

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async responseWindow => {
  if (!props.canManage || isSaving.value) return;
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { config: { response_window: responseWindow } },
    });
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(loadChannels);
</script>

<template>
  <section
    data-test="settings-schedule"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SCHEDULE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SCHEDULE.DESCRIPTION') }}
      </p>
    </div>

    <p v-if="isLoadingChannels" class="m-0 text-xs text-n-slate-11">
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SCHEDULE.LOADING_CHANNELS') }}
    </p>
    <p v-else-if="channelError" class="m-0 text-xs text-n-ruby-11" role="alert">
      {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.SCHEDULE.CHANNELS_ERROR') }}
    </p>
    <div
      v-else-if="channelsWithoutSchedule.length"
      class="flex flex-col gap-2 px-4 py-3 text-sm rounded-xl bg-n-amber-9/10 text-n-amber-12"
      data-test="schedule-warning"
    >
      <span>{{
        t('AGENTS.PANEL.REDESIGN_SETTINGS.SCHEDULE.MISSING_WARNING')
      }}</span>
      <ul class="m-0 list-disc ltr:pl-5 rtl:pr-5">
        <li v-for="channel in channelsWithoutSchedule" :key="channel.inbox_id">
          <RouterLink
            :to="{
              name: 'settings_inbox_show',
              params: {
                accountId: route.params.accountId,
                inboxId: channel.inbox_id,
                tab: 'business-hours',
              },
            }"
            class="underline underline-offset-2"
            data-test="schedule-inbox-link"
          >
            {{ channel.inbox_name }}
          </RouterLink>
        </li>
      </ul>
    </div>

    <AgentScheduleForm
      :agent="agent"
      :is-saving="isSaving || !canManage"
      @submit="save"
    />
  </section>
</template>
