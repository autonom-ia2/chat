// #1424 — ADAPTADOR FALSO do protótipo da Fase 2 dos Agentes. Mesmas funções que a API vai ter, com
// dados fixos em memória (somem no F5, de propósito: a demonstração recomeça igual). Não interpreta o
// texto da pessoa: o resultado de "Mudar conversando" é sempre o mesmo exemplo, para o Rodrigo ver a
// tela. Quem usa importa ./fonte.js, nunca este arquivo.

const ESPERA_MS = 1400;
const esperar = (ms = ESPERA_MS) =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// Onde cada agente da demonstração trabalha sem canal próprio (#1366, #1433). O servidor de verdade
// responde por id; aqui os agentes da semente local são achados pelo nome. As áreas da equipe são
// CAIXA + FUNIL, escolhidas no CRM em "Caixas no CRM › Quem cuida do quê?" (vocabulário do Multifunil).
const PAPEIS_DA_DEMO = {
  Maria: {
    tipo: 'equipe',
    areas: [
      { caixa: 'WhatsApp Loja', funil: 'Comercial' },
      { caixa: 'WhatsApp Loja', funil: 'Financeiro' },
    ],
  },
  Marta: { tipo: 'equipe', caixa: 'WhatsApp Loja', areas: [] },
  'Joana-produto-auto': { tipo: 'ajuda', agente: 'Joana' },
};

const definidos = new Map();

const listarPapeis = async agentes => {
  await esperar(300);
  return Object.fromEntries(
    (agentes || []).map(agente => [
      agente.id,
      definidos.get(agente.id) || PAPEIS_DA_DEMO[agente.name] || null,
    ])
  );
};

const definirPapel = async (agente, papel) => {
  await esperar(900);
  definidos.set(agente.id, papel);
  return papel;
};

// ---------- Mudar conversando conferido (#1428) ----------
const PROVA = {
  ok: 3,
  total: 3,
  perguntas: [
    {
      pergunta: 'Quanto custa o plano anual?',
      resposta:
        'Quem passa os valores é a nossa equipe. Já chamei alguém para falar com você.',
    },
    {
      pergunta: 'Vocês abrem no sábado?',
      resposta: 'Abrimos no sábado, das 9h às 13h. Posso ajudar em algo mais?',
    },
    {
      pergunta: 'Como troco o meu plano?',
      resposta:
        'Você troca pelo app, em Meu plano. Se preferir, a equipe faz por você.',
    },
  ],
};

const DUVIDA = {
  id: 'tom',
  estado: 'duvida',
  pedido: 'falar mais animado',
  opcoes: [
    {
      valor: 'exclamacoes',
      texto: 'Usar exclamações e emojis',
      aplicado: 'Tom: mais animado, com exclamações e emojis',
    },
    {
      valor: 'nome',
      texto: 'Chamar o cliente pelo nome',
      aplicado: 'Tom: chama o cliente pelo nome',
    },
    {
      valor: 'nada',
      texto: 'Deixar como está',
      aplicado: 'Tom: ficou como estava, a seu pedido',
    },
  ],
};

const aplicarPedido = async () => {
  await esperar();
  return {
    resposta:
      'Mudei o que você pediu e testei com 3 perguntas de prova. Uma parte eu não entendi: veja abaixo.',
    itens: [
      { id: 'frases', estado: 'aplicado', texto: 'Respostas com até 2 frases' },
      { id: 'preco', estado: 'aplicado', texto: 'Preço: passa para a equipe' },
      DUVIDA,
    ],
    prova: PROVA,
  };
};

const responderDuvida = async (resultado, itemId, valor) => {
  await esperar();
  const opcao = DUVIDA.opcoes.find(item => item.valor === valor);
  return {
    resposta: `Feito. Testei de novo com as 3 perguntas de prova.`,
    itens: resultado.itens.map(item =>
      item.id === itemId
        ? { id: item.id, estado: 'aplicado', texto: opcao.aplicado }
        : item
    ),
    prova: PROVA,
  };
};

const desfazer = async () => {
  await esperar(900);
  return { desfeito: true };
};

export default {
  listarPapeis,
  definirPapel,
  aplicarPedido,
  responderDuvida,
  desfazer,
};
