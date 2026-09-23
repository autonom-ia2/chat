// Roteiro do vídeo de trajeto do artigo 13.10 — "Ler os indicadores em
// Gestão de campanhas". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true) — sem Sidekiq no ar, nenhuma campanha de
// e-mail real foi enviada nesta conta, e não fabricamos dado de entrega
// para simular isso. Por isso o vídeo mostra o caminho até a tela e o
// estado real dela hoje — "Nenhum dado de campanha ainda" — que é, ele
// mesmo, um dos estados que o artigo descreve ("O que dá errado": "Não
// aparece nenhum cartão"). Os cartões de indicador em si (Enviados,
// Abertos, Clicados...) exigem campanha de e-mail de verdade enviada, que
// este ambiente não tem como gerar.
//
// Trajeto: CRM → Gestão de campanhas → filtros do topo → estado sem dado.

export const id = '13.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

export const cenas = [
  {
    legenda: 'Indicadores de Gestão de campanhas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
  {
    legenda: 'Abra o menu CRM',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="CRM"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Gestão de campanhas',
    acao: 'mover e clicar',
    alvo: { texto: 'Gestão de campanhas' },
    zoom: 1.8,
  },
  {
    legenda: 'Todas as campanhas soma tudo',
    acao: 'parar',
    alvo: { texto: 'Todas as campanhas' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Escolha uma campanha específica',
    acao: 'mover e clicar',
    alvo: { texto: 'Todas as campanhas' },
    zoom: 1.8,
  },
  {
    legenda: 'Filtre pela situação da campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Situação da campanha' },
    zoom: 1.8,
  },
  {
    legenda: 'Sem envio, sem cartão',
    acao: 'parar',
    alvo: { texto: 'Nenhum dado de campanha ainda' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
];
