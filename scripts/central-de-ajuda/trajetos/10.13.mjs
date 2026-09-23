// Roteiro do vídeo de trajeto do artigo 10.13 — "Dashboard do CRM: KPIs e
// seções". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,crm}.json e em
// app/javascript/dashboard/routes/dashboard/crm/pages/CrmDashboardPage.vue.
//
// Trajeto: barra lateral → CRM → Dashboard → cartões do topo → Funil por
// etapa → IA vs humano → atualizar. Os seletores de funil e período são
// `<select>` nativos — o vídeo só os mostra (destaque), sem trocar valor: o
// motor não tem ação para operar `<select>`.

export const id = '10.13';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'O Dashboard do funil',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Dashboard',
    acao: 'mover e clicar',
    alvo: { texto: 'Dashboard' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o funil e o período',
    acao: 'parar',
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Leia os cartões do topo',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja o Funil por etapa',
    acao: 'parar',
    alvo: { texto: 'Funil por etapa', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Compare IA vs humano',
    acao: 'parar',
    alvo: { texto: 'IA vs humano', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em atualizar',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-lucide-refresh-cw"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
