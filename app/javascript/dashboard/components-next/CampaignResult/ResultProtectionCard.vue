<script setup>
// "Envio pausado" / "Saúde do envio" of the Resultado (#990): why it paused (the reason recorded
// on the campaign, plus what the protection looks at), what to do, the numbers of THIS campaign by
// period ("Como foi esta campanha") and the actions in order of importance (Retomar, Reavaliar, Ver
// lista de problemas). The account's 7-day evaluation only shows under "Ver detalhes", with its
// dates. The rules are the old Gestão panel's (useProtectionState, O1).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import {
  NS as EMAIL_NS,
  formatDate,
  statusKey,
  displayStatusLabel,
  reasonKey,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { useProtectionState } from 'dashboard/components-next/Campaigns/EmailProtection/useProtectionState';
import ResultCampaignPeriod from './ResultCampaignPeriod.vue';

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
  blockReason,
  isPaused,
  reason,
  hasReason,
  canResume,
  canReevaluate,
  title,
  badgeRecord,
  analysisOnly,
  metricRows,
  detailSections,
  hasDetails,
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

// "Por que pausou": the reason recorded on the campaign when it paused (pause_reason, already
// presented by the API), falling back to what the protection says now. The two rate reasons get
// their own sentence; the others reuse the protection texts.
const WHY_DETAILED = ['hard_bounce_rate', 'complaint_rate', 'preflight_review'];
const reasonText = computed(() => t(`${EMAIL_NS}.REASON.${reason.value}`));
const why = computed(() => {
  const recorded = props.campaign.pause_reason;
  if (WHY_DETAILED.includes(recorded)) return t(`${NS}.WHY.${recorded}`);
  return recorded
    ? t(`${EMAIL_NS}.REASON.${reasonKey(recorded)}`)
    : reasonText.value;
});
const isManual = computed(
  () => reasonKey(props.campaign.pause_reason) === 'manual'
);
// While paused the reason is said once, in "Por que pausou". The header only adds what blocks the
// send now when that is something else (e.g. the sending service went down after a manual pause).
const showHeaderReason = computed(() => {
  if (!hasReason.value) return false;
  if (!isPaused.value) return true;
  return Boolean(blockReason.value) && reasonText.value !== why.value;
});
const periodVersion = computed(
  () => `${props.campaign.status || ''}|${props.campaign.updated_at || ''}`
);
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
          v-if="showHeaderReason"
          class="mb-0 max-w-2xl text-sm text-n-slate-11"
          data-protection-reason
        >
          {{ reasonText }}
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

    <div
      v-if="isPaused"
      class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 px-4 py-3"
      data-protection-why
    >
      <p class="m-0 text-sm text-n-slate-12">
        <span class="font-semibold">{{ t(`${NS}.WHY.LABEL`) }}</span>
        {{ why }}
      </p>
      <p
        v-if="!isManual"
        class="m-0 text-xs text-n-slate-11"
        data-protection-why-scope
      >
        {{ t(`${NS}.WHY.SCOPE`) }}
      </p>
    </div>

    <ResultCampaignPeriod
      v-if="campaign.id"
      :campaign-id="campaign.id"
      :version="periodVersion"
    />

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
          {{
            section.key === 'CURRENT'
              ? t(`${NS}.ACCOUNT_WINDOW`)
              : t(`${EMAIL_NS}.${section.key}`)
          }}
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
