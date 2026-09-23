// Roteiro do vídeo de trajeto do artigo 04.01 — "'Agente' aqui é gente: a
// tela Agentes e como ler a lista". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json.
//
// Trajeto: Menu lateral → Configurações → Agentes → pesquisar → ler o
// status de cada pessoa. Tela só de leitura, sem nenhum assistente com
// marca (mesma tela usada em 04.02; zooms seguem o padrão do modelo).

export const id = '04.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Vídeo só de leitura — nada é criado nem alterado.
export const preparar = null;

export const cenas = [
  {
    legenda: 'A tela Agentes e como ler a lista',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/agents/list`,
    aguardarTexto: 'Agentes',
    zoom: 1,
    duracaoMs: 4200,
  },
  {
    legenda: 'Pesquise pelo nome ou e-mail',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Pesquisar agentes..."]' },
    zoom: 1.6,
  },
  {
    legenda: 'Digite o nome da pessoa',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar agentes..."]' },
    texto: ['Bia'],
    zoom: 1.6,
  },
  {
    legenda: 'Verificado já confirmou o e-mail',
    acao: 'parar',
    alvo: { texto: 'Verificado' },
    zoom: 1.8,
    duracaoMs: 2400,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3800,
  },
];
