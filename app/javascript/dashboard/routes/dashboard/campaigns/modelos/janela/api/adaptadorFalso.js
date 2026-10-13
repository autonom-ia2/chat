// Adaptador FALSO do protótipo (#1335). Números e textos inventados, para a
// jornada poder ser clicada antes do backend. `?demo=` no endereço mostra os
// outros casos: `ninguem` (ninguém do público falou nas últimas 24 h), `erro`
// (a ajuda para escrever não responde) e `pergunta` (a ajuda pede mais detalhe).
const ESPERA_MS = 900;
const PARTE_QUE_FALOU = 0.031;

// Lido quando o módulo carrega: a Nova campanha reescreve o endereço logo depois.
const MODO_DEMO = new URLSearchParams(window.location.search).get('demo') || '';
const modoDemo = () => MODO_DEMO;

const esperar = () =>
  new Promise(resolve => {
    setTimeout(resolve, ESPERA_MS);
  });

const contarJanela = async ({ total }) => {
  await esperar();
  const dentro =
    modoDemo() === 'ninguem'
      ? 0
      : Math.min(total, Math.max(1, Math.round(total * PARTE_QUE_FALOU)));
  return {
    dentro,
    fora: total - dentro,
    fechamLogo: Math.min(dentro, 6),
    conferidoEm: new Date().toISOString(),
  };
};

const OPCOES = [
  'Oi, {{cliente.primeiro_nome}}! Que bom falar com você hoje. Chegou a coleção nova e separei as peças que combinam com o que você procurou. Quer que eu mande as fotos aqui?',
  '{{cliente.primeiro_nome}}, a coleção nova chegou. Posso reservar a sua peça antes de abrir para todo mundo? É só responder esta mensagem.',
];

const MELHORADAS = {
  mais_curta:
    '{{cliente.primeiro_nome}}, chegou a coleção nova. Quer ver as fotos? Responda aqui.',
  mais_simpatica:
    'Oi, {{cliente.primeiro_nome}}! Lembrei de você: chegou a coleção nova, com aquelas peças que você gostou. Quer que eu mande as fotos?',
  mais_clara:
    '{{cliente.primeiro_nome}}, a coleção nova chegou hoje. Se quiser ver as fotos, responda esta mensagem que eu mando aqui mesmo.',
};

const escrever = async ({ pedido }) => {
  await esperar();
  const modo = modoDemo();
  if (modo === 'erro') throw new Error('indisponivel');
  if (modo === 'pergunta' && !pedido) {
    return {
      status: 'precisa_mais_info',
      opcoes: [],
      pergunta:
        'O que a pessoa precisa fazer depois de ler? Ex.: responder, passar na loja, reservar.',
    };
  }
  if (pedido?.melhoria) {
    return {
      status: 'ok',
      opcoes: [{ texto: MELHORADAS[pedido.melhoria] || OPCOES[0] }],
      pergunta: null,
    };
  }
  return {
    status: 'ok',
    opcoes: OPCOES.map(texto => ({ texto })),
    pergunta: null,
  };
};

export default { contarJanela, escrever };
