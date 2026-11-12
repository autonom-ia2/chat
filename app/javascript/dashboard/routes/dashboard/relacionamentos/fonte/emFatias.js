// #2894 — manda as pessoas de uma ação em grupo em fatias, uma depois da outra.
//
// A fatia é TRANSPORTE, não limite: a pessoa pode marcar quantas quiser (regra
// do produto: nenhum freio no uso). O servidor leva cerca de 20 ms por pessoa
// (até uns 85 ms ao apagar) e corta o pedido em 15 s; com 50 por pedido cada
// fatia cabe com folga. Em sequência, e não ao mesmo tempo, para não disputar
// o servidor com o resto da equipe.
export const PESSOAS_POR_FATIA = 50;

const NADA_FEITO = {
  feitas: 0,
  deFora: [],
  tentadas: 0,
  parou: false,
  erro: null,
};

const emFatiasDe = (lista, tamanho) =>
  Array.from({ length: Math.ceil(lista.length / tamanho) }, (_, indice) =>
    lista.slice(indice * tamanho, (indice + 1) * tamanho)
  );

// `mandar(fatia)` faz a ação com aquelas pessoas e devolve { feitas, deFora }.
// `aoAndar({ feitas, total })` avisa a cada fatia que voltou. `deveParar()` é
// perguntado antes de cada fatia (a pessoa fechou o diálogo).
//
// Devolve sempre o que aconteceu de verdade:
//   { [contagem]: quantas deram certo, deFora, faltam, erro }
// Se uma fatia falha (rede, 500, 422), para ali: `faltam` são as pessoas que
// ninguém tentou (a fatia que falhou e as seguintes) e `erro` é a falha. Com
// tudo tentado, `faltam` vem vazio e `erro`, null.
export const emFatias = async ({
  pessoas,
  contagem,
  mandar,
  aoAndar = () => {},
  deveParar = () => false,
}) => {
  const total = pessoas.length;

  const proxima = async (antes, fatia) => {
    if (antes.parou || deveParar()) return { ...antes, parou: true };
    let resposta;
    try {
      resposta = await mandar(fatia);
    } catch (erro) {
      return { ...antes, parou: true, erro };
    }
    const tentadas = antes.tentadas + fatia.length;
    aoAndar({ feitas: tentadas, total });
    return {
      ...antes,
      feitas: antes.feitas + resposta.feitas,
      deFora: [...antes.deFora, ...resposta.deFora],
      tentadas,
    };
  };

  const fim = await emFatiasDe(pessoas, PESSOAS_POR_FATIA).reduce(
    (cadeia, fatia) => cadeia.then(antes => proxima(antes, fatia)),
    Promise.resolve(NADA_FEITO)
  );

  return {
    [contagem]: fim.feitas,
    deFora: fim.deFora,
    faltam: pessoas.slice(fim.tentadas),
    erro: fim.erro,
  };
};
