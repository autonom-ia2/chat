// Routes of the new campaign journey (#993). Registered as children of the Campaigns
// route view by a single line in campaigns.routes.js. With CAMPAIGN_JOURNEY_ENABLED off
// they send the user back to the old campaign pages, so nothing changes (PRD A5).
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CAMPAIGN_PERMISSIONS } from 'dashboard/constants/permissions.js';

const CampaignJourneyPage = () => import('./CampaignJourneyPage.vue');
const AudiencesPage = () => import('./AudiencesPage.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
};

export const isCampaignJourneyEnabled = () =>
  window.globalConfig?.CAMPAIGN_JOURNEY_ENABLED === 'true';

const isCampaignImportEnabled = () =>
  window.globalConfig?.CAMPAIGN_IMPORT_ENABLED === 'true';

const backToOldCampaigns = to => ({
  name: 'campaigns_ongoing_index',
  params: to.params,
});

const requireJourney = (to, _from, next) => {
  if (isCampaignJourneyEnabled()) {
    next();
    return;
  }
  next(backToOldCampaigns(to));
};

// CAMPAIGN_IMPORT_ENABLED turns Públicos off (PRD §8.0).
const requireAudiences = (to, _from, next) => {
  if (isCampaignJourneyEnabled() && isCampaignImportEnabled()) {
    next();
    return;
  }
  next(
    isCampaignJourneyEnabled()
      ? { name: 'campaigns_journey_index', params: to.params }
      : backToOldCampaigns(to)
  );
};

export const campaignJourneyRoutes = [
  {
    path: 'all',
    name: 'campaigns_journey_index',
    meta,
    beforeEnter: requireJourney,
    component: CampaignJourneyPage,
  },
  {
    path: 'audiences',
    name: 'campaigns_journey_audiences',
    meta,
    beforeEnter: requireAudiences,
    component: AudiencesPage,
  },
];
