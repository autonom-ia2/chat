// Campaigns that who builds, without campaign_send, left "ready to send" (#1898). They live on the server
// (campaign_journey/drafts); sending one goes through the usual create with `draft_id`, and the server removes it.
import DraftsAPI from 'dashboard/api/campaignJourneyDrafts';

// Server draft → what the screens read: the journey draft as it was left, and who left it.
const fromServer = draft => ({
  id: draft.id,
  title: draft.title,
  channel: draft.channel,
  draft: {
    ...(draft.payload || {}),
    emailCampaignId: draft.email_campaign_id ?? draft.payload?.emailCampaignId,
  },
  autor: draft.author?.name || '',
  updatedAt: draft.updated_at,
});

export const listarProntas = async () => {
  const { data } = await DraftsAPI.get();
  return (data.payload || []).map(fromServer);
};

export const acharPronta = async id => {
  const { data } = await DraftsAPI.show(id);
  return fromServer(data.payload);
};

// { id?, title, channel, draft } → the saved draft. PATCH replaces the payload, so the whole draft goes every time.
export const guardarPronta = async ({ id, title, channel, draft }) => {
  const body = {
    draft: {
      title,
      channel,
      email_campaign_id: draft.emailCampaignId || null,
      payload: draft,
    },
  };
  const { data } = id
    ? await DraftsAPI.update(id, body)
    : await DraftsAPI.create(body);
  return fromServer(data.payload);
};
