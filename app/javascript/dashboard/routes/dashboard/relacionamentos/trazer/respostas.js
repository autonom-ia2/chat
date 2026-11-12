// #2896 — as respostas das perguntas de "Trazer minha lista", em funções puras:
// o que conta como respondido e qual pergunta ainda está sem resposta.
export const PERGUNTA_CLIENTES = 'clientes';
export const PERGUNTA_TELEFONE = 'telefone';
export const RESPOSTA_ALGUMAS = 'algumas';

const SEM_PERGUNTA = -1;

// A coluna escolhida é o índice dela na planilha (0 é a primeira).
const colunaEscolhida = coluna =>
  coluna !== undefined && coluna !== null && coluna !== '';

// A coluna que diz quem é cliente só vale com a resposta "Algumas".
export const responderPergunta = (respostas, pergunta, valor) => {
  const { colunaCliente, ...outras } = { ...respostas, [pergunta]: valor };
  const guardaAColuna =
    pergunta !== PERGUNTA_CLIENTES || valor === RESPOSTA_ALGUMAS;
  return guardaAColuna && colunaEscolhida(colunaCliente)
    ? { ...outras, colunaCliente }
    : outras;
};

export const perguntaRespondida = (pergunta, respostas) => {
  if (!pergunta) return true;
  if (pergunta.id !== PERGUNTA_CLIENTES) return Boolean(respostas[pergunta.id]);
  if (respostas.clientes === RESPOSTA_ALGUMAS) {
    return colunaEscolhida(respostas.colunaCliente);
  }
  return Boolean(respostas.clientes);
};

// A posição da primeira pergunta sem resposta; -1 quando todas têm.
export const primeiraSemResposta = (perguntas, respostas) =>
  Array.isArray(perguntas)
    ? perguntas.findIndex(item => !perguntaRespondida(item, respostas))
    : SEM_PERGUNTA;
