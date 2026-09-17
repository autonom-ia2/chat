export const NS = 'EMAIL_CAMPAIGN_PROTECTION';
export const CAMPAIGN_STATUSES = [
  '',
  'attention',
  'draft',
  'scheduled',
  'sending',
  'sent',
  'paused',
  'canceled',
  'failed',
];
export const RECIPIENT_STATUSES = [
  '',
  'attention',
  'pending',
  'sent',
  'delivered',
  'opened',
  'clicked',
  'failed',
  'suppressed',
  'bounced',
  'hard_bounced',
  'temporary_bounced',
  'unknown_bounced',
  'complained',
  'unsubscribed',
  'preflight_invalid',
  'preflight_review',
  'preflight_unknown',
];
const BOUNCES = {
  hard_bounced: 'permanent',
  temporary_bounced: 'temporary',
  unknown_bounced: 'unknown',
};
const MANUAL_REASONS = ['manual', 'manual_pause', 'user'];
const STATUS_KEYS = new Set([
  'pending',
  'sent',
  'delivered',
  'opened',
  'clicked',
  'failed',
  'suppressed',
  'complained',
  'unsubscribed',
  'draft',
  'scheduled',
  'sending',
  'canceled',
  'healthy',
  'attention',
  'high_risk',
  'analysing',
  'ready',
  'protected',
  'invalid',
  'review',
  'unchecked',
  'duplicate',
  'total',
  'completed',
]);

// A legacy delivered event can be only the sending service's acceptance.
// Never infer a source from the inbox configuration or from other recipients.
export function deliveryKey(source = {}) {
  if (source.delivery_mode === 'direct_inbox') return 'accepted_service';
  const evidence = source.delivery_evidence;
  if (evidence) {
    const { provider_confirmed: confirmed, direct_acceptance_only: direct } =
      evidence;
    const complete =
      [confirmed, direct, source.delivered].every(
        value => Number.isInteger(value) && value >= 0
      ) && confirmed + direct === source.delivered;
    if (complete && confirmed === 0 && direct > 0) return 'accepted_service';
    if (
      complete &&
      direct === 0 &&
      evidence.legacy_delivered_includes_acceptance === false
    )
      return 'delivered';
    return 'acceptance_recorded';
  }
  return source.delivery_mode === 'ses' ? 'delivered' : 'acceptance_recorded';
}

export function statusKey(row = {}, campaign = false) {
  if (row.status === 'delivered' && !campaign)
    return deliveryKey({ delivery_mode: row.delivery_mode });
  if (!campaign && row.status === 'suppressed' && !row.suppression_reason) {
    if (row.preflight_status === 'invalid') return 'invalid';
    if (row.preflight_status === 'review') return 'review';
  }
  if (row.status === 'paused')
    return campaign && MANUAL_REASONS.includes(row.pause_reason)
      ? 'manual'
      : 'paused';
  if (row.status === 'bounced' || BOUNCES[row.status]) {
    if (
      ['mailbox_not_found', 'mailbox_does_not_exist', 'no_such_user'].includes(
        row.reason_code
      )
    )
      return 'nonexistent';
    const outcome = row.delivery_outcome || BOUNCES[row.status];
    return ['permanent', 'temporary'].includes(outcome)
      ? outcome
      : 'bounce_unknown';
  }
  const preflight = {
    preflight_invalid: 'invalid',
    preflight_review: 'review',
    preflight_unknown: 'unknown',
    valid: 'completed',
  };
  return (
    preflight[row.status] ||
    (STATUS_KEYS.has(row.status) ? row.status : 'unknown')
  );
}

export function reasonKey(code) {
  const reasons = {
    manual: 'manual',
    manual_pause: 'manual',
    user: 'manual',
    reputation: 'reputation',
    reputation_guardrail: 'reputation',
    hard_bounce_rate: 'reputation',
    complaint_rate: 'reputation',
    provider_blocked: 'provider',
    ses_account_paused: 'provider',
    ses_sending_disabled: 'provider',
    unsubscribed: 'unsubscribed',
    opt_out: 'unsubscribed',
    complained: 'complained',
    complaint: 'complained',
    permanent_bounce: 'permanent',
    hard_bounce: 'permanent',
    temporary_bounce: 'temporary',
    mailbox_not_found: 'nonexistent',
    mailbox_does_not_exist: 'nonexistent',
    no_such_user: 'nonexistent',
    invalid_format: 'invalid',
    invalid_domain: 'invalid',
    domain_no_mail_route: 'invalid',
    preflight_invalid: 'invalid',
    preflight_review: 'review',
    unsubscribe: 'unsubscribed',
    temporary_failure: 'temporary',
    mailbox_full: 'temporary',
    permanent_failure: 'permanent',
    provider_suppression: 'provider',
    provider_manual_block: 'provider',
    provider_telemetry_unknown: 'provider',
    reputation_paused: 'reputation',
    reputation_threshold: 'reputation',
    legacy_pause: 'reputation',
    hygiene_validation_required: 'review',
    invalid_email: 'invalid',
    blank_email: 'invalid',
    unsupported_local_part: 'invalid',
    nxdomain: 'invalid',
    null_mx: 'invalid',
    no_mail_route: 'invalid',
    invalid_recipient: 'review',
    provider_typo: 'review',
    idn_requires_ascii_domain: 'review',
  };
  return Object.hasOwn(reasons, code) ? reasons[code] : 'unknown';
}

export function protectionBlockReason(protection) {
  if (['blocked', 'paused', 'disabled'].includes(protection?.provider?.state))
    return 'provider';
  if (protection?.state !== 'paused') return null;
  const reason = reasonKey(protection.reason_code);
  return reason === 'manual' ? 'unknown' : reason;
}

export function canResumeCampaign(campaign = {}) {
  if (campaign.status !== 'paused') return false;
  const protection = campaign.protection;
  if (protection?.capabilities?.resume !== true) return false;
  if (
    !['healthy', 'unknown', 'not_applicable'].includes(
      protection.provider?.state
    )
  )
    return false;
  // A release opportunity does not clear the sticky state or its trigger.
  if (protection.state === 'paused')
    return protection.release_eligible === true;
  return ['healthy', 'unknown', 'attention', 'high_risk'].includes(
    protection.state
  );
}

export const safeError = (t, error) => {
  const key = reasonKey(
    error?.response?.data?.protection?.code ||
      error?.response?.data?.error_code ||
      error?.response?.data?.code ||
      error?.response?.data?.error
  );
  return t(key === 'unknown' ? `${NS}.ERROR` : `${NS}.REASON.${key}`);
};
// Report totals include direct sends; reputation denominators do not.
export const reputationDenominator = (source = {}, rate = 'hard_bounce_rate') =>
  source?.rate_metadata?.[rate]?.denominator ??
  source?.reputation_coverage?.sent;

export const hasActiveEmailWork = (campaign = {}) =>
  ['scheduled', 'sending'].includes(campaign.status) ||
  campaign.ai_status === 'processing' ||
  ['queued', 'processing'].includes(campaign.recipient_import?.status) ||
  ['queued', 'processing', 'analysing'].includes(campaign.preflight?.status) ||
  campaign.preflight?.counts?.unchecked > 0 ||
  ['paused', 'attention', 'high_risk'].includes(campaign.protection?.state);

export const localeTag = locale => locale.replace('_', '-');
export const formatNumber = (value, locale) =>
  typeof value === 'number' && Number.isFinite(value)
    ? new Intl.NumberFormat(localeTag(locale), {
        maximumFractionDigits: 2,
      }).format(value)
    : '—';
export const formatDate = (value, locale) => {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? '—'
    : new Intl.DateTimeFormat(localeTag(locale), {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(date);
};
export const downloadCsv = (blob, name) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  URL.revokeObjectURL(url);
};
