// #3158 (B8a) — onde cada gráfico do relatório entra na resposta do Guia.
//
// O modelo escreve o marcador `[grafico:<id>]` onde o gráfico deve aparecer;
// os números vêm da ferramenta, junto da resposta (`graficos`). Aqui a resposta
// vira uma lista de pedaços de texto e de gráfico, na ordem.
//
// O gráfico nunca some: se o modelo esqueceu ou mudou o marcador, ele vai para
// o fim. Só é marcador o trecho exato `[grafico:<dígitos>]`: o que não fecha ou
// traz outra coisa dentro fica no texto como veio. Marcador de dígitos sem
// gráfico (ou repetido) sai do texto, para a pessoa não ver o código. Sem
// regex: só `indexOf` e `slice`.
const ABRE = '[grafico:';
const FECHA = ']';

const soDigitos = texto =>
  texto.length > 0 &&
  [...texto].every(caractere => caractere >= '0' && caractere <= '9');

const comTexto = (pedacos, texto) => {
  const limpo = texto.trim();
  return limpo ? [...pedacos, { tipo: 'texto', texto: limpo }] : pedacos;
};

// -> [{ tipo: 'texto', texto } | { tipo: 'grafico', grafico }]
export const pedacosDaResposta = (texto, graficos) => {
  const lista = (Array.isArray(graficos) ? graficos : []).filter(Boolean);
  const porId = new Map(lista.map(grafico => [String(grafico.id), grafico]));
  const usados = new Set();
  const resposta = String(texto || '');
  let pedacos = [];
  let antes = '';
  let cursor = 0;
  let inicio = resposta.indexOf(ABRE);
  while (inicio >= 0) {
    const fim = resposta.indexOf(FECHA, inicio + ABRE.length);
    const id = fim < 0 ? '' : resposta.slice(inicio + ABRE.length, fim);
    if (!soDigitos(id)) {
      // Não é marcador: o texto fica, e a busca segue logo depois do "[grafico:".
      antes += resposta.slice(cursor, inicio + ABRE.length);
      cursor = inicio + ABRE.length;
    } else {
      antes += resposta.slice(cursor, inicio);
      if (porId.has(id) && !usados.has(id)) {
        pedacos = [
          ...comTexto(pedacos, antes),
          { tipo: 'grafico', grafico: porId.get(id) },
        ];
        usados.add(id);
        antes = '';
      }
      cursor = fim + FECHA.length;
    }
    inicio = resposta.indexOf(ABRE, cursor);
  }
  pedacos = comTexto(pedacos, antes + resposta.slice(cursor));
  const semMarcador = lista.filter(grafico => !usados.has(String(grafico.id)));
  return [
    ...pedacos,
    ...semMarcador.map(grafico => ({ tipo: 'grafico', grafico })),
  ];
};
