// Roteiro do vídeo de trajeto do artigo 00.08 — "Passo 7 — Criar o agente de
// IA". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json (AGENTS_BUILDER)
// e app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.BUILDER,
// AgentTypePicker).
//
// PARCIAL, DE PROPÓSITO (pedido do Rodrigo): o Construtor chama a IA de
// verdade assim que uma atuação é escolhida — `AgentBuilderPage.vue`
// (onPickType -> startThread(), e de novo em todo onMounted com
// agentType já definido) abre a conversa "IA-fala-primeiro" com uma chamada
// real ao provedor. Este vídeo grava só até a tela de escolha do tipo
// (Externo/Interno, Com base/Sem base) e alterna as duas opções para
// mostrar a frase de ajuda de cada uma — sem clicar em nenhum cartão de
// tipo, que é o que dispara a IA (mesmo caminho, mesmo motivo, do roteiro
// 11.02.mjs).
//
// Trajeto: barra lateral → Agentes → Construtor de agentes → Externo/Interno
// → Com base/Sem base → passar o mouse num cartão, sem clicar.

export const id = '00.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: a tela de escolha do Construtor não depende de nenhum
// agente existente, e este vídeo não cria nenhum (evita a chamada real de
// IA).

export const cenas = [
  {
    legenda: 'Criar o agente de IA',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Agentes na barra lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Agentes' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Construtor de agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Construtor de agentes' },
    aguardarTextoDepois: 'O que seu agente deve fazer?',
    zoom: 2,
  },
  {
    legenda: 'Escolha Externo ou Interno',
    acao: 'mover e clicar',
    alvo: { texto: 'Interno' },
    zoom: 1.8,
  },
  {
    legenda: 'Interno ajuda só a equipe',
    acao: 'parar',
    alvo: { texto: 'Nunca fala com cliente — só ajuda o atendente.' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Volte para Externo, que fala com o cliente',
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
    legenda: 'Sem base orienta por regras',
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
    legenda: 'Escolha um tipo pronto para começar',
    acao: 'passar o mouse',
    alvo: { texto: 'Suporte' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
