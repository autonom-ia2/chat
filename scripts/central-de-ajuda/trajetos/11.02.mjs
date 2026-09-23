// Roteiro do vídeo de trajeto do artigo 11.02 — "Decidir externo ou interno,
// com base ou sem base". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json e no componente
// AgentTypePicker.vue.
//
// IMPORTANTE (IA): clicar num cartão de tipo cria o agente de verdade e abre
// a conversa do Construtor, que fala primeiro sozinha — startThread() dispara
// uma chamada real de IA (ver comentário "IA-FALA-PRIMEIRO" em
// AgentBuilderPage.vue). Por isso este vídeo NUNCA clica num cartão: mostra
// as duas escolhas e passa o mouse sobre um cartão, sem soltar o clique.
//
// Trajeto: barra lateral → Construtor de agentes → Externo/Interno →
// Com base/Sem base → passar o mouse num cartão de tipo.

export const id = '11.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: a tela do Construtor não depende de nenhum agente
// existente, e este vídeo não cria nenhum (evita a chamada real de IA).

export const cenas = [
  {
    legenda: 'Decidir o tipo do seu agente',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra o Construtor de agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/agents/new`,
    aguardarTexto: 'O que seu agente deve fazer?',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Escolha Externo ou Interno',
    acao: 'mover e clicar',
    alvo: { texto: 'Interno' },
    zoom: 1.8,
  },
  {
    legenda: 'Leia a frase de ajuda da escolha',
    acao: 'parar',
    alvo: { texto: 'Nunca fala com cliente — só ajuda o atendente.' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Volte para Externo',
    acao: 'mover e clicar',
    alvo: { texto: 'Externo' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha Com base ou Sem base',
    acao: 'mover e clicar',
    alvo: { texto: 'Sem base' },
    zoom: 1.8,
  },
  {
    legenda: 'Leia a frase de ajuda da escolha',
    acao: 'parar',
    alvo: { texto: 'Sem documentos — orienta por regras e encaminha.' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Volte para Com base',
    acao: 'mover e clicar',
    alvo: { texto: 'Com base' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique num cartão de tipo',
    acao: 'passar o mouse',
    alvo: { texto: 'Suporte' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Ou em Começar do zero',
    acao: 'passar o mouse',
    alvo: { texto: 'Começar do zero' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
