// Campanhas menu of the new journey (#993, PRD D17). Sidebar.vue only hands its current
// children here: with the flag off they come back untouched; with it on the group shows
// Público, Campanha, Modelos, Links e QR codes and Gestão de campanhas, in this order,
// reusing the existing entries for the last three.
const KEPT_ENTRIES = [
  'Campaign WhatsApp Templates',
  'Campaign Links and QR codes',
  'Campaign Management',
];

export const withCampaignJourney = (
  { enabled, audiencesEnabled, t, accountScopedRoute },
  legacyChildren
) => {
  if (!enabled) return legacyChildren;

  const audiences = audiencesEnabled
    ? [
        {
          name: 'Campaign Audiences',
          label: t('CAMPAIGN_JOURNEY.SIDEBAR.AUDIENCES'),
          to: accountScopedRoute('campaigns_journey_audiences'),
          activeOn: ['campaigns_journey_audiences'],
        },
      ]
    : [];
  const kept = KEPT_ENTRIES.map(name =>
    legacyChildren.find(child => child.name === name)
  ).filter(Boolean);

  return [
    ...audiences,
    {
      name: 'Campaign Journey',
      label: t('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS'),
      to: accountScopedRoute('campaigns_journey_index'),
      activeOn: ['campaigns_journey_index'],
    },
    ...kept,
  ];
};
