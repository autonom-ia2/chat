// #1871 — para onde leva cada número de CRM › Números. Toda lista já existe e
// abre já filtrada pelos filtros do link (F2: Kanban e Lista no #1886, caixa no
// #1889). F3 (#1897): só os da visão "Só eu", sempre com responsável = eu.
// Cada número conta o mesmo que a lista mostra (atrasado = retorno vencido,
// parado = 7 dias sem mensagem nem mudança de etapa).

const EU = 'me';

const kanban = (funilId, extra = {}) => ({
  name: 'crm_kanban_index',
  query: {
    ...(funilId ? { pipeline_id: String(funilId) } : {}),
    owner_id: EU,
    ...extra,
  },
});
const lista = (funilId, extra) => kanban(funilId, { view: 'list', ...extra });
const ATRASADOS = { follow_up_status: 'overdue' };
const PARADOS = { stale_days: '7' };
// "Fechado no mês" só existe para o mês de hoje, e a Lista filtra pelo dono atual: o servidor diz (`lista`) se
// ela mostra exatamente os cards creditados; senão, o número fica sem link.
const doMes = (fechado, item, destino) =>
  fechado || item?.lista === false ? null : destino;

export const DESTINOS = {
  meus_atrasados: ({ funis }) => kanban(funis.vendas, ATRASADOS),
  meus_parados: ({ funis }) => kanban(funis.vendas, PARADOS),
  meus_cards: ({ funis }) => kanban(funis.vendas),
  meus_lembretes: ({ funis }) => kanban(funis.suporte, ATRASADOS),
  meus_casos: ({ funis }) => kanban(funis.suporte),
  fechadas: ({ funis, fechado, item }) =>
    doMes(
      fechado,
      item,
      lista(funis.vendas, { result: 'won', closed_in: 'this_month' })
    ),
  andamento: ({ funis }) => kanban(funis.vendas),
  atrasados: ({ funis }) => kanban(funis.vendas, ATRASADOS),
  resolvidos: ({ funis, fechado, item }) =>
    doMes(
      fechado,
      item,
      lista(funis.suporte, { result: 'resolved', closed_in: 'this_month' })
    ),
  // Sem link até a caixa ter filtro de responsável pelo endereço: "com você agora" conta as
  // conversas abertas atribuídas a mim, e a caixa abre com o status e a aba salvos da pessoa.
  com_voce: () => null,
  deu_certo: () => ({ name: 'csat_reports' }),
  campanha_com_voce: ({ funis, item }) =>
    kanban(funis.vendas, { campaign_source_ids: item.origem }),
  // Mesmo limite: "a IA te passou" conta as passagens para mim no mês, e `?da_ia=1` mostra
  // todas as recebidas da IA que a pessoa vê, sem mês e sem responsável.
  ia_passou: () => null,
  criar_funil: () => ({ name: 'crm_kanban_index' }),
};

// `podeAbrir`: a mesma checagem de rota do menu; lista que a pessoa não abre
// (ex.: satisfação sem relatórios) não vira link.
export const destino = (tipo, contexto) => {
  const regra = DESTINOS[tipo];
  const to = regra ? regra(contexto) : null;
  if (!to) return null;
  if (contexto.podeAbrir && !contexto.podeAbrir(to)) return null;
  return { to };
};
