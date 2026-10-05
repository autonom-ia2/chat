// Campaign result (#1007, PRD §6.5): pure helpers shared by the result pages, the Gestão overview,
// the Campanha list ("Abrir") and the Kanban ("Ver no CRM").
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';

export const RESULT_ROUTE = 'campaigns_journey_result';
// E2: while a campaign is sending, the numbers refresh at most every 15s (≤ 30s asked).
export const RESULT_POLL_MS = 15000;
// Kanban query that opens the board filtered by one campaign mark (K6 filter of #1002).
export const CRM_CAMPAIGN_QUERY = 'campaign_source_ids';

// Channels that have a result page. Chat ao vivo has no list to measure (#1008).
export const RESULT_CHANNELS = [
  CAMPAIGN_CHANNELS.EMAIL,
  CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
  CAMPAIGN_CHANNELS.WHATSAPP_API,
  CAMPAIGN_CHANNELS.SMS,
];

export const resultRoute = (channel, campaignId) => ({
  name: RESULT_ROUTE,
  params: { channel, campaignId },
});

export const crmKanbanRoute = sourceId => ({
  name: 'crm_kanban_index',
  query: { [CRM_CAMPAIGN_QUERY]: sourceId },
});

/** Campaign marks asked by the URL (`?campaign_source_ids=a,b`), or [] when none. */
export const campaignSourceIdsFromQuery = (query = {}) => {
  const value = query[CRM_CAMPAIGN_QUERY];
  if (typeof value !== 'string') return [];
  return value
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);
};

// Numbers of each message channel, in screen order (PRD §6.5). "Lidas" only on WhatsApp Oficial;
// WhatsApp API records no delivery receipt.
const MESSAGE_KPIS = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: [
    'audience',
    'sent',
    'delivered',
    'read',
    'replied',
    'failed',
    'skipped',
  ],
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: [
    'audience',
    'sent',
    'replied',
    'failed',
    'skipped',
  ],
  [CAMPAIGN_CHANNELS.SMS]: [
    'audience',
    'sent',
    'delivered',
    'replied',
    'failed',
    'skipped',
  ],
};

/** Share of `part` in `whole`, one decimal, or null without a base. */
export const percent = (part, whole) => {
  if (typeof part !== 'number' || typeof whole !== 'number' || whole <= 0)
    return null;
  return Math.round((part / whole) * 1000) / 10;
};

export const messageKpis = (channel, totals = {}) =>
  (MESSAGE_KPIS[channel] || []).map(key => ({
    key,
    value: totals[key] ?? 0,
    rate:
      key === 'audience' ? null : percent(totals[key] ?? 0, totals.audience),
  }));

/**
 * E1: every person has exactly one situation.
 * Message channels: Enviadas + Falharam + Puladas + Na fila = Público.
 * E-mail: Entregues + Voltaram + Não enviados = Público elegível.
 */
export const resultBalance = (channel, totals = {}) => {
  const isEmail = channel === CAMPAIGN_CHANNELS.EMAIL;
  const keys = isEmail
    ? ['delivered', 'bounced', 'not_sent']
    : ['sent', 'failed', 'skipped', 'queued'];
  const total = isEmail ? totals.eligible : totals.audience;
  const parts = keys.map(key => ({ key, value: totals[key] ?? 0 }));
  const sum = parts.reduce((acc, part) => acc + part.value, 0);
  return { parts, total: total ?? 0, holds: sum === (total ?? 0) };
};

// Situation tabs of the people table, in screen order; the API says which exist per channel.
const FILTER_ORDER = [
  'sent',
  'delivered',
  'read',
  'replied',
  'failed',
  'skipped',
  'queued',
];

export const statusTabs = (filters = []) => [
  '',
  ...FILTER_ORDER.filter(filter => filters.includes(filter)),
];

// Engine status → situation of the Campanha list (CAMPAIGN_JOURNEY.STATUS).
const EMAIL_STATUS = {
  draft: 'draft',
  scheduled: 'scheduled',
  sending: 'sending',
  sent: 'completed',
  paused: 'paused',
  canceled: 'cancelled',
  failed: 'failed',
};
const WHATSAPP_API_STATUS = {
  scheduled: 'scheduled',
  running: 'sending',
  paused: 'paused',
  completed: 'completed',
  completed_with_failures: 'completed',
  cancelled: 'cancelled',
  failed: 'failed',
};
const ONE_OFF_STATUS = {
  active: 'scheduled',
  processing: 'sending',
  completed: 'completed',
};

export const journeyStatus = (channel, status) => {
  if (channel === CAMPAIGN_CHANNELS.EMAIL) return EMAIL_STATUS[status] || '';
  if (channel === CAMPAIGN_CHANNELS.WHATSAPP_API)
    return WHATSAPP_API_STATUS[status] || '';
  return ONE_OFF_STATUS[status] || '';
};
