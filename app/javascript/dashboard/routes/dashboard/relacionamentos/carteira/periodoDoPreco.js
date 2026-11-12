// #2897 — de quanto em quanto tempo o preço é cobrado: por ano (o de sempre) ou
// por mês (seguro por assinatura). Função pura: devolve o nome da frase do
// catálogo (`PERIODO.ANO` ou `PERIODO.MES`); sem o dado, vale por ano.
export const PERIODOS = { ANO: 'ano', MES: 'mes' };

export const periodoDoPreco = preco =>
  preco?.periodo === PERIODOS.MES ? 'MES' : 'ANO';
