// Números › Origens (#2001, F6 do #1871) — para onde leva cada "Ver" de Números › Origens. A Lista do funil de vendas,
// em "Todos" (quem entrou e quem já fechou), só com quem entrou no funil este mês, filtrada pela origem de
// primeiro toque ou pelo anúncio de primeiro toque. O número da tela é o tamanho da lista.

// Decisão 1 (25/10): a venda conta no mês em que fechou, então a Lista mostra quem entrou OU fechou no mês.
const lista = (funilId, mes, extra) => ({
  name: 'crm_kanban_index',
  query: {
    ...(funilId ? { pipeline_id: String(funilId) } : {}),
    view: 'list',
    result: 'todos',
    entrou_em: mes,
    ...extra,
  },
});

// O gerenciador de anúncios da Meta: o gasto e a mensagem de boas-vindas moram lá.
export const GERENCIADOR_DA_META =
  'https://adsmanager.facebook.com/adsmanager/manage/ads';

// Sem funil escolhido ("Todos os funis") não há uma lista só: sem link.
export const destinoDaOrigem = (tipo, { funilId, mes, podeAbrir }) => {
  if (!funilId || !mes) return null;
  const to = lista(funilId, mes, { origem: tipo });
  return podeAbrir && !podeAbrir(to) ? null : to;
};

export const destinoDoAnuncio = (id, { funilId, mes, podeAbrir }) => {
  if (!funilId || !mes) return null;
  const to = lista(funilId, mes, { anuncio: String(id) });
  return podeAbrir && !podeAbrir(to) ? null : to;
};
