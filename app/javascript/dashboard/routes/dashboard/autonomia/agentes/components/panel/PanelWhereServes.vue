<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import ChannelsAPI from 'dashboard/api/autonomia/channels';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ConfirmDialog from '../ConfirmDialog.vue';

const props = defineProps({
  agentId: { type: Number, required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const canManageInboxes = useCanManage('inbox_manage');
const { run, isPending } = useAbortableRequest();
const connected = ref([]);
const eligible = ref([]);
const occupied = ref([]);
const loaded = ref(false);
const loadError = ref(false);
const actionError = ref('');
const isWriting = ref(false);
const removing = ref(null);
const removeDialog = ref(null);
let disposed = false;

const isInternal = computed(() => props.agent.actuation === 'internal');
const canAdd = computed(
  () => props.canManage && props.agent.state?.code === 'E5'
);
const visibleOccupied = computed(() => {
  const connectedIds = new Set(connected.value.map(item => item.inbox_id));
  return occupied.value.filter(item => !connectedIds.has(item.id));
});
const removeDescription = computed(() =>
  t('AGENTS.PANEL.REDESIGN_CHANNELS.REMOVE_DESCRIPTION', {
    name: props.agent.name,
    channel: removing.value?.inbox_name || '',
  })
);
const channelIcon = channel => {
  const icons = {
    whatsapp: 'i-lucide-message-circle',
    website: 'i-lucide-globe',
    email: 'i-lucide-mail',
    instagram: 'i-lucide-instagram',
    facebook: 'i-lucide-message-circle',
  };
  return icons[channel.channel_type] || 'i-lucide-radio';
};
const occupiedLabel = item =>
  item.occupied_by?.kind === 'agent'
    ? t('AGENTS.PANEL.REDESIGN_CHANNELS.OCCUPIED_AGENT', {
        name: item.occupied_by.agent_name,
      })
    : t('AGENTS.PANEL.REDESIGN_CHANNELS.OCCUPIED_BOT');

const loadChannels = async () => {
  if (isInternal.value || !props.canManage) return;
  loadError.value = false;
  try {
    const response = await run(signal =>
      ChannelsAPI.get(props.agentId, { signal })
    );
    if (!response) return;
    connected.value = response.data.payload;
    eligible.value = response.data.eligible_inboxes;
    occupied.value = response.data.occupied_inboxes;
    loaded.value = true;
  } catch {
    loadError.value = true;
  }
};

const writeChannel = async action => {
  if (isWriting.value || !props.canManage) return;
  const targetAgentId = props.agentId;
  actionError.value = '';
  isWriting.value = true;
  try {
    await action(targetAgentId);
    if (disposed || targetAgentId !== props.agentId) return;
    removeDialog.value?.close();
    removing.value = null;
    await loadChannels();
    emit('changed');
  } catch (error) {
    if (disposed || targetAgentId !== props.agentId) return;
    actionError.value =
      error?.response?.data?.error ||
      t('AGENTS.PANEL.REDESIGN_CHANNELS.ACTION_ERROR');
  } finally {
    if (targetAgentId === props.agentId) isWriting.value = false;
  }
};
const connect = inbox => {
  if (!canAdd.value) return;
  writeChannel(agentId => ChannelsAPI.connect(agentId, inbox.id));
};
const requestRemove = inbox => {
  if (!props.canManage || isWriting.value) return;
  removing.value = inbox;
  removeDialog.value.open();
};
const confirmRemove = () => {
  if (!removing.value) return;
  const inboxId = removing.value.inbox_id;
  writeChannel(agentId => ChannelsAPI.disconnect(agentId, inboxId));
};
const openChannels = () =>
  router.push({
    name: 'settings_inbox_new',
    params: { accountId: accountId.value },
  });

watch(
  [() => props.agentId, isInternal],
  () => {
    connected.value = [];
    eligible.value = [];
    occupied.value = [];
    loaded.value = false;
    isWriting.value = false;
    actionError.value = '';
    removing.value = null;
    removeDialog.value?.close();
    loadChannels();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  disposed = true;
});
</script>

<template>
  <div data-testid="agent-panel-channels" class="grid w-full min-w-0 gap-5">
    <div
      v-if="isPending && !loaded"
      role="status"
      class="grid gap-4"
      data-state="channels-loading"
    >
      <span class="sr-only">{{
        t('AGENTS.PANEL.REDESIGN_CHANNELS.LOADING')
      }}</span>
      <div
        v-for="index in 2"
        :key="index"
        class="h-44 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
    </div>
    <section
      v-else-if="loadError"
      role="alert"
      data-state="channel-load-error"
      class="grid justify-items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-6"
    >
      <p class="text-sm text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.LOAD_ERROR') }}
      </p>
      <button
        type="button"
        data-action="channels-retry"
        class="min-h-11 rounded-xl border border-n-weak px-4 font-semibold text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="loadChannels"
      >
        {{ t('AGENTS.PERFORMANCE.RETRY') }}
      </button>
    </section>
    <template v-else-if="loaded">
      <p
        v-if="actionError"
        role="alert"
        class="rounded-xl border border-n-ruby-7 bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
      >
        {{ actionError }}
      </p>
      <section
        aria-labelledby="channels-current-title"
        class="grid min-w-0 gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <h2
            id="channels-current-title"
            class="text-base font-semibold text-n-slate-12"
          >
            {{
              t('AGENTS.PANEL.REDESIGN_CHANNELS.CURRENT_TITLE', {
                name: agent.name,
              })
            }}
          </h2>
          <p class="mt-1 text-sm leading-6 text-n-slate-11">
            {{
              t('AGENTS.PANEL.REDESIGN_CHANNELS.CURRENT_DESCRIPTION', {
                name: agent.name,
              })
            }}
          </p>
        </div>
        <p
          v-if="!connected.length"
          data-state="channel-empty"
          class="rounded-xl bg-n-alpha-1 p-4 text-sm leading-6 text-n-slate-11"
        >
          {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.EMPTY', { name: agent.name }) }}
        </p>
        <div
          v-for="channel in connected"
          :key="channel.inbox_id"
          data-connected-channel
          class="flex min-w-0 flex-wrap items-center gap-3 rounded-xl border border-n-weak p-4"
        >
          <span
            class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          >
            <i
              :class="channelIcon(channel)"
              class="size-5"
              aria-hidden="true"
            />
          </span>
          <div class="min-w-0 flex-1">
            <p class="break-words text-sm font-semibold text-n-slate-12">
              {{ channel.inbox_name }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.CONNECTED') }}
            </p>
          </div>
          <button
            v-if="canManage"
            type="button"
            data-action="channel-remove"
            :disabled="isWriting"
            :aria-label="
              t('AGENTS.PANEL.REDESIGN_CHANNELS.REMOVE_NAMED', {
                channel: channel.inbox_name,
              })
            "
            class="min-h-11 rounded-xl border border-n-weak px-4 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="requestRemove(channel)"
          >
            {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.REMOVE') }}
          </button>
        </div>
      </section>
      <section
        aria-labelledby="channels-available-title"
        class="grid min-w-0 gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <h2
            id="channels-available-title"
            class="text-base font-semibold text-n-slate-12"
          >
            {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.ADD_TITLE') }}
          </h2>
          <p class="mt-1 text-sm leading-6 text-n-slate-11">
            {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.ADD_DESCRIPTION') }}
          </p>
        </div>
        <p
          v-if="!canAdd"
          data-state="channel-inactive"
          class="rounded-xl bg-n-amber-3 p-4 text-sm leading-6 text-n-amber-12"
        >
          {{
            t('AGENTS.PANEL.REDESIGN_CHANNELS.INACTIVE', { name: agent.name })
          }}
        </p>
        <p
          v-if="!eligible.length"
          data-state="channel-no-eligible"
          class="text-sm leading-6 text-n-slate-11"
        >
          {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.NO_ELIGIBLE') }}
        </p>
        <div
          v-if="eligible.length"
          class="overflow-hidden rounded-xl border border-n-weak divide-y divide-n-weak"
        >
          <div
            v-for="channel in eligible"
            :key="channel.id"
            data-eligible-channel
            class="flex min-w-0 flex-wrap items-center gap-3 p-4"
          >
            <span
              class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-11"
              ><i
                :class="channelIcon(channel)"
                class="size-5"
                aria-hidden="true"
            /></span>
            <p
              class="min-w-0 flex-1 break-words text-sm font-semibold text-n-slate-12"
            >
              {{ channel.name }}
            </p>
            <button
              type="button"
              data-action="channel-connect"
              :disabled="!canAdd || isWriting"
              :aria-label="
                t('AGENTS.PANEL.REDESIGN_CHANNELS.ADD_NAMED', {
                  channel: channel.name,
                })
              "
              class="min-h-11 rounded-xl bg-n-blue-11 px-4 text-sm font-semibold text-white hover:bg-n-blue-12 disabled:opacity-40 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand dark:text-n-navy"
              @click="connect(channel)"
            >
              {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.ADD') }}
            </button>
          </div>
        </div>
        <div v-if="visibleOccupied.length" class="grid gap-3">
          <h3 class="text-sm font-semibold text-n-slate-11">
            {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.OCCUPIED_TITLE') }}
          </h3>
          <div
            v-for="channel in visibleOccupied"
            :key="channel.id"
            data-occupied-channel
            aria-disabled="true"
            class="flex min-w-0 items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-n-slate-11"
          >
            <i
              class="i-lucide-lock-keyhole size-5 shrink-0"
              aria-hidden="true"
            />
            <div class="min-w-0">
              <p class="break-words text-sm font-semibold">
                {{ channel.name }}
              </p>
              <p class="mt-1 break-words text-xs">
                {{ occupiedLabel(channel) }}
              </p>
            </div>
          </div>
        </div>
        <p class="text-xs leading-5 text-n-slate-11">
          {{ t('AGENTS.PANEL.REDESIGN_CHANNELS.CENTRAL_HINT') }}
        </p>
        <button
          v-if="canManageInboxes"
          type="button"
          data-action="open-channels"
          class="inline-flex min-h-11 items-center justify-center gap-2 justify-self-start rounded-xl border border-n-weak px-4 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="openChannels"
        >
          <i class="i-lucide-plus size-4" aria-hidden="true" />{{
            t('AGENTS.PANEL.REDESIGN_CHANNELS.OPEN_CHANNELS')
          }}
        </button>
      </section>
    </template>
    <ConfirmDialog
      ref="removeDialog"
      :title="t('AGENTS.PANEL.REDESIGN_CHANNELS.REMOVE_TITLE')"
      :description="removeDescription"
      :confirm-label="t('AGENTS.PANEL.REDESIGN_CHANNELS.REMOVE')"
      :cancel-label="t('AGENTS.V2.actions.cancel')"
      :is-loading="isWriting"
      destructive
      @confirm="confirmRemove"
      @close="removing = null"
    />
  </div>
</template>
