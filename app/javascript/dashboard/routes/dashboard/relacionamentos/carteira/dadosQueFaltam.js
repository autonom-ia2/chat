// #2897 — os dados que faltam para cotar, quando quem preenche é a pessoa da
// corretora: um campo por dado. Funções puras: nada do que chega é alterado.
const escrito = (escritos, dado) => String(escritos?.[dado] ?? '').trim();

// O primeiro dado ainda vazio, na ordem da lista (`null` = todos escritos).
export const primeiroDadoQueFalta = (faltou = [], escritos = {}) =>
  faltou.find(dado => !escrito(escritos, dado)) ?? null;

// Só os dados que faltavam, sem espaço sobrando.
export const dadosEscritos = (faltou = [], escritos = {}) =>
  Object.fromEntries(faltou.map(dado => [dado, escrito(escritos, dado)]));
