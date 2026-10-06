<script setup>
// "Envio pausado" / "Saúde do envio" of the Resultado (#990): one line on why, one on what to
// do, the numbers in a strip and the actions in order of importance (Retomar, Reavaliar, Ver
// lista de problemas). The rules are the old Gestão panel's (useProtectionState, O1).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import {
  NS as EMAIL_NS,
  formatDate,
  statusKey,
  displayStatusLabel,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { useProtectionState } from 'dashboard/components-next/Campaigns/EmailProtection/useProtectionState';

const props = defineProps({
  campaign: { type: Object, default: () => ({}) },
  busy: Boolean,
});
const emit = defineEmits(['reevaluate', 'resume', 'problems']);

const NS = 'RESULT_JOURNEY.EMAIL_HEALTH';
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const showDetails = ref(false);
const {
  health,
  isPaused,
  reason,
  hasReason,
  canResume,
  canReevaluate,
  title,
  badgeRecord,
  analysisOnly,
  current,
  summaryCards,
  metricRows,
  detailSections,
  hasDetails,
  number,
  rate,
} = useProtectionState(
  { campaign: () => props.campaign, protection: () => null },
  { t, locale }
);

const date = value => formatDate(value, locale.value);

const PILL_CLASSES = {
  paused: 'bg-n-amber-3 text-n-amber-11',
  attention: 'bg-n-amber-3 text-n-amber-11',
  review: 'bg-n-amber-3 text-n-amber-11',
  high_risk: 'bg-n-ruby-3 text-n-ruby-11',
  healthy: 'bg-n-teal-3 text-n-teal-11',
};
const pillKey = computed(() =>
  statusKey(badgeRecord.value.record, badgeRecord.value.campaign)
);
const pill = computed(() => ({
  label: displayStatusLabel(t, pillKey.value),
  className: PILL_CLASSES[pillKey.value] || 'bg-n-alpha-2 text-n-slate-11',
}));

const showResume = computed(() => canManage.value && canResume.value);
const showReevaluate = computed(() => canManage.value && canReevaluate.value);

// One sentence telling what to do now, matching the main button shown.
const nextStep = computed(() => {
  if (!isPaused.value) return '';
  if (props.campaign.pause_reason === 'hygiene_validation_required')
    return t(`${NS}.NEXT.RECHECK`);
  if (showResume.value) return t(`${NS}.NEXT.RESUME`);
  if (showReevaluate.value) return t(`${NS}.NEXT.REEVALUATE`);
  return t(`${NS}.NEXT.PROBLEMS`);
});

const strip = computed(() => [
  ...(typeof current.value.sent === 'number'
    ? [
        {
          key: 'sent',
          label: t(`${EMAIL_NS}.STATUS.sent`),
          count: current.value.sent,
        },
      ]
    : []),
  ...summaryCards.value,
]);
// No empty cell at any width: 4 numbers make 2×2 on a phone, 3 make one column.
const STRIP_COLUMNS = {
  1: 'grid-cols-1',
  2: 'grid-cols-2',
  3: 'grid-cols-1 sm:grid-cols-3',
  4: 'grid-cols-2 sm:grid-cols-4',
};
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    aria-live="polite"
    data-protection-card
  >
    <header class="flex flex-wrap items-start gap-3">
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl"
        :class="
          isPaused
            ? 'bg-n-amber-3 text-n-amber-11'
            : 'bg-n-teal-3 text-n-teal-11'
        "
        aria-hidden="true"
      >
        <span
          :class="isPaused ? 'i-lucide-pause' : 'i-lucide-shield-check'"
          class="size-5"
        />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="mb-0 text-base font-semibold text-n-slate-12">
            {{ title }}
          </h2>
          <span
            class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
            :class="pill.className"
            data-protection-pill
          >
            {{ pill.label }}
          </span>
        </div>
        <p
          v-if="hasReason"
          class="mb-0 max-w-2xl text-sm text-n-slate-11"
          data-protection-reason
        >
          {{ t(`${EMAIL_NS}.REASON.${reason}`) }}
        </p>
        <p
          v-if="nextStep"
          class="mb-0 max-w-2xl text-sm font-medium text-n-slate-12"
          data-protection-next
        >
          {{ nextStep }}
        </p>
        <p v-if="analysisOnly" class="mb-0 text-sm text-n-amber-11">
          {{ t(`${EMAIL_NS}.ANALYSIS_ONLY`) }}
        </p>
      </div>
    </header>

    <dl
      v-if="strip.length"
      class="m-0 grid gap-px overflow-hidden rounded-xl border border-n-weak bg-n-weak"
      :class="STRIP_COLUMNS[strip.length]"
      data-protection-strip
    >
      <div
        v-for="item in strip"
        :key="item.key"
        class="min-w-0 bg-n-solid-1 px-4 py-3"
        :data-strip="item.key"
      >
        <dt class="text-xs text-n-slate-11">{{ item.label }}</dt>
        <dd class="m-0 mt-1 text-xl font-semibold tabular-nums text-n-slate-12">
          {{ number(item.count) }}
        </dd>
        <dd
          v-if="typeof item.rate === 'number'"
          class="m-0 text-xs text-n-slate-11"
        >
          {{ rate(item.rate) }}
        </dd>
      </div>
    </dl>
    <p
      v-if="current.evaluated_at"
      class="-mt-3 mb-0 text-xs text-n-slate-11"
      data-protection-checked
    >
      {{ t(`${EMAIL_NS}.CHECKED`, { date: date(current.evaluated_at) }) }}
    </p>

    <div
      class="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center"
      data-protection-actions
    >
      <Button
        v-if="showResume"
        :label="t(`${EMAIL_NS}.RESUME`)"
        icon="i-lucide-play"
        class="!min-h-11 !rounded-xl"
        :disabled="busy"
        data-protection-action="resume"
        @click="emit('resume')"
      />
      <Button
        v-if="showReevaluate"
        :label="t(`${NS}.REEVALUATE`)"
        icon="i-lucide-refresh-cw"
        slate
        outline
        class="!min-h-11 !rounded-xl"
        :disabled="busy"
        :is-loading="busy"
        data-protection-action="reevaluate"
        @click="emit('reevaluate')"
      />
      <Button
        v-if="campaign.id"
        :label="t(`${EMAIL_NS}.PROBLEMS`)"
        icon="i-lucide-list-filter"
        slate
        ghost
        class="!min-h-11 !rounded-xl"
        data-protection-action="problems"
        @click="emit('problems')"
      />
      <button
        v-if="hasDetails"
        type="button"
        class="inline-flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand sm:ms-auto"
        :aria-expanded="showDetails"
        aria-controls="result-protection-details"
        data-protection-details-toggle
        @click="showDetails = !showDetails"
      >
        {{ t(`${NS}.${showDetails ? 'HIDE_DETAILS' : 'SHOW_DETAILS'}`) }}
        <span
          :class="showDetails ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4"
          aria-hidden="true"
        />
      </button>
    </div>

    <div
      v-if="hasDetails"
      v-show="showDetails"
      id="result-protection-details"
      class="grid gap-4 rounded-xl border border-n-weak p-4 md:grid-cols-2"
      data-protection-details
    >
      <p class="m-0 text-xs text-n-slate-11 md:col-span-2">
        {{ t(`${EMAIL_NS}.SCOPE`) }}
      </p>
      <div
        v-for="section in detailSections"
        :key="section.key"
        class="flex flex-col gap-2"
        :data-section="section.key"
      >
        <h3 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t(`${EMAIL_NS}.${section.key}`) }}
        </h3>
        <p v-if="section.at" class="m-0 text-xs text-n-slate-11">
          {{
            t(
              `${EMAIL_NS}.${section.key === 'CURRENT' ? 'CHECKED' : 'TRIGGER_AT'}`,
              { date: date(section.at) }
            )
          }}
        </p>
        <p
          v-if="section.metrics?.window_start && section.metrics?.window_end"
          class="m-0 text-xs text-n-slate-11"
        >
          {{
            t(`${EMAIL_NS}.WINDOW`, {
              start: date(section.metrics.window_start),
              end: date(section.metrics.window_end),
            })
          }}
        </p>
        <p v-if="section.reason" class="m-0 text-xs text-n-slate-11">
          {{ t(`${EMAIL_NS}.REASON.${section.reason}`) }}
        </p>
        <dl
          v-if="metricRows(section.metrics).length"
          class="m-0 grid grid-cols-[1fr_auto] gap-x-3 gap-y-1 text-xs text-n-slate-12"
        >
          <template v-for="row in metricRows(section.metrics)" :key="row.key">
            <dt class="text-n-slate-11">{{ row.label }}</dt>
            <dd class="m-0 flex flex-wrap justify-end gap-2 text-end">
              <span v-if="row.count" class="font-medium tabular-nums">
                {{ row.count }}
              </span>
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
            t(`${EMAIL_NS}.PROVIDER_AT`, {
              date: date(health.provider.observed_at),
            })
          }}
        </p>
        <span
          v-for="domain in health?.domains || []"
          :key="domain"
          class="break-all text-xs text-n-slate-11"
        >
          {{ domain }}
        </span>
      </div>
    </div>
  </section>
</template>
