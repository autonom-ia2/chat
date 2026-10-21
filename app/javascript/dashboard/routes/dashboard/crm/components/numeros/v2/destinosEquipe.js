// #1992 (F5 do #1871) — para onde leva cada número da visão "Equipe" de CRM ›
// Números. As mesmas listas da visão "Só eu" (destinos.js), sem o "responsável =
// eu": o Kanban e a Lista do funil principal com os filtros do link da F2
// (#1886), a caixa com ?da_ia=1&esperando_min=30&no_funil=1 (#1889, #1999: só
// os funis que a pessoa vê no Números), e o filtro por uma
// pessoa no "Quem precisa de ajuda". O servidor conta o mesmo que a lista mostra.

const kanban = (funilId, extra = {}) => ({
  name: 'crm_kanban_index',
  query: {
    ...(funilId ? { pipeline_id: String(funilId) } : {}),
    ...extra,
  },
});
const lista = (funilId, extra) => kanban(funilId, { view: 'list', ...extra });
const ATRASADOS = { follow_up_status: 'overdue' };
const PARADOS = { stale_days: '7' };
const DA_PESSOA = item => ({ owner_id: String(item.pessoa.id) });
// "Fechado no mês" só existe para o mês de hoje, e a Lista mostra um funil:
// o servidor diz (`lista`) se ela mostra exatamente o que o número conta.
const doMes = (fechado, item, destino) =>
  fechado || item?.lista === false ? null : destino;

export const DESTINOS_DA_EQUIPE = {
  // Topo
  parados: ({ funis }) => kanban(funis.vendas, PARADOS),
  atrasados_equipe: ({ funis }) => kanban(funis.vendas, ATRASADOS),
  cards_equipe: ({ funis }) => kanban(funis.vendas),
  lembretes_equipe: ({ funis }) => kanban(funis.suporte, ATRASADOS),
  casos_equipe: ({ funis }) => kanban(funis.suporte),
  // Próximo passo
  sem_responsavel: ({ funis }) =>
    lista(funis.vendas, {
      result: 'won',
      closed_in: 'this_month',
      responsible_kind: 'none',
    }),
  ia_esperando: () => ({
    name: 'home',
    query: { da_ia: '1', esperando_min: '30', no_funil: '1' },
  }),
  // Vendendo e Atendendo
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
  lembretes: ({ funis }) => kanban(funis.suporte, ATRASADOS),
  parados_atende: ({ funis }) => kanban(funis.suporte, PARADOS),
  // Quem precisa de ajuda: a lista daquela pessoa.
  retornos: ({ funis, item }) =>
    kanban(funis.vendas, { ...DA_PESSOA(item), ...ATRASADOS }),
  casos_parados: ({ funis, item }) =>
    kanban(funis.suporte, { ...DA_PESSOA(item), ...PARADOS }),
  // Quem cuidou: as conversas de quem atende e a página do agente de IA.
  relatorio_pessoa: ({ item }) => ({
    name: 'agent_reports_show',
    params: { id: String(item.id) },
  }),
  agente: ({ item }) =>
    item.agenteId
      ? {
          name: 'autonomia_agent_panel',
          params: { agentId: String(item.agenteId) },
        }
      : { name: 'autonomia_agents_index' },
};

// `podeAbrir`: a mesma checagem de rota do menu; lista que a pessoa não abre
// não vira link (o modo leitura, sem o CRM, fica sem os "Ver").
export const destinoDaEquipe = (tipo, contexto) => {
  const regra = DESTINOS_DA_EQUIPE[tipo];
  const to = regra ? regra(contexto) : null;
  if (!to) return null;
  if (contexto.podeAbrir && !contexto.podeAbrir(to)) return null;
  return { to };
};
