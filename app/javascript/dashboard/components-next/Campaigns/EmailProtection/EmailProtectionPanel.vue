<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmailStatusBadge from './EmailStatusBadge.vue';
import {
  NS,
  canResumeCampaign,
  protectionBlockReason,
  reasonKey,
  formatNumber,
  formatDate,
  displayStatusLabel,
} from './presentation';

const props = defineProps({
  campaign: { type: Object, default: () => ({}) },
  protection: { type: Object, default: null },
  busy: Boolean,
});

const emit = defineEmits(['reevaluate', 'resume', 'problems']);
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const showDetails = ref(false);
const health = computed(() => props.protection || props.campaign.protection);
const blockReason = computed(() => protectionBlockReason(health.value));
const isPaused = computed(
  () => Boolean(blockReason.value) || props.campaign.status === 'paused'
);
const state = computed(() => {
  if (blockReason.value) return 'paused';
  return health.value?.state === 'healthy' &&
    !health.value?.current?.evaluated_at
    ? 'unknown'
    : health.value?.state || 'unknown';
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
const manualPause = computed(
  () =>
    props.campaign.status === 'paused' &&
    !blockReason.value &&
    reasonKey(props.campaign.pause_reason) === 'manual'
);
const title = computed(() => {
  if (manualPause.value) return t(`${NS}.STATUS.manual`);
  if (isPaused.value) return t(`${NS}.STATUS.paused_unknown`);
  return t(`${NS}.HEALTH`);
});

const number = value => formatNumber(value, locale.value);
const date = value => formatDate(value, locale.value);
const rate = value =>
  typeof value === 'number' ? t(`${NS}.RATE`, { value: number(value) }) : '';

const current = computed(() => health.value?.current || {});
const summaryCards = computed(() =>
  [
    {
      key: 'permanent',
      label: displayStatusLabel(t, 'permanent'),
      icon: 'i-lucide-circle-x',
      className: 'bg-n-ruby-3 text-n-ruby-11',
      count: current.value.permanent_bounces,
      rate: current.value.hard_bounce_rate,
    },
    {
      key: 'temporary',
      label: t(`${NS}.STATUS.temporary`),
      icon: 'i-lucide-refresh-cw',
      className: 'bg-n-amber-3 text-n-amber-11',
      count: current.value.temporary_bounces,
    },
    {
      key: 'complained',
      label: t(`${NS}.STATUS.complained`),
      icon: 'i-lucide-shield-alert',
      className: 'bg-n-ruby-3 text-n-ruby-11',
      count: current.value.complaints,
      rate: current.value.complaint_rate,
    },
  ].filter(card => typeof card.count === 'number')
);

const metricRows = metrics => {
  if (!metrics) return [];
  return [
    ['sent', 'sent'],
    ['permanent', 'permanent_bounces', 'hard_bounce_rate'],
    ['temporary', 'temporary_bounces'],
    ['bounce_unknown', 'unknown_bounces'],
    ['complained', 'complaints', 'complaint_rate'],
  ]
    .filter(([, countKey, rateKey]) =>
      [metrics[countKey], metrics[rateKey]].some(
        value => typeof value === 'number'
      )
    )
    .map(([key, countKey, rateKey]) => ({
      key,
      label: displayStatusLabel(t, key),
      count:
        typeof metrics[countKey] === 'number' ? number(metrics[countKey]) : '',
      rate: typeof metrics[rateKey] === 'number' ? rate(metrics[rateKey]) : '',
    }));
};

const detailSections = computed(() =>
  [
    {
      key: 'CURRENT',
      metrics: current.value,
      at: current.value.evaluated_at,
      reason: null,
    },
    health.value?.trigger
      ? {
          key: 'TRIGGER',
          metrics: health.value.trigger.metrics,
          at: health.value.trigger.at,
          reason: reasonKey(health.value.trigger.reason_code),
        }
      : null,
  ].filter(
    section => section && (section.at || metricRows(section.metrics).length)
  )
);

const hasDetails = computed(
  () =>
    detailSections.value.length > 0 ||
    health.value?.provider?.observed_at ||
    (health.value?.domains || []).length > 0
);
</script>

<template>
  <section
    class="flex flex-col min-w-0 gap-4 p-4 border rounded-lg border-n-weak bg-n-solid-1"
    aria-live="polite"
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
    >
      <div class="flex flex-col gap-2">
        <h3 class="m-0 text-base font-medium text-n-slate-12">
          {{ title }}
        </h3>
        <p
          v-if="blockReason || health?.reason_code || campaign.pause_reason"
          class="max-w-2xl m-0 text-sm text-n-slate-11"
        >
          {{ t(`${NS}.REASON.${reason}`) }}
          <span v-if="campaign.pause_reason === 'hygiene_validation_required'">
            {{ t(`${NS}.RECHECK`) }}
          </span>
        </p>
      </div>

      <EmailStatusBadge
        v-if="campaign.status === 'paused' && !blockReason"
        :record="campaign"
        campaign
      />
      <EmailStatusBadge
        v-else
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
      v-if="summaryCards.length"
      class="grid grid-cols-1 gap-2 sm:grid-cols-3"
    >
      <div
        v-for="card in summaryCards"
        :key="card.key"
        class="flex items-center gap-3 p-3 rounded-lg"
        :class="card.className"
      >
        <Icon :icon="card.icon" class="size-5 shrink-0" />
        <div class="min-w-0">
          <p class="m-0 text-xs font-medium">{{ card.label }}</p>
          <div class="flex items-baseline gap-2">
            <strong class="text-base font-semibold">{{
              number(card.count)
            }}</strong>
            <span v-if="typeof card.rate === 'number'" class="text-xs">
              {{ rate(card.rate) }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <div
      class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-n-slate-11"
    >
      <span
        v-if="typeof current.sent === 'number'"
        class="inline-flex items-center gap-1"
      >
        <span>{{ t(`${NS}.STATUS.sent`) }}</span>
        <strong class="font-medium text-n-slate-12">{{
          number(current.sent)
        }}</strong>
      </span>
      <span v-if="current.evaluated_at">
        {{ t(`${NS}.CHECKED`, { date: date(current.evaluated_at) }) }}
      </span>
    </div>

    <p
      v-if="
        !isPaused &&
        !blockReason &&
        ['shadow', 'warning'].includes(health?.mode)
      "
      class="m-0 text-sm text-n-amber-11"
    >
      {{ t(`${NS}.ANALYSIS_ONLY`) }}
    </p>

    <div v-if="hasDetails" class="flex flex-col gap-3">
      <Button
        :label="t(`${NS}.DETAILS`)"
        :icon="showDetails ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        sm
        slate
        ghost
        class="self-start"
        @click="showDetails = !showDetails"
      />

      <div
        v-show="showDetails"
        class="grid gap-3 p-3 border rounded-lg border-n-weak bg-n-alpha-1 md:grid-cols-2"
      >
        <p class="m-0 text-xs text-n-slate-11 md:col-span-2">
          {{ t(`${NS}.SCOPE`) }}
        </p>

        <div
          v-for="section in detailSections"
          :key="section.key"
          class="flex flex-col gap-2"
          :data-section="section.key"
        >
          <h4 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.${section.key}`) }}
          </h4>
          <p v-if="section.at" class="m-0 text-xs text-n-slate-11">
            {{
              t(
                `${NS}.${section.key === 'CURRENT' ? 'CHECKED' : 'TRIGGER_AT'}`,
                { date: date(section.at) }
              )
            }}
          </p>
          <p
            v-if="section.metrics?.window_start && section.metrics?.window_end"
            class="m-0 text-xs text-n-slate-11"
          >
            {{
              t(`${NS}.WINDOW`, {
                start: date(section.metrics.window_start),
                end: date(section.metrics.window_end),
              })
            }}
          </p>
          <p v-if="section.reason" class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.REASON.${section.reason}`) }}
          </p>
          <dl
            v-if="metricRows(section.metrics).length"
            class="grid grid-cols-2 gap-x-3 gap-y-1 m-0 text-xs text-n-slate-12"
          >
            <template v-for="row in metricRows(section.metrics)" :key="row.key">
              <dt>{{ row.label }}</dt>
              <dd class="flex flex-wrap justify-end gap-2 m-0 text-end">
                <span v-if="row.count">{{ row.count }}</span>
                <span v-if="row.rate" class="text-n-slate-11">{{
                  row.rate
                }}</span>
              </dd>
            </template>
          </dl>
        </div>

        <div
          v-if="health?.provider?.observed_at || (health?.domains || []).length"
          class="flex flex-col gap-1 md:col-span-2"
        >
          <p
            v-if="health?.provider?.observed_at"
            class="m-0 text-xs text-n-slate-11"
          >
            {{
              t(`${NS}.PROVIDER_AT`, {
                date: date(health.provider.observed_at),
              })
            }}
          </p>
          <span
            v-for="domain in health?.domains || []"
            :key="domain"
            class="text-xs break-all text-n-slate-11"
          >
            {{ domain }}
          </span>
        </div>
      </div>
    </div>

    <div class="flex flex-wrap gap-2">
      <Button
        v-if="canManage && campaign.id && health?.capabilities?.reevaluate"
        :label="t(`${NS}.REEVALUATE`)"
        icon="i-lucide-refresh-cw"
        :disabled="busy"
        :is-loading="busy"
        sm
        outline
        @click="emit('reevaluate')"
      />
      <Button
        v-if="canManage && canResume"
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
