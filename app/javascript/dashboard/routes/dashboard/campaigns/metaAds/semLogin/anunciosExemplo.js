// "Ver um exemplo" (#1960, tela "pronto"): números de demonstração, genéricos (servem a qualquer negócio), no
// formato do painel sem gasto (Panel::Report com source 'whatsapp'). A tela marca tudo com o selo "Exemplo".
const SUM_KEYS = [
  'conversations',
  'quotes',
  'open_quotes',
  'sales',
  'sales_value',
];

// [anúncio (o nome sai do i18n), ...SUM_KEYS na mesma ordem]
const NAMES = 'CRM_KANBAN.META_ADS_HUB.SEM_LOGIN.EXAMPLE.ADS';
const ROWS = {
  30: [
    ['winter', 18, 9, 6, 3, 1200],
    ['talk', 12, 5, 4, 1, 400],
    ['shipping', 6, 2, 2, 0, 0],
  ],
  7: [
    ['winter', 5, 2, 1, 1, 400],
    ['talk', 3, 1, 1, 0, 0],
    ['shipping', 1, 0, 0, 0, 0],
  ],
};

const toAd =
  t =>
  ([id, ...numbers]) => ({
    ad_id: `exemplo-${id}`,
    name: t(`${NAMES}.${id.toUpperCase()}`),
    image_url: null,
    thumbnail_url: null,
    spend: null,
    verdict: null,
    cost_per_sale: null,
    ...Object.fromEntries(SUM_KEYS.map((key, index) => [key, numbers[index]])),
  });

export const examplePanel = (days, t) => {
  const ads = (ROWS[days] || ROWS[30]).map(toAd(t));
  const totals = Object.fromEntries(
    SUM_KEYS.map(key => [key, ads.reduce((sum, ad) => sum + ad[key], 0)])
  );
  return {
    source: 'example',
    days,
    currency: 'BRL',
    totals: { ...totals, spend: null },
    ads,
  };
};
