// #2894 — números "aleatórios" que são sempre os mesmos: a demonstração mostra a
// mesma lista a cada carga. (Gerador de Park–Miller: pequeno, sem dependência e
// sem operação de bits; o produto cabe nos 53 bits de um número do JavaScript.)
const MODULO = 2_147_483_647;
const MULTIPLICADOR = 48_271;

export const sorteioFixo = semente => {
  let estado = (Math.abs(Math.trunc(semente)) % (MODULO - 1)) + 1;
  return () => {
    estado = (estado * MULTIPLICADOR) % MODULO;
    return (estado - 1) / (MODULO - 1);
  };
};

// 0..n-1 embaralhados com a semente dada (Fisher–Yates, sem alterar a lista).
export const embaralhadoFixo = (n, semente) => {
  const sorteio = sorteioFixo(semente);
  const ordem = Array.from({ length: n }, (_, i) => i);
  return ordem.reduceRight((lista, _, i) => {
    const j = Math.floor(sorteio() * (i + 1));
    return lista.map((valor, k) => {
      if (k === i) return lista[j];
      return k === j ? lista[i] : valor;
    });
  }, ordem);
};
