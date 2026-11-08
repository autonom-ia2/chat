import ApiClient from './ApiClient';

// Server drafts of "Nova campanha" (#1898): who only builds leaves the campaign ready for who sends.
// GET    .../campaign_journey/drafts       → { payload: [draft] } pending drafts, newest first
// GET    .../campaign_journey/drafts/:id   → { payload: draft }
// POST   .../campaign_journey/drafts       { draft: { title, channel, email_campaign_id, payload } }
// PATCH  .../campaign_journey/drafts/:id   same fields; payload is replaced, never merged
// DELETE .../campaign_journey/drafts/:id   the author, or who sends
// draft: { id, title, channel, payload, email_campaign_id, author: { id, name }, created_at, updated_at }
class CampaignJourneyDraftsAPI extends ApiClient {
  constructor() {
    super('campaign_journey/drafts', { accountScoped: true });
  }
}

export default new CampaignJourneyDraftsAPI();
