import { valoresRespondidos } from './valoresDeCliente';

// #2896 — as respostas das perguntas de "Trazer minha lista", em funções puras:
// o que conta como respondido e qual pergunta ainda está sem resposta.
// E3 — a pergunta "Quais destes querem dizer cliente?" (`valores_cliente`) é da
// coluna que diz quem é cliente: mudar a resposta de "São clientes?" ou a
// coluna apaga os valores marcados (trazer/valoresDeCliente.js).
export const PERGUNTA_CLIENTES = 'clientes';
export const PERGUNTA_TELEFONE = 'telefone';
export const PERGUNTA_VALORES = 'valores_cliente';
export const RESPOSTA_ALGUMAS = 'algumas';

const SEM_PERGUNTA = -1;
const SEM_COLUNA = null;

// A coluna escolhida é o índice dela na planilha (0 é a primeira).
const colunaEscolhida = coluna =>
  coluna !== undefined && coluna !== null && coluna !== '';

const sem = (respostas, chave) =>
  Object.fromEntries(
    Object.entries(respostas).filter(([nome]) => nome !== chave)
  );

const respondido = valor => valor !== undefined && valor !== null;

// A coluna que diz quem é cliente só vale com a resposta "Algumas". A resposta
// nula (a pessoa desmarcou tudo) tira a resposta da pergunta.
export const responderPergunta = (respostas, pergunta, valor) => {
  const mudouDeClientes =
    pergunta === PERGUNTA_CLIENTES && respostas[PERGUNTA_CLIENTES] !== valor;
  const base = mudouDeClientes ? sem(respostas, PERGUNTA_VALORES) : respostas;
  const { colunaCliente, ...outras } = respondido(valor)
    ? { ...base, [pergunta]: valor }
    : sem(base, pergunta);
  const guardaAColuna =
    pergunta !== PERGUNTA_CLIENTES || valor === RESPOSTA_ALGUMAS;
  return guardaAColuna && colunaEscolhida(colunaCliente)
    ? { ...outras, colunaCliente }
    : outras;
};

// Os valores marcados eram os da coluna de antes.
export const trocarColunaDeCliente = (respostas, coluna) =>
  respostas.colunaCliente === coluna
    ? respostas
    : { ...sem(respostas, PERGUNTA_VALORES), colunaCliente: coluna };

export const perguntaRespondida = (pergunta, respostas) => {
  if (!pergunta) return true;
  if (pergunta.id === PERGUNTA_VALORES) {
    return valoresRespondidos(respostas[PERGUNTA_VALORES]);
  }
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

export const posicaoDaPergunta = (perguntas, id) =>
  Array.isArray(perguntas)
    ? perguntas.findIndex(item => item.id === id)
    : SEM_PERGUNTA;

// A pergunta dos valores vem do servidor, para a coluna que ele conhece. Quando
// a resposta de "São clientes?" na tela aponta outra coluna (ou nenhuma), a
// pergunta que a leitura traz já não serve: a tela grava antes de seguir.
export const mudouQuemDizQuemEhCliente = (perguntas, respostas) => {
  const daTela =
    respostas.clientes === RESPOSTA_ALGUMAS &&
    colunaEscolhida(respostas.colunaCliente)
      ? respostas.colunaCliente
      : SEM_COLUNA;
  const dosValores = (perguntas ?? []).find(
    item => item.id === PERGUNTA_VALORES
  );
  return daTela !== (dosValores ? dosValores.indice : SEM_COLUNA);
};
