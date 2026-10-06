// Short, plain status of a person in the e-mail Resultado (#990). The precise label of the old
// Gestão (EmailStatusBadge) stays in the pill title and in "Situação completa" of the details.
// Keys come from statusKey() of EmailProtection/presentation.
const PILL_OF_STATUS = {
  pending: 'pending',
  sent: 'sent',
  delivered: 'delivered',
  accepted_service: 'sent',
  acceptance_recorded: 'sent',
  opened: 'opened',
  clicked: 'clicked',
  temporary: 'temporary',
  permanent: 'not_delivered',
  bounce_unknown: 'not_delivered',
  nonexistent: 'nonexistent',
  failed: 'failed',
  complained: 'complained',
  invalid: 'invalid',
  review: 'review',
  suppressed: 'blocked',
  protected: 'blocked',
  unsubscribed: 'unsubscribed',
};

export const pillKeyOf = statusKey => PILL_OF_STATUS[statusKey] || 'unknown';

// Filter values of the reports API (presentation RECIPIENT_STATUSES / PROBLEM_STATUSES).
export const FILTER_PILL_KEYS = {
  pending: 'pending',
  attention: 'problem',
  unsubscribed: 'unsubscribed',
  temporary_bounced: 'temporary',
  hard_bounced: 'not_delivered',
  complained: 'complained',
  preflight_invalid: 'invalid',
  preflight_review: 'review',
};

const GOOD = 'bg-n-teal-3 text-n-teal-11';
const INFO = 'bg-n-blue-3 text-n-blue-11';
const WARN = 'bg-n-amber-3 text-n-amber-11';
const BAD = 'bg-n-ruby-3 text-n-ruby-11';
const NEUTRAL = 'bg-n-alpha-2 text-n-slate-11';

export const PILL_CLASSES = {
  pending: NEUTRAL,
  sent: INFO,
  delivered: GOOD,
  opened: INFO,
  clicked: INFO,
  temporary: WARN,
  not_delivered: BAD,
  nonexistent: BAD,
  failed: BAD,
  complained: BAD,
  invalid: BAD,
  review: WARN,
  blocked: NEUTRAL,
  unsubscribed: NEUTRAL,
  unknown: NEUTRAL,
};

// preflight_status of the recipient (EmailCampaignRecipient::PREFLIGHT_STATUSES).
export const ADDRESS_CHECK_KEYS = {
  valid: 'VALID',
  invalid: 'INVALID',
  review: 'REVIEW',
  unknown: 'UNKNOWN',
  unchecked: 'UNCHECKED',
};
