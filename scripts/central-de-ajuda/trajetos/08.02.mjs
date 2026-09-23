// Roteiro do vídeo de trajeto do artigo 08.02 — "Escolher a fila certa:
// Minhas, Não atribuídas, Todos e Não atendidas". Seletores conferidos no
// DOM renderizado (login manual de exploração): as três abas do topo da
// lista são <li> filhos diretos do mesmo <ul>, cada um com um
// `a.text-button`, nesta ordem fixa (Minhas, Não atribuídas, Todos) — o
// texto de cada aba tem o total da fila colado (ex. "Todos 4"), por isso o
// alvo usa posição (nth-child), não texto. "Não atendidas" é outro link no
// menu lateral (app/javascript/dashboard/components-next/sidebar/Sidebar.vue),
// com o total colado do mesmo jeito — o alvo usa o href, estável.
//
// Trajeto: tela de Conversas (já é a rota padrão) → aba Minhas → aba Não
// atribuídas → aba Todos → link Não atendidas no menu lateral.

export const id = '08.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Escolher a fila certa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique na aba Minhas',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(1) > a.text-button' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique na aba Não atribuídas',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(2) > a.text-button' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Não atendidas',
    acao: 'mover e clicar',
    alvo: { seletor: 'a[href="/app/accounts/9/unattended/conversations"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja a fila de resgate',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
