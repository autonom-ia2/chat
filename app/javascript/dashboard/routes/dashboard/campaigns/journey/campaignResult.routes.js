// Resultado of one campaign (#1007). Registered with the journey routes; the channel segment
// accepts only channels with a result, anything else falls back to Campanha. With
// CAMPAIGN_JOURNEY_ENABLED off the address goes to the old campaign pages (PRD A5).
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CAMPAIGN_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { RESULT_CHANNELS } from 'dashboard/components-next/CampaignResult/resultMetrics';

const CampaignResultPage = () => import('./CampaignResultPage.vue');

export const campaignResultRoutes = ({ requireJourney }) => [
  {
    path: 'results/:channel/:campaignId',
    name: 'campaigns_journey_result',
    meta: {
      featureFlag: FEATURE_FLAGS.CAMPAIGNS,
      permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
    },
    beforeEnter: [
      requireJourney,
      to =>
        RESULT_CHANNELS.includes(to.params.channel) || {
          name: 'campaigns_journey_index',
          params: { accountId: to.params.accountId },
        },
    ],
    component: CampaignResultPage,
  },
];
