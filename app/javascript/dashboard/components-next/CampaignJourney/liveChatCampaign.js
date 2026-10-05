// Chat ao vivo of the journey (#993 / #1008, PRD §6.8): the form of Chatwoot's ongoing campaign
// (same fields LiveChatCampaignForm sends to the campaigns API), as plain functions.
export const BOT_SENDER = 0;
export const DEFAULT_TIME_ON_PAGE = 10;

export const emptyLiveChat = () => ({
  inboxId: null,
  url: '',
  timeOnPage: DEFAULT_TIME_ON_PAGE,
  businessHours: false,
  title: '',
  senderId: BOT_SENDER,
  message: '',
  enabled: true,
});

/** Full address starting with http(s)://, parsed by the browser (no regular expressions). */
export const isValidPageUrl = value => {
  const text = String(value || '').trim();
  if (!text.startsWith('https://') && !text.startsWith('http://')) return false;
  try {
    return Boolean(new URL(text).hostname);
  } catch {
    return false;
  }
};

export const toCampaignPayload = form => ({
  title: form.title.trim(),
  message: form.message.trim(),
  inbox_id: form.inboxId,
  sender_id: form.senderId || null,
  enabled: form.enabled,
  trigger_only_during_business_hours: form.businessHours,
  trigger_rules: {
    url: form.url.trim(),
    time_on_page: Number(form.timeOnPage) || 0,
  },
});

export const fromCampaign = campaign => ({
  inboxId: campaign.inbox?.id ?? campaign.inbox_id ?? null,
  url: campaign.trigger_rules?.url || '',
  timeOnPage: Number(
    campaign.trigger_rules?.time_on_page ?? DEFAULT_TIME_ON_PAGE
  ),
  businessHours: campaign.trigger_only_during_business_hours === true,
  title: campaign.title || '',
  senderId: campaign.sender?.id ?? BOT_SENDER,
  message: campaign.message || '',
  enabled: campaign.enabled !== false,
});
