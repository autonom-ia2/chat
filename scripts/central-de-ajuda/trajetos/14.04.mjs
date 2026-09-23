// Roteiro do vídeo de trajeto do artigo 14.04 — "Relatório de Conversas: os
// sete gráficos e a seta de tendência". Tela de leitura (gráficos de
// linha) — o vídeo é um tour de rolagem pelos títulos reais dos blocos
// (app/javascript/dashboard/i18n/locale/pt_BR/report.json, chave
// REPORT.METRICS; cada nome fica sozinho num <span>, sem o "(Total)"/
// "(Média)" colado — conferido em ChartStats.vue), sem clicar em barra
// (ação restrita a administrador e depende de haver dado no dia).

export const id = '14.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Relatório de Conversas: os sete gráficos',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
  {
    legenda: 'Abra Relatórios, Conversas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/conversation`,
    aguardarTexto: 'Baixar relatórios de conversas',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Veja Mensagens Recebidas e enviadas',
    acao: 'parar',
    alvo: { texto: 'Mensagens Recebidas' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Role até Tempo de Primeira Resposta',
    acao: 'parar',
    alvo: { texto: 'Tempo de Primeira Resposta', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja o Tempo de Resolução',
    acao: 'parar',
    alvo: { texto: 'Tempo de Resolução' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Role até Tempo de espera do cliente',
    acao: 'parar',
    alvo: { texto: 'Tempo de espera do cliente', blocoRolagem: 'start' },
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'A seta compara com o período anterior',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
];
