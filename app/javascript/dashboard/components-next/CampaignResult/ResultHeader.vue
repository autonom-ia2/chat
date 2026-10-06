<script setup>
// Top of a campaign result (#1007): path, name, situation, one line about the send, actions.
import { useI18n } from 'vue-i18n';
import { CHANNEL_ICONS } from 'dashboard/components-next/CampaignJourney/campaignChannels';

defineProps({
  name: { type: String, required: true },
  channel: { type: String, required: true },
  statusKey: { type: String, default: '' },
  subtitle: { type: String, default: '' },
});

const { t } = useI18n();

const STATUS_CLASSES = {
  draft: 'bg-n-alpha-2 text-n-slate-11',
  scheduled: 'bg-n-amber-3 text-n-amber-11',
  sending: 'bg-n-blue-3 text-n-blue-11',
  paused: 'bg-n-amber-3 text-n-amber-11',
  completed: 'bg-n-teal-3 text-n-teal-11',
  cancelled: 'bg-n-alpha-2 text-n-slate-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};
</script>

<template>
  <div>
    <nav
      class="mb-5 flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
      :aria-label="t('RESULT_JOURNEY.BREADCRUMB')"
    >
      {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
      <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
      <router-link
        :to="{ name: 'campaigns_journey_index' }"
        class="rounded hover:text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS') }}
      </router-link>
      <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
      <span
        class="min-w-0 truncate font-medium text-n-blue-11"
        aria-current="page"
      >
        {{ name }}
      </span>
    </nav>
    <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
      <div class="flex min-w-0 items-start gap-3">
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span :class="CHANNEL_ICONS[channel]" class="size-5" />
        </span>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h1
              class="mb-0 break-words text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
            >
              {{ name }}
            </h1>
            <span
              v-if="statusKey"
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="STATUS_CLASSES[statusKey]"
              data-result-status
            >
              {{ t(`CAMPAIGN_JOURNEY.STATUS.${statusKey.toUpperCase()}`) }}
            </span>
          </div>
          <p
            v-if="subtitle"
            class="mb-0 mt-2 break-words text-sm leading-6 text-n-slate-11"
          >
            {{ subtitle }}
          </p>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <slot name="actions" />
      </div>
    </header>
  </div>
</template>
