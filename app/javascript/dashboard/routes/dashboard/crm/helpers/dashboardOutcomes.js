import { countsAsSale } from './cardOutcome';

// Números do Dashboard do CRM conforme o tipo do funil (#1151). Funil de venda
// mostra ganhos e perdidos; funil de atendimento mostra resolvidos e cancelados,
// e nunca vira venda. Pessoas, conversas e cards são contados à parte: uma
// conversa pode ter vários cards.
export const showsSales = summary => countsAsSale(summary);

export const outcomeKpis = summary => {
  if (showsSales(summary)) {
    return [
      { key: 'WON', value: summary?.won_count || 0 },
      { key: 'LOST', value: summary?.lost_count || 0 },
    ];
  }
  return [
    { key: 'RESOLVED', value: summary.resolved_count || 0 },
    { key: 'CANCELLED', value: summary.cancelled_count || 0 },
  ];
};

const SALE_DATASETS = [
  { key: 'won', labelKey: 'WON', color: '#16a34a' },
  { key: 'lost', labelKey: 'LOST', color: '#e11d48' },
];

const SERVICE_DATASETS = [
  { key: 'resolved', labelKey: 'RESOLVED', color: '#16a34a' },
  { key: 'cancelled', labelKey: 'CANCELLED', color: '#e11d48' },
];

export const throughputDatasets = throughput =>
  countsAsSale(throughput) ? SALE_DATASETS : SERVICE_DATASETS;

export const openWork = summary => [
  { key: 'PEOPLE', value: summary?.open_people_count || 0 },
  { key: 'CONVERSATIONS', value: summary?.open_conversations_count || 0 },
  { key: 'CARDS', value: summary?.open_count || 0 },
];
