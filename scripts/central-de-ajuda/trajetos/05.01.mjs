// Roteiro do vídeo de trajeto do artigo 05.01 — "O que é um Time e a tela
// de Times". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json.
//
// Trajeto: Barra lateral → Configurações → Times → ler a lista → pesquisar.
// Tela só de leitura, sem marca (confirmado com scripts/central-de-ajuda/
// ../diag); zooms no padrão do modelo.

export const id = '05.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Vídeo só de leitura — nada é criado nem alterado.
export const preparar = null;

export const cenas = [
  {
    legenda: 'O que é um Time e a tela de Times',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/teams/list`,
    aguardarTexto: 'Times',
    zoom: 1,
    duracaoMs: 3800,
  },
  {
    // O DOM guarda o nome sempre em minúsculo (o CSS só capitaliza na
    // tela) — o texto na íntegra do artigo é "vendas sul", não "Vendas Sul".
    legenda: 'Cada linha é um time',
    acao: 'parar',
    alvo: { texto: 'vendas sul' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Pesquise pelo nome do time',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Pesquisar times..."]' },
    zoom: 1.6,
  },
  {
    legenda: 'Digite o nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar times..."]' },
    texto: ['Vendas'],
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3800,
  },
];
