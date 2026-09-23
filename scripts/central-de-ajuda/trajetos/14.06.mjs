// Roteiro do vídeo de trajeto do artigo 14.06 — "Visão Geral de Agentes,
// Caixa de Entrada e Time". Seletores conferidos no código-fonte:
// - nome do agente na tabela: SummaryReportLink.vue renderiza um
//   `<router-link>` com o nome da pessoa como texto — usa-se "Bia Vendas",
//   agente fixo da conta de teste.
// - seta de voltar: BackButton.vue, ícone `.i-lucide-chevron-left`.
//
// Trajeto: Relatórios → Visão Geral de Agentes → clique no nome de um
// agente → detalhe → seta de voltar.

export const id = '14.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Visão Geral de Agentes e Times',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Relatórios, Visão Geral de Agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/agents_overview`,
    aguardarTexto: 'Baixar relatórios de agentes',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Leia a tabela de agentes',
    acao: 'parar',
    alvo: { texto: 'Nº de Conversas' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique no nome de um agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Bia Vendas' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja o detalhe do agente',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique na seta de voltar',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-chevron-left' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
