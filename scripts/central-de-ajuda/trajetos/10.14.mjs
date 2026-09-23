// Roteiro do vídeo de trajeto do artigo 10.14 — "Gestão de IA do CRM: quanto
// está custando". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/pages/CrmAiUsagePage.vue.
// Tela 100% leitura — não precisa preparar nada nem disparar IA: a conta 9
// já tem uso real de IA registrado (telemetria de outras features, ex.
// agente_resposta), então os cartões e o histórico já vêm com dado de
// verdade, sem precisar simular nada.
//
// Servidor :3001 (CRM_AI_ENABLED=true).
//
// Trajeto: barra lateral → CRM → Gestão de IA → cartões do topo → período →
// Gasto por recurso → Histórico de uso → Baixar relatório.

export const id = '10.14';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3001';

export const cenas = [
  {
    legenda: 'Quanto a IA do CRM está custando',
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
    legenda: 'Clique em Gestão de IA',
    acao: 'mover e clicar',
    alvo: { texto: 'Gestão de IA' },
    zoom: 1.8,
  },
  {
    legenda: 'Leia os cartões do topo',
    acao: 'parar',
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique no período Mês',
    acao: 'mover e clicar',
    alvo: { texto: 'Mês' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja o Gasto por recurso',
    acao: 'parar',
    alvo: { texto: 'Gasto por recurso', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Confira o Histórico de uso',
    acao: 'parar',
    alvo: { texto: 'Histórico de uso', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Baixar relatório',
    acao: 'mover e clicar',
    alvo: { texto: 'Baixar relatório' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
