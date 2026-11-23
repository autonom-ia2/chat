// #3158 (B8a) — onde cada gráfico do relatório entra na resposta do Guia.
//
// O modelo escreve o marcador `[grafico:<id>]` onde o gráfico deve aparecer;
// os números vêm da ferramenta, junto da resposta (`graficos`). Aqui a resposta
// vira uma lista de pedaços de texto e de gráfico, na ordem.
//
// O gráfico nunca some: se o modelo esqueceu ou mudou o marcador, ele vai para
// o fim. Marcador sem gráfico (ou repetido) sai do texto, para a pessoa não ver
// o código. Sem regex: só `indexOf` e `slice`.
const ABRE = '[grafico:';
const FECHA = ']';

const comTexto = (pedacos, texto) => {
  const limpo = texto.trim();
  return limpo ? [...pedacos, { tipo: 'texto', texto: limpo }] : pedacos;
};

// -> [{ tipo: 'texto', texto } | { tipo: 'grafico', grafico }]
export const pedacosDaResposta = (texto, graficos) => {
  const lista = (Array.isArray(graficos) ? graficos : []).filter(Boolean);
  const porId = new Map(lista.map(grafico => [String(grafico.id), grafico]));
  const usados = new Set();
  let pedacos = [];
  let antes = '';
  let resto = String(texto || '');
  let inicio = resto.indexOf(ABRE);
  while (inicio >= 0) {
    const fim = resto.indexOf(FECHA, inicio + ABRE.length);
    if (fim < 0) break;
    antes += resto.slice(0, inicio);
    const id = resto.slice(inicio + ABRE.length, fim).trim();
    if (porId.has(id) && !usados.has(id)) {
      pedacos = [
        ...comTexto(pedacos, antes),
        { tipo: 'grafico', grafico: porId.get(id) },
      ];
      usados.add(id);
      antes = '';
    }
    resto = resto.slice(fim + FECHA.length);
    inicio = resto.indexOf(ABRE);
  }
  pedacos = comTexto(pedacos, antes + resto);
  const semMarcador = lista.filter(grafico => !usados.has(String(grafico.id)));
  return [
    ...pedacos,
    ...semMarcador.map(grafico => ({ tipo: 'grafico', grafico })),
  ];
};
