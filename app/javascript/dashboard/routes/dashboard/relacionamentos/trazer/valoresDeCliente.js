// #2896, E3 — a resposta de "Quais destes querem dizer cliente?", em funções
// puras. Quem decide o que quer dizer cliente é a pessoa: a tela não adivinha
// pelo texto da célula, e nada vem marcado. A resposta tem duas formas, que não
// se misturam (o formato é o do servidor):
//   - `{ modo: 'preenchidas' }`: toda linha com algo escrito na coluna;
//   - `{ modo: 'valores', chaves: [...] }`: os valores que a pessoa marcou. A
//     chave de cada valor vem do servidor; o texto da célula nunca volta.
// Sem nada marcado não há resposta (`null`).
export const MODOS = { PREENCHIDAS: 'preenchidas', VALORES: 'valores' };

const SEM_RESPOSTA = null;

export const marcouPreenchidas = resposta =>
  resposta?.modo === MODOS.PREENCHIDAS;

export const chavesMarcadas = resposta =>
  resposta?.modo === MODOS.VALORES && Array.isArray(resposta.chaves)
    ? resposta.chaves
    : [];

export const valorMarcado = (resposta, chave) =>
  chavesMarcadas(resposta).includes(chave);

export const valoresRespondidos = resposta =>
  marcouPreenchidas(resposta) || chavesMarcadas(resposta).length > 0;

// Marcar a primeira opção desmarca os valores.
export const alternarPreenchidas = resposta =>
  marcouPreenchidas(resposta) ? SEM_RESPOSTA : { modo: MODOS.PREENCHIDAS };

// Marcar um valor desmarca a primeira opção.
export const alternarValor = (resposta, chave) => {
  const outras = chavesMarcadas(resposta).filter(marcada => marcada !== chave);
  const chaves = valorMarcado(resposta, chave) ? outras : [...outras, chave];
  return chaves.length ? { modo: MODOS.VALORES, chaves } : SEM_RESPOSTA;
};

// A resposta como vai ao servidor: só o modo e, nos valores, as chaves.
export const corpoDosValores = resposta => {
  if (marcouPreenchidas(resposta)) return { modo: MODOS.PREENCHIDAS };
  const chaves = chavesMarcadas(resposta);
  return chaves.length
    ? { modo: MODOS.VALORES, chaves: [...chaves] }
    : undefined;
};
