// Roteiro do vídeo de trajeto do artigo 14.02 — "Visão geral: números ao
// vivo, status, calor e tabelas". É uma tela de leitura (números que se
// atualizam sozinhos, mapas de calor, tabelas) — o "Como faz" do artigo é
// rolar e ler, não clicar; o vídeo por isso é um tour de rolagem pelos
// títulos reais dos cards (conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/report.json,
// chave OVERVIEW_REPORTS), sem nenhuma mutação de dado.

export const id = '14.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Visão geral: números ao vivo e calor',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Relatórios, Visão geral',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/overview`,
    aguardarTexto: 'Conversas Abertas',
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    legenda: 'Leia os números de Conversas Abertas',
    acao: 'parar',
    alvo: { texto: 'Conversas Abertas' },
    zoom: 1.3,
    duracaoMs: 2200,
  },
  {
    legenda: 'Veja o Status do agente',
    acao: 'parar',
    alvo: { texto: 'Status do agente' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Role até Tráfego de conversa',
    acao: 'parar',
    alvo: { texto: 'Tráfego de conversa', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Role até Conversas por agentes',
    acao: 'parar',
    alvo: { texto: 'Conversas por agentes', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Veja a fila de cada time',
    acao: 'parar',
    alvo: { texto: 'Conversas por times', blocoRolagem: 'start' },
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
