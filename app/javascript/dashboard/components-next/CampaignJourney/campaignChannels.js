// Campaign channels of the new journey (#993, PRD §8.10). One decision feeds the
// sidebar, the channel chooser and the list filters: a channel only shows up when its
// feature is on AND the account has an inbox (or sender) able to send it.
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const CAMPAIGN_CHANNELS = {
  EMAIL: 'email',
  WHATSAPP_OFFICIAL: 'whatsapp_official',
  WHATSAPP_API: 'whatsapp_api',
  SMS: 'sms',
  LIVE_CHAT: 'live_chat',
};

// Display order everywhere (chooser, filter chips).
export const CHANNEL_ORDER = [
  CAMPAIGN_CHANNELS.EMAIL,
  CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
  CAMPAIGN_CHANNELS.WHATSAPP_API,
  CAMPAIGN_CHANNELS.SMS,
  CAMPAIGN_CHANNELS.LIVE_CHAT,
];

export const CHANNEL_ICONS = {
  [CAMPAIGN_CHANNELS.EMAIL]: 'i-lucide-mail',
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'i-lucide-message-circle-heart',
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: 'i-lucide-message-circle',
  [CAMPAIGN_CHANNELS.SMS]: 'i-lucide-message-square-text',
  [CAMPAIGN_CHANNELS.LIVE_CHAT]: 'i-lucide-app-window',
};

// i18n suffix under CAMPAIGN_JOURNEY.CHANNELS.
export const CHANNEL_LABEL_KEYS = {
  [CAMPAIGN_CHANNELS.EMAIL]: 'EMAIL',
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'WHATSAPP_OFFICIAL',
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: 'WHATSAPP_API',
  [CAMPAIGN_CHANNELS.SMS]: 'SMS',
  [CAMPAIGN_CHANNELS.LIVE_CHAT]: 'LIVE_CHAT',
};

const isWhatsappCloud = inbox =>
  inbox.channel_type === INBOX_TYPES.WHATSAPP &&
  inbox.provider === 'whatsapp_cloud';

const isWhatsappApiCampaignInbox = inbox =>
  inbox.channel_type === INBOX_TYPES.API &&
  inbox.additional_attributes?.campaign_channel_type === 'whatsapp_api';

const isSmsInbox = inbox =>
  inbox.channel_type === INBOX_TYPES.SMS ||
  (inbox.channel_type === INBOX_TYPES.TWILIO && inbox.medium === 'sms');

const isEmailInbox = inbox => inbox.channel_type === INBOX_TYPES.EMAIL;
const isWebsiteInbox = inbox => inbox.channel_type === INBOX_TYPES.WEB;

/**
 * Connected campaign channels, in display order.
 * @param {Object} params
 * @param {Array} params.inboxes inbox records (snake_case, as in the inboxes store)
 * @param {Array} params.senderIdentities email sender identities
 * @param {Object} params.features { emailCampaigns, whatsappCampaigns, whatsappApiCampaigns }
 * @returns {string[]} channel keys from CAMPAIGN_CHANNELS
 */
export const connectedCampaignChannels = ({
  inboxes = [],
  senderIdentities = [],
  features = {},
} = {}) => {
  const has = predicate => inboxes.some(predicate);
  const hasVerifiedDomain = senderIdentities.some(
    identity => identity.status === 'verified'
  );

  const connected = {
    [CAMPAIGN_CHANNELS.EMAIL]:
      features.emailCampaigns === true &&
      (hasVerifiedDomain || has(isEmailInbox)),
    [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]:
      features.whatsappCampaigns === true && has(isWhatsappCloud),
    [CAMPAIGN_CHANNELS.WHATSAPP_API]:
      features.whatsappApiCampaigns === true && has(isWhatsappApiCampaignInbox),
    [CAMPAIGN_CHANNELS.SMS]: has(isSmsInbox),
    [CAMPAIGN_CHANNELS.LIVE_CHAT]: has(isWebsiteInbox),
  };

  return CHANNEL_ORDER.filter(channel => connected[channel]);
};
