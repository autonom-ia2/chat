<script setup>
// "Nova campanha" first step for now (#993): pick one of the connected channels and the
// existing creation flow of that channel opens. Channels that are not connected are not
// rendered at all (PRD M1–M2).
import { onMounted, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { CHANNEL_ICONS, CHANNEL_LABEL_KEYS } from './campaignChannels';

defineProps({
  channels: { type: Array, required: true },
});

const emit = defineEmits(['choose', 'close']);

const { t } = useI18n();
const titleId = useId();
const panel = useTemplateRef('panel');

onMounted(() => {
  panel.value?.querySelector('button, a')?.focus();
});
</script>

<template>
  <div
    ref="panel"
    role="dialog"
    :aria-labelledby="titleId"
    class="absolute top-12 z-50 flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-3 p-4 shadow-xl backdrop-blur-[100px] ltr:right-0 rtl:left-0"
    @keydown.esc.stop="emit('close')"
  >
    <h2 :id="titleId" class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t('CAMPAIGN_JOURNEY.CHOOSER.TITLE') }}
    </h2>
    <p class="mb-0 text-sm text-n-slate-11">
      {{
        channels.length
          ? t('CAMPAIGN_JOURNEY.CHOOSER.SUBTITLE')
          : t('CAMPAIGN_JOURNEY.CHOOSER.EMPTY')
      }}
    </p>
    <ul v-if="channels.length" class="m-0 flex list-none flex-col gap-2 p-0">
      <li v-for="channel in channels" :key="channel">
        <button
          type="button"
          class="flex min-h-11 w-full items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-start hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :data-channel="channel"
          @click="emit('choose', channel)"
        >
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            <span :class="CHANNEL_ICONS[channel]" class="size-5" />
          </span>
          <span class="min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{
                t(`CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[channel]}`)
              }}
            </span>
            <span class="block text-xs text-n-slate-11">
              {{
                t(
                  `CAMPAIGN_JOURNEY.CHOOSER.HINTS.${CHANNEL_LABEL_KEYS[channel]}`
                )
              }}
            </span>
          </span>
        </button>
      </li>
    </ul>
    <router-link
      v-else
      :to="{ name: 'settings_inbox_new' }"
      class="flex min-h-11 items-center gap-2 text-sm font-medium text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    >
      {{ t('CAMPAIGN_JOURNEY.CHOOSER.CONNECT') }}
      <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
    </router-link>
  </div>
</template>
