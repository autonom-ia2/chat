// Bloco "De onde vieram as vendas" de Números. #1876: toda origem que o
// servidor manda tem nome (campanhas e o chat do site inclusive), a venda sem
// toque vem na linha "Sem origem" (`none`) e a origem vazia nunca vira anúncio.
export const NO_ORIGIN = 'none';

export const ORIGIN_SOURCES = [
  {
    key: 'meta_ctwa',
    icon: 'i-lucide-message-circle',
    barClass: 'bg-n-blue-9',
  },
  { key: 'meta_organic', icon: 'i-lucide-leaf', barClass: 'bg-n-teal-9' },
  { key: 'google_ads', icon: 'i-lucide-search', barClass: 'bg-n-amber-9' },
  { key: 'tiktok_ads', icon: 'i-lucide-music-2', barClass: 'bg-n-violet-9' },
  {
    key: 'meta_paid',
    icon: 'i-lucide-badge-dollar-sign',
    barClass: 'bg-n-ruby-9',
  },
  { key: 'tracked_link', icon: 'i-lucide-link', barClass: 'bg-n-slate-9' },
  { key: 'campaign_whatsapp', icon: 'i-lucide-send', barClass: 'bg-n-iris-9' },
  { key: 'campaign_email', icon: 'i-lucide-mail', barClass: 'bg-n-brand' },
  {
    key: 'campaign_sms',
    icon: 'i-lucide-message-square-text',
    barClass: 'bg-n-teal-9',
  },
  {
    key: 'campaign_live_chat',
    icon: 'i-lucide-messages-square',
    barClass: 'bg-n-blue-7',
  },
  { key: NO_ORIGIN, icon: 'i-lucide-circle-dashed', barClass: 'bg-n-slate-8' },
].map(source => ({
  ...source,
  labelKey: `CRM_DASHBOARD.ORIGIN.SOURCES.${source.key.toUpperCase()}`,
}));

const SOURCE_BY_KEY = Object.fromEntries(
  ORIGIN_SOURCES.map(source => [source.key, source])
);

// Origem que o painel não conhece não ganha linha própria: é venda sem origem
// que a tela sabe nomear.
const lineFor = source => (SOURCE_BY_KEY[source] ? source : NO_ORIGIN);

const addValues = (list, extra) => {
  const byCurrency = new Map(list.map(item => [item.currency, item]));
  extra.forEach(({ currency, value_cents: cents }) => {
    const current = byCurrency.get(currency)?.value_cents || 0;
    byCurrency.set(currency, {
      currency,
      value_cents: current + Number(cents || 0),
    });
  });
  return [...byCurrency.values()].sort((a, b) =>
    String(a.currency || '').localeCompare(String(b.currency || ''))
  );
};

export const originRows = metrics => {
  const totals = (metrics || []).reduce((acc, metric) => {
    const key = lineFor(metric.source);
    const current = acc[key] || { wonCount: 0, valueList: [] };
    return {
      ...acc,
      [key]: {
        wonCount: current.wonCount + Number(metric.won_count || 0),
        valueList: addValues(
          current.valueList,
          metric.won_value_by_currency || []
        ),
      },
    };
  }, {});

  return ORIGIN_SOURCES.filter(source => {
    const row = totals[source.key];
    return row && (row.wonCount > 0 || row.valueList.length > 0);
  }).map(source => ({
    source: source.key,
    icon: source.icon,
    barClass: source.barClass,
    labelKey: source.labelKey,
    ...totals[source.key],
  }));
};
