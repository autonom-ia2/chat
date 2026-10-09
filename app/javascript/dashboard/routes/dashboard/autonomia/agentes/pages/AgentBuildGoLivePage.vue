<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, RouterLink } from 'vue-router';

import NextButton from 'dashboard/components-next/button/Button.vue';
import ChannelRadioList from '../components/ChannelRadioList.vue';

const props = defineProps({
  agent: { type: Object, default: null },
  channels: { type: Array, default: () => [] },
  occupiedChannels: { type: Array, default: () => [] },
  testValid: { type: Boolean, default: false },
  isPublishing: { type: Boolean, default: false },
  canManage: { type: Boolean, default: true },
});

const emit = defineEmits(['publish', 'back', 'leave', 'leave-off']);
const { t } = useI18n();
const route = useRoute();
const selectedChannelIds = ref([]);
const responseWindow = ref('always');
const selectionTouched = ref(false);

const isInternal = computed(() => props.agent?.actuation === 'internal');
const hasSelection = computed(
  () => isInternal.value || selectedChannelIds.value.length > 0
);
const canPublish = computed(
  () =>
    props.testValid &&
    hasSelection.value &&
    props.canManage &&
    !props.isPublishing
);
const channelOptions = computed(() =>
  props.channels.map(channel => ({
    ...channel,
    busy: channel.busy === true,
  }))
);
const occupiedOptions = computed(() =>
  props.occupiedChannels.map(channel => ({
    ...channel,
    busy: true,
    reason:
      channel.occupied_by?.kind === 'agent' && channel.occupied_by?.agent_name
        ? t('AGENTS.CREATION.live.channelBusyByAgent', {
            name: channel.occupied_by.agent_name,
          })
        : t('AGENTS.CREATION.live.channelBusy'),
  }))
);
const selectedChannels = computed(() =>
  channelOptions.value.filter(channel =>
    selectedChannelIds.value.includes(channel.id)
  )
);
const agentName = computed(
  () => props.agent?.name || t('AGENTS.CREATION.test.agentFallback')
);
const greeting = computed(
  () => props.agent?.greeting || props.agent?.config?.greeting || ''
);

watch(
  () => props.agent?.id,
  () => {
    selectionTouched.value = false;
    selectedChannelIds.value = [];
  },
  { immediate: true }
);

watch(
  channelOptions,
  options => {
    const available = options.filter(channel => !channel.busy);
    const availableIds = new Set(available.map(channel => channel.id));
    const selected = selectedChannelIds.value.filter(id =>
      availableIds.has(id)
    );

    // One eligible channel is the safe default. As soon as there are multiple
    // choices, keep the decision explicit; a user who already touched the
    // list also keeps the ability to leave every channel unchecked.
    if (!selectionTouched.value && available.length === 1) {
      selectedChannelIds.value = [available[0].id];
      return;
    }
    if (!selectionTouched.value && available.length > 1) {
      selectedChannelIds.value = [];
      return;
    }
    selectedChannelIds.value = selected;
  },
  { immediate: true }
);

const isSelected = channel => selectedChannelIds.value.includes(channel.id);

const toggleChannel = channel => {
  if (props.isPublishing || channel.busy) return;

  selectionTouched.value = true;

  if (isSelected(channel)) {
    selectedChannelIds.value = selectedChannelIds.value.filter(
      id => id !== channel.id
    );
    return;
  }

  selectedChannelIds.value = [...selectedChannelIds.value, channel.id];
};

const publish = () => {
  if (!canPublish.value) return;
  emit('publish', {
    inboxIds: isInternal.value ? [] : [...selectedChannelIds.value],
    responseWindow: responseWindow.value,
  });
};
</script>

<template>
  <main
    data-testid="agent-creation-live"
    class="flex flex-col w-full max-w-5xl gap-6 px-4 py-6 mx-auto sm:px-6 lg:py-8"
  >
    <header class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-3">
        <div>
          <p
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t('AGENTS.CREATION.live.eyebrow') }}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.live.title', { name: agentName }) }}
          </h1>
        </div>
        <NextButton
          ghost
          slate
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.leave')"
          data-action="creation-save-exit"
          @click="emit('leave')"
        />
      </div>
      <p class="max-w-2xl text-sm leading-6 text-n-slate-11">
        {{ t('AGENTS.CREATION.live.description') }}
      </p>
    </header>

    <div
      v-if="!testValid"
      class="flex items-start gap-3 p-4 border rounded-xl border-n-amber-7 bg-n-amber-3 text-n-amber-11"
      role="alert"
    >
      <i
        class="mt-0.5 i-lucide-flask-conical size-5 shrink-0"
        aria-hidden="true"
      />
      <span class="text-sm">{{ t('AGENTS.CREATION.live.testRequired') }}</span>
    </div>

    <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(18rem,0.8fr)]">
      <section
        class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div v-if="isInternal" class="flex flex-col gap-2">
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.live.internalTitle') }}
          </h2>
          <p class="text-sm leading-6 text-n-slate-11">
            {{ t('AGENTS.CREATION.live.internalDescription') }}
          </p>
        </div>
        <template v-else>
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('AGENTS.CREATION.live.channelTitle') }}
            </h2>
            <p class="mt-1 text-xs leading-5 text-n-slate-11">
              {{ t('AGENTS.CREATION.live.channelDescription') }}
            </p>
          </div>
          <div
            class="flex flex-col gap-2"
            role="group"
            :aria-label="t('AGENTS.CREATION.live.channelLabel')"
          >
            <button
              v-for="channel in channelOptions"
              :key="channel.id"
              type="button"
              role="checkbox"
              :data-channel-id="channel.id"
              :aria-checked="isSelected(channel)"
              :aria-disabled="isPublishing || channel.busy"
              :disabled="isPublishing || channel.busy"
              class="flex items-center min-h-11 gap-3 px-3 py-2 text-left transition-colors border rounded-xl border-n-weak bg-n-solid-1 hover:border-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :class="
                isSelected(channel)
                  ? 'border-n-brand bg-n-iris-2 ring-1 ring-n-brand'
                  : ''
              "
              @click="toggleChannel(channel)"
            >
              <span
                class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-alpha-2 text-n-slate-11"
                :class="isSelected(channel) ? 'bg-n-brand text-white' : ''"
                aria-hidden="true"
              >
                <i
                  :class="
                    isSelected(channel)
                      ? 'i-lucide-check size-4'
                      : 'i-lucide-radio size-4'
                  "
                />
              </span>
              <span class="flex flex-col flex-1 min-w-0 gap-0.5">
                <strong class="text-sm font-medium truncate text-n-slate-12">
                  {{ channel.name }}
                </strong>
                <span v-if="channel.busy" class="text-xs text-n-amber-11">
                  {{ channel.reason || t('AGENTS.CREATION.live.channelBusy') }}
                </span>
                <span v-else class="text-xs text-n-slate-11">
                  {{
                    channel.provider || t('AGENTS.CREATION.live.channelReady')
                  }}
                </span>
              </span>
              <i
                v-if="isSelected(channel)"
                class="i-lucide-check size-5 shrink-0 text-n-brand"
                aria-hidden="true"
              />
            </button>
            <p
              v-if="!channelOptions.length"
              class="p-3 text-sm leading-5 rounded-xl bg-n-alpha-1 text-n-slate-11"
            >
              {{ t('AGENTS.CREATION.live.noChannels') }}
            </p>
            <p
              v-else-if="selectedChannels.length"
              class="text-xs leading-5 text-n-slate-11"
            >
              {{
                t('AGENTS.CREATION.live.selectedTitle', {
                  count: selectedChannels.length,
                })
              }}
            </p>
          </div>
          <details
            v-if="occupiedOptions.length"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-3"
          >
            <summary
              class="flex min-h-11 cursor-pointer items-center text-sm font-medium text-n-slate-12"
            >
              {{
                t('AGENTS.CREATION.live.occupiedTitle', {
                  count: occupiedOptions.length,
                })
              }}
            </summary>
            <div class="pb-3">
              <ChannelRadioList :channels="occupiedOptions" disabled />
            </div>
          </details>
          <RouterLink
            v-if="!channelOptions.length && canManage"
            :to="{
              name: 'settings_inbox_new',
              params: { accountId: route.params.accountId },
            }"
            class="inline-flex items-center justify-center min-h-11 gap-2 px-4 py-2 text-sm font-medium border rounded-xl border-n-weak text-n-slate-12 hover:border-n-brand"
          >
            <i class="i-lucide-plus size-4" aria-hidden="true" />
            {{ t('AGENTS.CREATION.live.openChannels') }}
          </RouterLink>
        </template>

        <div
          v-if="!isInternal"
          class="flex flex-col gap-3 pt-4 border-t border-n-weak"
        >
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('AGENTS.CREATION.live.windowTitle') }}
            </h2>
            <p class="mt-1 text-xs leading-5 text-n-slate-11">
              {{ t('AGENTS.CREATION.live.windowDescription') }}
            </p>
          </div>
          <div
            class="grid gap-2 sm:grid-cols-3"
            role="radiogroup"
            :aria-label="t('AGENTS.CREATION.live.windowTitle')"
          >
            <button
              v-for="option in [
                {
                  key: 'always',
                  label: t('AGENTS.CREATION.live.windows.always'),
                },
                {
                  key: 'business_hours',
                  label: t('AGENTS.CREATION.live.windows.businessHours'),
                },
                {
                  key: 'outside_business_hours',
                  label: t('AGENTS.CREATION.live.windows.outside'),
                },
              ]"
              :key="option.key"
              type="button"
              role="radio"
              :aria-checked="responseWindow === option.key"
              class="min-h-11 px-3 py-2 text-sm text-left border rounded-xl border-n-weak text-n-slate-11 hover:border-n-brand"
              :class="
                responseWindow === option.key
                  ? 'border-n-brand bg-n-iris-2 text-n-slate-12 ring-1 ring-n-brand'
                  : ''
              "
              @click="responseWindow = option.key"
            >
              {{ option.label }}
            </button>
          </div>
        </div>
      </section>

      <aside
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-iris-5 bg-n-iris-2"
      >
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.live.summaryTitle') }}
          </h2>
          <p class="mt-1 text-sm leading-6 text-n-slate-11">
            {{ t('AGENTS.CREATION.live.summary', { name: agentName }) }}
          </p>
        </div>
        <ul
          v-if="selectedChannels.length"
          class="flex flex-col gap-1 px-3 py-2 text-sm rounded-xl bg-n-solid-1 text-n-slate-12"
          :aria-label="
            t('AGENTS.CREATION.live.selectedTitle', {
              count: selectedChannels.length,
            })
          "
        >
          <li
            v-for="channel in selectedChannels"
            :key="channel.id"
            class="flex items-center gap-2"
          >
            <i class="i-lucide-check size-4 text-n-brand" aria-hidden="true" />
            <span class="truncate">{{ channel.name }}</span>
          </li>
        </ul>
        <blockquote
          v-if="greeting"
          class="p-3 text-sm leading-6 rounded-xl bg-n-solid-1 text-n-slate-11"
        >
          {{ t('AGENTS.CREATION.live.greeting', { greeting }) }}
        </blockquote>
        <p class="text-xs leading-5 text-n-slate-11">
          {{ t('AGENTS.CREATION.live.noWhatsapp') }}
        </p>
        <NextButton
          solid
          slate
          block
          class="min-h-11"
          :is-loading="isPublishing"
          :disabled="!canPublish"
          :label="t('AGENTS.CREATION.actions.publish')"
          data-action="creation-publish"
          data-testid="creation-live-publish"
          @click="publish"
        />
        <NextButton
          ghost
          slate
          block
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.keepOff')"
          data-action="creation-stay-off"
          @click="emit('leave-off')"
        />
        <NextButton
          ghost
          slate
          block
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.backToTest')"
          @click="emit('back')"
        />
      </aside>
    </div>
  </main>
</template>
