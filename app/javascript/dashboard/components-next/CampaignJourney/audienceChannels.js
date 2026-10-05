// Audience ↔ campaign channel rules of Nova campanha (#993, PRD §6.2–6.3, J1, J4, J5).
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import { audienceChannelBadges, withSmsChannel } from './audienceRows';
import { isSavedAudience } from './audienceReview';

// Which audience channel each campaign channel needs.
export const AUDIENCE_CHANNEL_OF = {
  [CAMPAIGN_CHANNELS.EMAIL]: 'email',
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'whatsapp',
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: 'whatsapp',
  // #1004: SMS has its own badge on the audience.
  [CAMPAIGN_CHANNELS.SMS]: 'sms',
};

// i18n suffix under CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.UNAVAILABLE.
const MISSING_REASON = {
  email: 'NO_EMAIL',
  whatsapp: 'NO_PHONE',
  sms: 'NO_SMS',
};

/**
 * Channels of an audience as `{ email, whatsapp }` with `{ enabled, count }`. Imports from
 * before #992 have no `channels`: they were phone-only lists, so their valid rows count as
 * WhatsApp.
 */
export const audienceChannels = campaignImport => {
  const channels = campaignImport?.channels;
  const hasChannels =
    channels && typeof channels === 'object' && Object.keys(channels).length;
  if (hasChannels) {
    const sms = withSmsChannel(channels).sms;
    return {
      email: {
        enabled: channels.email?.enabled !== false,
        count: Number(channels.email?.count) || 0,
      },
      whatsapp: {
        enabled: channels.whatsapp?.enabled !== false,
        count: Number(channels.whatsapp?.count) || 0,
      },
      sms: {
        enabled: sms?.enabled === true,
        count: Number(sms?.count) || 0,
      },
    };
  }
  const people = Number(campaignImport?.valid_rows) || 0;
  return {
    email: { enabled: false, count: 0 },
    whatsapp: { enabled: people > 0, count: people },
    sms: { enabled: false, count: people },
  };
};

/** People the audience can reach on a campaign channel (0 when switched off). */
export const reachOn = (campaignChannel, channels) => {
  const audienceChannel = AUDIENCE_CHANNEL_OF[campaignChannel];
  const channel = channels?.[audienceChannel];
  return channel?.enabled ? channel.count : 0;
};

/** J4: available, or the reason key ("Este público não tem celular"). */
export const channelAvailability = (campaignChannel, channels) => {
  const audienceChannel = AUDIENCE_CHANNEL_OF[campaignChannel];
  if (!audienceChannel) return { available: true, reason: null };
  if (reachOn(campaignChannel, channels) > 0) {
    return { available: true, reason: null };
  }
  return { available: false, reason: MISSING_REASON[audienceChannel] };
};

/** Saved audiences (J1) as rows for the Público step, newest first as the API sends. */
export const savedAudienceRows = campaignImports =>
  (campaignImports || []).filter(isSavedAudience).map(campaignImport => {
    const channels = audienceChannels(campaignImport);
    return {
      id: campaignImport.id,
      name: campaignImport.name || campaignImport.campaign_name || '',
      people: Number(campaignImport.valid_rows) || 0,
      createdAt: campaignImport.created_at,
      channels,
      badges: audienceChannelBadges(channels),
      companies: campaignImport.companies?.contacts_linked ?? null,
    };
  });

/** Name search, same rule as the Campanha list. */
export const searchAudiences = (rows, query) => {
  const term = String(query || '')
    .trim()
    .toLocaleLowerCase();
  if (!term) return rows;
  return rows.filter(row => row.name.toLocaleLowerCase().includes(term));
};
