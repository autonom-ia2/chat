// PRD A3 (#993): with CAMPAIGN_JOURNEY_ENABLED on, the old addresses of each channel list
// open "Campanha" filtered by that channel, and the old import history opens "Público".
// The old route records are not edited (PRD §8.0): dashboard.routes.js passes the route
// trees through `withCampaignJourneyRedirects`, which adds a guard in front of the
// existing ones. Flag off → the guard lets every visit through, as before (A5).
import {
  CAMPAIGN_CHANNELS,
  LEGACY_QUERY,
} from 'dashboard/components-next/CampaignJourney/campaignChannels';
import {
  isCampaignImportEnabled,
  isCampaignJourneyEnabled,
} from './campaignJourney.routes';

export const LEGACY_LIST_CHANNELS = {
  campaigns_livechat_index: CAMPAIGN_CHANNELS.LIVE_CHAT,
  campaigns_sms_index: CAMPAIGN_CHANNELS.SMS,
  campaigns_whatsapp_index: CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
  campaigns_whatsapp_api_index: CAMPAIGN_CHANNELS.WHATSAPP_API,
  campaigns_email_index: CAMPAIGN_CHANNELS.EMAIL,
};

// A visit from the journey list itself (row "Abrir") still opens the old page, which is
// where those campaigns are handled until each one gets its Resultado (#1007).
const isLegacyVisit = to => to.query?.[LEGACY_QUERY] === '1';

const channelListGuard = channel => to => {
  if (!isCampaignJourneyEnabled() || isLegacyVisit(to)) return true;
  return {
    name: 'campaigns_journey_index',
    params: { accountId: to.params.accountId },
    query: { channel },
  };
};

const audiencesGuard = to => {
  if (!isCampaignJourneyEnabled() || !isCampaignImportEnabled()) return true;
  if (isLegacyVisit(to)) return true;
  return {
    name: 'campaigns_journey_audiences',
    params: { accountId: to.params.accountId },
  };
};

const GUARDS = {
  ...Object.fromEntries(
    Object.entries(LEGACY_LIST_CHANNELS).map(([name, channel]) => [
      name,
      channelListGuard(channel),
    ])
  ),
  contacts_campaign_imports: audiencesGuard,
};

const withGuard = route => {
  const children = route.children?.map(withGuard);
  const next = children ? { ...route, children } : { ...route };
  const guard = GUARDS[route.name];
  if (!guard) return next;
  const existing = [route.beforeEnter].flat().filter(Boolean);
  return { ...next, beforeEnter: [guard, ...existing] };
};

/** New route records with the A3 guards; the given records are left untouched. */
export const withCampaignJourneyRedirects = routes => routes.map(withGuard);
