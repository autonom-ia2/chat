import { ref } from 'vue';
import CampaignJourneyAPI from 'dashboard/api/campaignJourney';

// Campaign names of campaign messages (#1002, P2). One request per tick for every bubble that
// asks, cached for the session: a conversation full of campaign messages costs one call.
const names = ref({});
const pending = { campaign: new Set(), whatsappApi: new Set() };
let flushTimer = null;

const keyFor = (kind, id) => `${kind}:${id}`;

const flush = async () => {
  flushTimer = null;
  const campaignIds = [...pending.campaign];
  const whatsappApiCampaignIds = [...pending.whatsappApi];
  pending.campaign.clear();
  pending.whatsappApi.clear();

  try {
    const { data } = await CampaignJourneyAPI.getCampaignNames({
      campaignIds,
      whatsappApiCampaignIds,
    });
    const { campaigns = {}, whatsapp_api_campaigns: apiCampaigns = {} } =
      data.payload || {};
    const resolved = { ...names.value };
    campaignIds.forEach(id => {
      resolved[keyFor('campaign', id)] = campaigns[id] || '';
    });
    whatsappApiCampaignIds.forEach(id => {
      resolved[keyFor('whatsappApi', id)] = apiCampaigns[id] || '';
    });
    names.value = resolved;
  } catch {
    // Without the name the bubble shows no label.
  }
};

// { kind: 'campaign' | 'whatsappApi', id } of a message, from its additional attributes.
export const campaignRefFor = attributes => {
  if (attributes?.whatsappApiCampaignId) {
    return {
      kind: 'whatsappApi',
      id: String(attributes.whatsappApiCampaignId),
    };
  }
  if (attributes?.campaignId) {
    return { kind: 'campaign', id: String(attributes.campaignId) };
  }
  return null;
};

export function useCampaignNames() {
  const request = ({ kind, id }) => {
    const key = keyFor(kind, id);
    if (key in names.value || pending[kind].has(id)) return;

    pending[kind].add(id);
    flushTimer ??= setTimeout(flush, 0);
  };

  const nameFor = ({ kind, id }) => names.value[keyFor(kind, id)] || '';

  return { request, nameFor };
}

export const resetCampaignNamesCache = () => {
  names.value = {};
  pending.campaign.clear();
  pending.whatsappApi.clear();
  clearTimeout(flushTimer);
  flushTimer = null;
};
