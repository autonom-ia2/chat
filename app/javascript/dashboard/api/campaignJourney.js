/* global axios */

import ApiClient from './ApiClient';

// Campaign journey reads (#1002):
// GET .../campaign_journey/contact_origins/:contactId
//   → { payload: { marks: [{ source, source_id, headline, touched_at, ... }], audiences: [{ id, name }] } }
// GET .../campaign_journey/campaign_names?campaign_ids=1,2&whatsapp_api_campaign_ids=3
//   → { payload: { campaigns: { id: title }, whatsapp_api_campaigns: { id: title } } }
class CampaignJourneyAPI extends ApiClient {
  constructor() {
    super('campaign_journey', { accountScoped: true });
  }

  getContactOrigins(contactId) {
    return axios.get(`${this.url}/contact_origins/${contactId}`);
  }

  getCampaignNames({ campaignIds = [], whatsappApiCampaignIds = [] }) {
    return axios.get(`${this.url}/campaign_names`, {
      params: {
        campaign_ids: campaignIds.join(','),
        whatsapp_api_campaign_ids: whatsappApiCampaignIds.join(','),
      },
    });
  }
}

export default new CampaignJourneyAPI();

// Audiences and journey campaign creation (#993) live in their own file (one class per file).
export {
  audiencesAPI,
  journeyCampaignsAPI,
} from './campaignJourneyAudiences';
