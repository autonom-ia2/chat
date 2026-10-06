// Campanhas menu of the new journey (#993, PRD D17). Sidebar.vue only hands its current
// children here: with the flag off they come back untouched; with it on the group shows
// Público, Campanha, Modelos, Links e QR codes, Anúncios da Meta (#1068, when its flag is on)
// and Gestão de campanhas, in this order, reusing the existing entries for the last four.
const KEPT_ENTRIES = [
  'Campaign WhatsApp Templates',
  'Campaign Links and QR codes',
  'Campaign Meta Ads',
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
          activeOn: [
            'campaigns_journey_audiences',
            'campaigns_journey_audience_new',
          ],
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
      // A campaign's Resultado (#1007) belongs to Campanha.
      activeOn: [
        'campaigns_journey_index',
        'campaigns_journey_new',
        'campaigns_journey_live_chat_new',
        'campaigns_journey_live_chat_edit',
        'campaigns_journey_result',
      ],
    },
    ...kept,
  ];
};
