// What the protection of an e-mail campaign says: paused or not, why, the numbers of the
// current evaluation and what can be done. Shared by the old Gestão panel
// (EmailProtectionPanel) and the Resultado card (#990), so both read the same rules.
import { computed } from 'vue';
import {
  NS,
  canResumeCampaign,
  protectionBlockReason,
  reasonKey,
  formatNumber,
  displayStatusLabel,
} from './presentation';

const METRIC_ROWS = [
  ['sent', 'sent'],
  ['permanent', 'permanent_bounces', 'hard_bounce_rate'],
  ['temporary', 'temporary_bounces'],
  ['bounce_unknown', 'unknown_bounces'],
  ['complained', 'complaints', 'complaint_rate'],
];

// source: { campaign: () => object, protection: () => object|null }
export function useProtectionState(source, { t, locale }) {
  const campaign = () => source.campaign() || {};
  const health = computed(() => source.protection() || campaign().protection);
  const blockReason = computed(() => protectionBlockReason(health.value));
  const isPaused = computed(
    () => Boolean(blockReason.value) || campaign().status === 'paused'
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
    if (campaign().pause_reason === 'hygiene_validation_required')
      return 'review';
    return (
      blockReason.value ||
      reasonKey(health.value?.reason_code || campaign().pause_reason)
    );
  });
  const hasReason = computed(() =>
    Boolean(
      blockReason.value || health.value?.reason_code || campaign().pause_reason
    )
  );
  const canResume = computed(() =>
    canResumeCampaign({ ...campaign(), protection: health.value })
  );
  const canReevaluate = computed(() =>
    Boolean(campaign().id && health.value?.capabilities?.reevaluate)
  );
  const manualPause = computed(
    () =>
      campaign().status === 'paused' &&
      !blockReason.value &&
      reasonKey(campaign().pause_reason) === 'manual'
  );
  const title = computed(() => {
    if (manualPause.value) return t(`${NS}.STATUS.manual`);
    if (isPaused.value) return t(`${NS}.STATUS.paused_unknown`);
    return t(`${NS}.HEALTH`);
  });
  // The record the status badge reads: the campaign itself when it was paused by hand.
  const badgeRecord = computed(() => {
    if (campaign().status === 'paused' && !blockReason.value)
      return { record: campaign(), campaign: true };
    return {
      record: {
        status: state.value,
        reason_code:
          blockReason.value === 'provider'
            ? 'provider_blocked'
            : health.value?.reason_code,
      },
      campaign: false,
    };
  });
  const analysisOnly = computed(
    () =>
      !isPaused.value &&
      !blockReason.value &&
      ['shadow', 'warning'].includes(health.value?.mode)
  );

  const number = value => formatNumber(value, locale.value);
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
    return METRIC_ROWS.filter(([, countKey, rateKey]) =>
      [metrics[countKey], metrics[rateKey]].some(
        value => typeof value === 'number'
      )
    ).map(([key, countKey, rateKey]) => ({
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

  return {
    health,
    blockReason,
    isPaused,
    state,
    reason,
    hasReason,
    canResume,
    canReevaluate,
    manualPause,
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
  };
}
