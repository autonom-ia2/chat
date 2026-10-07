// Routes of the new campaign journey (#993). Registered as children of the Campaigns
// route view by a single line in campaigns.routes.js. With CAMPAIGN_JOURNEY_ENABLED off
// they send the user back to the old campaign pages, so nothing changes (PRD A5).
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CAMPAIGN_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { campaignResultRoutes } from './campaignResult.routes';

const CampaignJourneyPage = () => import('./CampaignJourneyPage.vue');
const AudiencesPage = () => import('./AudiencesPage.vue');
const NewAudiencePage = () => import('./NewAudiencePage.vue');
const NewCampaignPage = () => import('./NewCampaignPage.vue');
const LiveChatJourneyPage = () => import('./LiveChatJourneyPage.vue');
const BrandKitsPage = () => import('./BrandKitsPage.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
};

// Creating audiences and campaigns needs campaign_manage (PRD A4); campaign_view only reads.
const manageMeta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator', 'campaign_manage'],
};

export const isCampaignJourneyEnabled = () =>
  window.globalConfig?.CAMPAIGN_JOURNEY_ENABLED === 'true';

export const isCampaignImportEnabled = () =>
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

// Identidade visual (#1076): BRAND_KITS_ENABLED and e-mail campaigns on; otherwise Campanha.
export const isBrandKitsEnabled = () =>
  window.globalConfig?.BRAND_KITS_ENABLED === 'true' &&
  window.globalConfig?.EMAIL_CAMPAIGN_ENABLED === 'true' &&
  window.globalConfig?.CRM_KANBAN_ENABLED === 'true';

const requireBrandKits = (to, _from, next) => {
  if (isCampaignJourneyEnabled() && isBrandKitsEnabled()) {
    next();
    return;
  }
  next(
    isCampaignJourneyEnabled()
      ? { name: 'campaigns_journey_index', params: to.params }
      : backToOldCampaigns(to)
  );
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
  {
    path: 'audiences/new',
    name: 'campaigns_journey_audience_new',
    meta: manageMeta,
    beforeEnter: requireAudiences,
    component: NewAudiencePage,
  },
  // The 3-step journey starts from a saved audience (PRD D2), so it needs Públicos on.
  {
    path: 'new',
    name: 'campaigns_journey_new',
    meta: manageMeta,
    beforeEnter: requireAudiences,
    component: NewCampaignPage,
  },
  // Chat ao vivo has no audience (PRD D16): its own flow, also to edit and pause (#1008).
  {
    path: 'live-chat/new',
    name: 'campaigns_journey_live_chat_new',
    meta: manageMeta,
    beforeEnter: requireJourney,
    component: LiveChatJourneyPage,
  },
  {
    path: 'live-chat/:campaignId',
    name: 'campaigns_journey_live_chat_edit',
    meta: manageMeta,
    beforeEnter: requireJourney,
    component: LiveChatJourneyPage,
  },
  // Identidade visual (#1076): a tab of Campanha; reading needs campaign_view, changing campaign_manage.
  {
    path: 'identity',
    name: 'campaigns_journey_brand_kits',
    meta,
    beforeEnter: requireBrandKits,
    component: BrandKitsPage,
  },
  {
    path: 'identity/new',
    name: 'campaigns_journey_brand_kit_new',
    meta: manageMeta,
    beforeEnter: requireBrandKits,
    component: BrandKitsPage,
  },
  {
    path: 'identity/:kitId',
    name: 'campaigns_journey_brand_kit_edit',
    meta: manageMeta,
    beforeEnter: requireBrandKits,
    component: BrandKitsPage,
  },
  ...campaignResultRoutes({ requireJourney }),
];
