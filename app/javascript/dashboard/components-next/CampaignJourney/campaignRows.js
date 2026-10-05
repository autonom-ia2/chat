// One list for every campaign channel (#993, PRD §6.1). Read-only aggregation of the
// stores that already exist: Chatwoot campaigns (WhatsApp Oficial, SMS, Chat ao vivo),
// WhatsApp API campaigns and e-mail campaigns. Each row opens the Resultado of its campaign
// (#1007); the old pages stay reachable at their own addresses.
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { CAMPAIGN_CHANNELS, CHANNEL_ORDER } from './campaignChannels';
import { resultRoute } from 'dashboard/components-next/CampaignResult/resultMetrics';

export const JOURNEY_STATUSES = {
  DRAFT: 'draft',
  SCHEDULED: 'scheduled',
  SENDING: 'sending',
  PAUSED: 'paused',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  FAILED: 'failed',
  ALWAYS_ON: 'always_on',
};

// Filter order in the status choice.
export const STATUS_ORDER = Object.values(JOURNEY_STATUSES);

const EMAIL_STATUS = {
  draft: JOURNEY_STATUSES.DRAFT,
  scheduled: JOURNEY_STATUSES.SCHEDULED,
  sending: JOURNEY_STATUSES.SENDING,
  sent: JOURNEY_STATUSES.COMPLETED,
  paused: JOURNEY_STATUSES.PAUSED,
  canceled: JOURNEY_STATUSES.CANCELLED,
  failed: JOURNEY_STATUSES.FAILED,
};

const WHATSAPP_API_STATUS = {
  scheduled: JOURNEY_STATUSES.SCHEDULED,
  running: JOURNEY_STATUSES.SENDING,
  paused: JOURNEY_STATUSES.PAUSED,
  completed: JOURNEY_STATUSES.COMPLETED,
  completed_with_failures: JOURNEY_STATUSES.COMPLETED,
  cancelled: JOURNEY_STATUSES.CANCELLED,
  failed: JOURNEY_STATUSES.FAILED,
};

const toTime = value => {
  if (!value) return null;
  // Chatwoot campaigns send unix seconds; the fork modules send ISO strings.
  if (typeof value === 'number') return value * 1000;
  const time = new Date(value).getTime();
  return Number.isNaN(time) ? null : time;
};

const chatwootChannel = campaign => {
  const channelType = campaign.inbox?.channel_type;
  if (campaign.campaign_type === CAMPAIGN_TYPES.ONGOING) {
    return channelType === INBOX_TYPES.WEB ? CAMPAIGN_CHANNELS.LIVE_CHAT : null;
  }
  if (channelType === INBOX_TYPES.WHATSAPP) {
    return CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL;
  }
  if (
    channelType === INBOX_TYPES.SMS ||
    // Twilio WhatsApp campaigns are not SMS (PRD M4).
    (channelType === INBOX_TYPES.TWILIO && campaign.inbox?.medium === 'sms')
  ) {
    return CAMPAIGN_CHANNELS.SMS;
  }
  return null;
};

const chatwootStatus = (campaign, channel) => {
  if (channel === CAMPAIGN_CHANNELS.LIVE_CHAT) {
    return campaign.enabled
      ? JOURNEY_STATUSES.ALWAYS_ON
      : JOURNEY_STATUSES.PAUSED;
  }
  if (campaign.campaign_status === 'completed') {
    return JOURNEY_STATUSES.COMPLETED;
  }
  return campaign.started_at
    ? JOURNEY_STATUSES.SENDING
    : JOURNEY_STATUSES.SCHEDULED;
};

// "Abrir" opens the Resultado of the campaign (#1007). Chat ao vivo has no list to measure, so
// it opens its own journey page, where it is edited and paused (#1008).
const CHATWOOT_ROUTES = {
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: campaign =>
    resultRoute(CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL, campaign.id),
  [CAMPAIGN_CHANNELS.SMS]: campaign =>
    resultRoute(CAMPAIGN_CHANNELS.SMS, campaign.id),
  [CAMPAIGN_CHANNELS.LIVE_CHAT]: campaign => ({
    name: 'campaigns_journey_live_chat_edit',
    params: { campaignId: campaign.id },
  }),
};

const fromChatwootCampaign = campaign => {
  const channel = chatwootChannel(campaign);
  if (!channel) return null;
  return {
    key: `${channel}-${campaign.id}`,
    channel,
    name: campaign.title,
    detail: campaign.inbox?.name || '',
    status: chatwootStatus(campaign, channel),
    when: toTime(campaign.scheduled_at),
    sortTime: toTime(campaign.scheduled_at) || toTime(campaign.created_at),
    sent: null,
    total: null,
    route: CHATWOOT_ROUTES[channel](campaign),
  };
};

const fromWhatsappApiCampaign = campaign => ({
  key: `${CAMPAIGN_CHANNELS.WHATSAPP_API}-${campaign.id}`,
  channel: CAMPAIGN_CHANNELS.WHATSAPP_API,
  name: campaign.title,
  detail: campaign.inbox?.name || '',
  status: WHATSAPP_API_STATUS[campaign.status] || JOURNEY_STATUSES.FAILED,
  when: toTime(campaign.scheduled_at),
  sortTime: toTime(campaign.scheduled_at) || toTime(campaign.created_at),
  sent: campaign.sent_count ?? null,
  total: campaign.recipients_count ?? null,
  route: resultRoute(CAMPAIGN_CHANNELS.WHATSAPP_API, campaign.id),
});

const fromEmailCampaign = campaign => {
  const when = toTime(campaign.sent_at) || toTime(campaign.scheduled_at);
  return {
    key: `${CAMPAIGN_CHANNELS.EMAIL}-${campaign.id}`,
    channel: CAMPAIGN_CHANNELS.EMAIL,
    name: campaign.name,
    detail: campaign.from_email || campaign.sender_domain || '',
    status: EMAIL_STATUS[campaign.status] || JOURNEY_STATUSES.FAILED,
    when,
    sortTime: when || toTime(campaign.updated_at),
    sent: campaign.sent_count ?? null,
    total: campaign.recipients_count ?? null,
    route: resultRoute(CAMPAIGN_CHANNELS.EMAIL, campaign.id),
    // The e-mail actions of the row (L8, #1007) read the campaign itself.
    source: campaign,
  };
};

/**
 * Rows of the "Campanha" list, newest first (drafts without date go last).
 */
export const buildJourneyRows = ({
  campaigns = [],
  whatsappApiCampaigns = [],
  emailCampaigns = [],
} = {}) =>
  [
    ...campaigns.map(fromChatwootCampaign),
    ...whatsappApiCampaigns.map(fromWhatsappApiCampaign),
    ...emailCampaigns.map(fromEmailCampaign),
  ]
    .filter(Boolean)
    .sort((a, b) => (b.sortTime || 0) - (a.sortTime || 0));

/**
 * Channels offered as filter chips: connected ones plus any channel that still has
 * campaigns, so campaigns of a channel disconnected later stay reachable.
 */
export const filterChannels = (rows, connectedChannels = []) =>
  CHANNEL_ORDER.filter(
    channel =>
      connectedChannels.includes(channel) ||
      rows.some(row => row.channel === channel)
  );

/**
 * Applies the list filters. Every existing campaign is listed, whatever the channel
 * state today (decision of 05/10).
 */
export const filterJourneyRows = (
  rows,
  { channel = '', status = '', search = '' } = {}
) => {
  const query = search.trim().toLocaleLowerCase();
  return rows.filter(
    row =>
      (!channel || row.channel === channel) &&
      (!status || row.status === status) &&
      (!query ||
        [row.name, row.detail].some(value =>
          (value || '').toLocaleLowerCase().includes(query)
        ))
  );
};
