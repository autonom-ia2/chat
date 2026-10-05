// Públicos list (#993, PRD §6.6) over the existing campaign_imports API. Older imports
// have no `name` nor `channels` (added by #992): the name falls back to the campaign
// name and the channel badges simply don't show.
export const AUDIENCE_CHANNELS = ['email', 'whatsapp', 'sms'];

/**
 * Channels with the SMS badge (#1004): audiences saved before it have no `sms` key, which means
 * off with the WhatsApp count (docs/campaigns/publicos/api-1004.md §5a).
 */
export const withSmsChannel = channels => {
  if (!channels || typeof channels !== 'object' || Array.isArray(channels)) {
    return channels;
  }
  if (channels.sms || !channels.whatsapp) return channels;
  return {
    ...channels,
    sms: { enabled: false, count: Number(channels.whatsapp?.count) || 0 },
  };
};

/**
 * Channel badges of an audience: enabled channels with at least one person.
 * Accepts `{ email: { enabled, count }, whatsapp: { enabled, count } }`; anything
 * else (missing, empty, malformed) yields no badge.
 */
export const audienceChannelBadges = rawChannels => {
  if (
    !rawChannels ||
    typeof rawChannels !== 'object' ||
    Array.isArray(rawChannels)
  ) {
    return [];
  }
  const channels = withSmsChannel(rawChannels);
  return AUDIENCE_CHANNELS.map(channel => ({
    channel,
    enabled: channels[channel]?.enabled !== false,
    count: Number(channels[channel]?.count) || 0,
  })).filter(badge => badge.enabled && badge.count > 0);
};

export const buildAudienceRow = campaignImport => ({
  id: campaignImport.id,
  name: campaignImport.name || campaignImport.campaign_name || '',
  sourceFilename: campaignImport.source_filename || '',
  people: Number(campaignImport.valid_rows ?? campaignImport.total_rows) || 0,
  status: campaignImport.status,
  createdAt: campaignImport.created_at,
  badges: audienceChannelBadges(campaignImport.channels),
  isSaved: ['completed', 'completed_with_failures'].includes(
    campaignImport.status
  ),
  canDelete: campaignImport.can_delete === true,
});
