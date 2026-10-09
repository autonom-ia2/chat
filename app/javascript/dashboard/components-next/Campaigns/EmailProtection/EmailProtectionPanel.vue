<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import EmailStatusBadge from './EmailStatusBadge.vue';
import {
  NS,
  canResumeCampaign,
  protectionBlockReason,
  statusKey,
  reasonKey,
  formatNumber,
  reputationDenominator,
  formatDate,
} from './presentation';
const props = defineProps({
  campaign: { type: Object, default: () => ({}) },
  protection: { type: Object, default: null },
  busy: Boolean,
});
const emit = defineEmits(['reevaluate', 'resume', 'problems']);
const { t, locale } = useI18n();
const health = computed(() => props.protection || props.campaign.protection);
const blockReason = computed(() => protectionBlockReason(health.value));
const state = computed(() => {
  if (blockReason.value) return 'paused';
  return health.value?.state === 'healthy' &&
    !health.value?.current?.evaluated_at
    ? 'unknown'
    : health.value?.state || 'unknown';
});
const campaignState = computed(() => statusKey(props.campaign, true));
const distinctCampaignState = computed(
  () =>
    props.campaign.status === 'paused' &&
    campaignState.value !== statusKey({ status: state.value })
);
const titleKey = computed(() => {
  if (blockReason.value) return 'TITLE';
  if (props.campaign.status !== 'paused') return 'HEALTH';
  if (campaignState.value === 'manual') return 'STATUS.manual';
  return ['reputation', 'provider'].includes(
    reasonKey(props.campaign.pause_reason)
  )
    ? 'TITLE'
    : 'HEALTH';
});
const reason = computed(() => {
  if (blockReason.value && blockReason.value !== 'unknown')
    return blockReason.value;
  if (props.campaign.pause_reason === 'hygiene_validation_required')
    return 'review';
  return (
    blockReason.value ||
    reasonKey(health.value?.reason_code || props.campaign.pause_reason)
  );
});
const canResume = computed(() =>
  canResumeCampaign({ ...props.campaign, protection: health.value })
);
const sections = computed(() => [
  {
    key: 'CURRENT',
    metrics: health.value?.current,
    at: health.value?.current?.evaluated_at,
  },
  ...(health.value?.trigger
    ? [
        {
          key: 'TRIGGER',
          metrics: health.value.trigger.metrics,
          at: health.value.trigger.at,
        },
      ]
    : []),
]);
const counters = [
  'sent',
  'permanent_bounces',
  'temporary_bounces',
  'unknown_bounces',
  'complaints',
];
const counterLabel = key =>
  t(
    `${NS}.STATUS.${{ permanent_bounces: 'permanent', temporary_bounces: 'temporary', unknown_bounces: 'bounce_unknown', complaints: 'complained' }[key] || key}`
  );
const date = value => formatDate(value, locale.value);
const number = value => formatNumber(value, locale.value);
const rate = value =>
  typeof value === 'number' ? t(`${NS}.RATE`, { value: number(value) }) : '—';
</script>

<template>
  <section
    class="flex flex-col min-w-0 gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
    aria-live="polite"
  >
    <h3 class="m-0 text-base font-medium text-n-slate-12">
      {{ t(`${NS}.${titleKey}`) }}
    </h3>
    <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.SCOPE`) }}</p>
    <div class="flex flex-wrap items-center gap-2">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs text-n-slate-11">{{ t(`${NS}.HEALTH`) }}</span>
        <EmailStatusBadge
          :record="{
            status: state,
            reason_code:
              blockReason === 'provider'
                ? 'provider_blocked'
                : health?.reason_code,
          }"
        />
      </div>
      <div
        v-if="distinctCampaignState"
        class="flex flex-wrap items-center gap-2"
      >
        <span class="text-xs text-n-slate-11">{{
          t(`${NS}.CAMPAIGN_STATUS`)
        }}</span>
        <EmailStatusBadge :record="campaign" campaign />
      </div>
      <span
        v-for="domain in health?.domains || []"
        :key="domain"
        class="text-sm break-all text-n-slate-12"
      >
        {{ domain }}
      </span>
    </div>
    <p
      v-if="blockReason || health?.reason_code || campaign.pause_reason"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t(`${NS}.REASON.${reason}`) }}
      <span v-if="campaign.pause_reason === 'hygiene_validation_required'">{{
        t(`${NS}.RECHECK`)
      }}</span>
    </p>
    <p
      v-if="['shadow', 'warning'].includes(health?.mode)"
      class="m-0 text-sm text-n-amber-11"
    >
      {{ t(`${NS}.ANALYSIS_ONLY`) }}
    </p>
    <div class="grid gap-3 md:grid-cols-2">
      <div
        v-for="section in sections"
        :key="section.key"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak"
        :data-section="section.key"
      >
        <h4 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.${section.key}`) }}
        </h4>
        <p class="m-0 text-xs text-n-slate-11">
          {{
            t(`${NS}.${section.key === 'CURRENT' ? 'CHECKED' : 'TRIGGER_AT'}`, {
              date: date(section.at),
            })
          }}
        </p>
        <p
          v-if="section.metrics?.window_start || section.metrics?.window_end"
          class="m-0 text-xs text-n-slate-11"
        >
          {{
            t(`${NS}.WINDOW`, {
              start: date(section.metrics.window_start),
              end: date(section.metrics.window_end),
            })
          }}
        </p>
        <p v-if="section.key === 'TRIGGER'" class="m-0 text-xs text-n-slate-11">
          {{ t(`${NS}.REASON.${reasonKey(health.trigger.reason_code)}`) }}
        </p>
        <dl class="grid grid-cols-2 gap-2 m-0 text-xs text-n-slate-12">
          <template v-for="counter in counters" :key="counter">
            <dt>{{ counterLabel(counter) }}</dt>
            <dd class="m-0 text-end">
              {{ number(section.metrics?.[counter]) }}
            </dd>
          </template>
          <dt>{{ t(`${NS}.HARD_RATE`) }}</dt>
          <dd class="m-0 text-end">
            {{ rate(section.metrics?.hard_bounce_rate) }}
          </dd>
          <dt>{{ t(`${NS}.COMPLAINT_RATE`) }}</dt>
          <dd class="m-0 text-end">
            {{ rate(section.metrics?.complaint_rate) }}
          </dd>
        </dl>
        <p class="m-0 text-xs text-n-slate-11">
          {{
            t(`${NS}.OVER_SENT`, {
              count: number(
                reputationDenominator(section.metrics) ?? section.metrics?.sent
              ),
            })
          }}
        </p>
      </div>
    </div>
    <template v-if="health?.provider">
      <p class="m-0 text-xs text-n-slate-11">
        {{
          t(`${NS}.PROVIDER_AT`, { date: date(health.provider.observed_at) })
        }}
      </p>
    </template>
    <div class="flex flex-wrap gap-2">
      <Button
        v-if="campaign.id && health?.capabilities?.reevaluate"
        :label="t(`${NS}.REEVALUATE`)"
        icon="i-lucide-refresh-cw"
        :disabled="busy"
        :is-loading="busy"
        sm
        outline
        @click="emit('reevaluate')"
      />
      <Button
        v-if="canResume"
        :label="t(`${NS}.RESUME`)"
        icon="i-lucide-play"
        :disabled="busy"
        sm
        @click="emit('resume')"
      />
      <Button
        v-if="campaign.id"
        :label="t(`${NS}.PROBLEMS`)"
        icon="i-lucide-list-filter"
        sm
        slate
        outline
        @click="emit('problems')"
      />
    </div>
  </section>
</template>
