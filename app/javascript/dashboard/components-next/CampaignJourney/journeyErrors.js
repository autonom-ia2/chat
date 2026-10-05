// Errors of the journey API turned into what the screen says (#993).

/**
 * Titles of the campaigns still sending to an audience, from a 422 `audience_in_use`
 * (deleting the audience or switching its channel off, api-1005.md §5–6). Empty otherwise.
 */
export const campaignsUsingAudience = error => {
  const data = error?.response?.data;
  if (data?.code !== 'audience_in_use') return [];
  return (data.campaigns || []).map(campaign => campaign.title).filter(Boolean);
};

// 422 codes of POST /campaign_journey/campaigns (api-1005.md §4) → i18n suffix under
// CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.ERRORS. Anything else → GENERIC.
const CREATE_ERRORS = {
  whatsapp_cloud_required: 'WHATSAPP_CLOUD_REQUIRED',
  channel_not_in_audience: 'CHANNEL_NOT_IN_AUDIENCE',
  audience_not_ready: 'AUDIENCE_NOT_READY',
  invalid_variable_bindings: 'INVALID_VARIABLE_BINDINGS',
  invalid_campaign: 'INVALID_CAMPAIGN',
  campaign_journey_disabled: 'JOURNEY_DISABLED',
};

export const createErrorKey = error => {
  const response = error?.response;
  if (response?.status === 401) return 'NOT_ALLOWED';
  return CREATE_ERRORS[response?.data?.code] || 'GENERIC';
};
