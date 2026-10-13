// #1424 — ADAPTADOR FALSO do protótipo da Fase 2 dos Agentes. Mesmas funções que a API vai ter, com
// dados fixos em memória (somem no F5, de propósito: a demonstração recomeça igual). Não interpreta o
// texto da pessoa: o resultado de "Mudar conversando" é sempre o mesmo exemplo, para o Rodrigo ver a
// tela. Quem usa importa ./fonte.js, nunca este arquivo.

const ESPERA_MS = 1400;
const esperar = (ms = ESPERA_MS) =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// Onde cada agente da demonstração trabalha (#1366, #1433), no modelo do Rodrigo (rodada 2):
// - quem conversa com cliente fica DENTRO de caixas, com um papel em cada uma: "primeiro" (atende
//   primeiro, a porta: um por caixa) ou "recebe" (recebe quando alguém passar, por atribuição);
// - quem ajuda outros agentes não tem caixa, e diz quais agentes ajuda e quando é chamado.
// `assuntos` são os funis escolhidos depois, no CRM ("Quem cuida do quê?"). O servidor de verdade
// responde por id de agente e de caixa; aqui os agentes e as caixas da semente são achados pelo nome.
const PAPEIS_DA_DEMO = {
  Clara: {
    tipo: 'clientes',
    caixas: [
      { caixa: 'WhatsApp Loja', papel: 'primeiro', assuntos: ['Comercial'] },
    ],
  },
  Maria: {
    tipo: 'clientes',
    caixas: [
      { caixa: 'WhatsApp Loja', papel: 'recebe', assuntos: ['Vendas'] },
      { caixa: '@lojaexemplo', papel: 'recebe', assuntos: ['Vendas'] },
    ],
  },
  Joana: {
    tipo: 'clientes',
    caixas: [{ caixa: '@lojaexemplo', papel: 'primeiro', assuntos: [] }],
  },
  'Joana-produto-auto': {
    tipo: 'ajuda',
    ajuda: ['Joana', 'Clara'],
    quando: 'Quando a dúvida for sobre um produto',
  },
};

// Papel escolhido na criação antes de o rascunho existir (a jornada vem antes da conversa).
const RASCUNHO = 'novo';
// Guardado na aba (sessionStorage): sobrevive ao F5 e some ao fechar a aba, para a demonstração
// recomeçar igual. Sem acesso ao armazenamento, fica só em memória.
const GUARDADO = 'prototipo-fase2-papeis';
const lerGuardado = () => {
  try {
    return JSON.parse(window.sessionStorage.getItem(GUARDADO) || 'null');
  } catch {
    return null;
  }
};
const definidos = new Map(
  lerGuardado() ||
    Object.entries(PAPEIS_DA_DEMO).map(([nome, papel]) => [
      `nome:${nome}`,
      papel,
    ])
);
const guardar = () => {
  try {
    window.sessionStorage.setItem(GUARDADO, JSON.stringify([...definidos]));
  } catch {
    // Sem armazenamento: segue em memória.
  }
};
const chaveDe = agente => `nome:${agente.name}`;

const listarPapeis = async agentes => {
  await esperar(300);
  return Object.fromEntries(
    (agentes || []).map(agente => [
      agente.id,
      definidos.get(chaveDe(agente)) || null,
    ])
  );
};

// Atender primeiro numa caixa tira dali quem atendia primeiro: essa pessoa passa a receber.
const passarPortas = (agente, papel) => {
  const portas = (papel?.caixas || [])
    .filter(item => item.papel === 'primeiro')
    .map(item => item.caixa);
  definidos.forEach((outro, chave) => {
    if (chave === chaveDe(agente) || chave === RASCUNHO) return;
    if (outro?.tipo !== 'clientes') return;
    definidos.set(chave, {
      ...outro,
      caixas: outro.caixas.map(item =>
        portas.includes(item.caixa) && item.papel === 'primeiro'
          ? { ...item, papel: 'recebe' }
          : item
      ),
    });
  });
};

const definirPapel = async (agente, papel) => {
  await esperar(900);
  passarPortas(agente, papel);
  definidos.set(chaveDe(agente), papel);
  guardar();
  return papel;
};

const guardarRascunho = papel => {
  definidos.set(RASCUNHO, papel);
  guardar();
};

const rascunho = () => definidos.get(RASCUNHO) || null;

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
  guardarRascunho,
  rascunho,
  aplicarPedido,
  responderDuvida,
  desfazer,
};
