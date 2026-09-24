// Roteiro do vídeo de trajeto do artigo 05.06 — "Usar o time em Automação,
// Macros e Relatórios". O próprio artigo é uma referência cruzada (três
// telas curtas, não um fluxo único) — o vídeo segue o mesmo formato:
// Automação (onde a condição/ação "Time" mora) → Relatórios → Time → CRM →
// Filtros → Time. Sem criar nem salvar nada (só mostra onde cada peça
// fica); a regra "time é filtro/condição/ação em 4 lugares" é o que o
// vídeo prova, o texto do artigo explica o resto.
//
// Rótulos conferidos em app/javascript/dashboard/i18n/locale/pt_BR/
// automation.json (ASSIGN_TEAM) e crm.json (CRM_KANBAN.FILTERS.TEAM).

export const id = '05.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

// Vídeo só de leitura — abre telas existentes, não cria nem salva nada.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Usar o time em Automação, Macros e Relatórios',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações → Automação',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/automation/list`,
    aguardarTexto: 'Etiquetar pedidos de sinistro',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Veja a regra de automação existente',
    acao: 'parar',
    alvo: { texto: 'Etiquetar pedidos de sinistro' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Abra Relatórios → Time',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/teams_overview`,
    aguardarTexto: 'Time',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Escolha o time no relatório',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Kanban',
    acao: 'mover e clicar',
    alvo: { texto: 'Kanban' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Filtros',
    acao: 'mover e clicar',
    alvo: { texto: 'Filtros' },
    zoom: 1.6,
  },
  {
    legenda: 'Filtre os cards pelo Time',
    acao: 'selecionar',
    alvo: {
      seletor: '.flex.w-80.flex-col.gap-3.p-4 > label:nth-of-type(6) select',
    },
    valor: 'vendas sul',
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
