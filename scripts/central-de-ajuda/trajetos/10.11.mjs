// Roteiro do vídeo de trajeto do artigo 10.11 — "Calendário do CRM e
// agendar reunião". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_KANBAN.CALENDAR)
// e em app/javascript/dashboard/routes/dashboard/crm/components/calendar/
// CrmCalendarHeader.vue.
//
// Achado: CRM_CALENDAR_MEETINGS_ENABLED está "false" nos dois servidores
// deste lote (conferido em window.globalConfig via curl, 2026-09-24) —
// diferente do que as instruções do lote diziam ("todos os recursos
// ligados"). Por isso o vídeo cobre só a parte SEMPRE disponível do
// Calendário (navegação, sobreposições, escopo, Lembrete de retorno) e
// deixa de fora "Agendar reunião" e "Página de agendamento", que dependem
// dessa flag. Reportado na resposta final, não corrigido aqui (motor
// congelado, e a flag não é algo que o vídeo controla).

export const id = '10.11';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

// Vídeo só de leitura no calendário (navegação, sobreposições, escopo,
// atalho de lembrete de retorno) — nada é criado.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Calendário do CRM',
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
    legenda: 'Clique em Calendário',
    acao: 'mover e clicar',
    alvo: { texto: 'Calendário' },
    zoom: 1.8,
    aguardarTextoDepois: 'Lembretes',
  },
  {
    legenda: 'Alterne para a visão Semana',
    acao: 'mover e clicar',
    alvo: { texto: 'Semana' },
    zoom: 1.6,
  },
  {
    legenda: 'Mostre ou esconda o WhatsApp',
    acao: 'mover e clicar',
    alvo: { texto: 'WhatsApp' },
    zoom: 1.8,
  },
  {
    legenda: 'Troque o escopo para Todos',
    acao: 'mover e clicar',
    alvo: { texto: 'Todos' },
    zoom: 1.8,
  },
  {
    legenda: 'Ligue o Lembrete de retorno',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[role="switch"][aria-label="Lembrete de retorno"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
