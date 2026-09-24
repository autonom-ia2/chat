// Roteiro do vídeo de trajeto do artigo 14.10 — "Baixar, compartilhar e o
// que fazer com telas vazias". O Chrome headless não tem barra de endereço
// visível no recorte gravado — "copie o link da página" (o jeito de
// compartilhar) não dá pra mostrar em vídeo aqui; fica só no texto do
// artigo. O vídeo mostra o que é gravável: ajustar período/filtro e onde
// fica o botão de baixar CSV.
//
// Não clica no botão de baixar de propósito: um download real no Chrome
// headless não tem para onde ir (sem pasta de downloads configurada) e
// arrisca travar a gravação — mesma escolha feita no 14.07 para o mesmo
// botão.
//
// Seletores conferidos no código-fonte (routes/dashboard/settings/reports/
// Index.vue, report.json REPORT.*):
// - cabeçalho: "Conversas" (REPORT.HEADER).
// - botão de baixar: "Baixar relatórios de conversas"
//   (REPORT.DOWNLOAD_CONVERSATION_REPORTS).
//
// Trajeto: Relatórios → Conversas → ajuste o período → mostra o botão de
// baixar (sem clicar).

export const id = '14.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a criar: a tela de Conversas lê dados que já existem na conta.

export const cenas = [
  {
    legenda: 'Baixar e compartilhar relatórios',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Relatórios, Conversas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/conversation`,
    aguardarTexto: 'Baixar relatórios de conversas',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Ajuste período e filtros antes',
    acao: 'mover e clicar',
    alvo: { texto: 'Últimos 7 dias' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha outro período, se quiser',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Feche o calendário',
    acao: 'mover e clicar',
    alvo: { texto: 'Últimos 7 dias' },
    zoom: 1.6,
  },
  {
    legenda: 'O botão de baixar fica aqui',
    acao: 'parar',
    alvo: { texto: 'Baixar relatórios de conversas' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'O arquivo sai com a data final do período',
    acao: 'parar',
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
