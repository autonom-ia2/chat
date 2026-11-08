// #2500 F7 — o custo da IA em dólar. Fica na casa de US$ 0,0001: dois
// algarismos significativos, e abaixo do mínimo "menos de", nunca "US$ 0".
export const MENOR_CUSTO = 0.0001;

// O vue-i18n usa pt_BR; o Intl só aceita a etiqueta BCP 47 (pt-BR).
export const dolares = (valor, locale) =>
  new Intl.NumberFormat(locale.replace('_', '-'), {
    maximumSignificantDigits: 2,
  }).format(Math.max(valor, MENOR_CUSTO));

export const abaixoDoMinimo = valor => valor < MENOR_CUSTO;

// "US$ 0,0021" ou "menos de US$ 0,0001", para entrar numa frase com {custo}.
export const custoEmTexto = (valor, t, locale) =>
  t(
    abaixoDoMinimo(valor)
      ? 'AUTOMACAO_LIVRE.IA.CUSTO.VALOR_MENOS_DE'
      : 'AUTOMACAO_LIVRE.IA.CUSTO.VALOR',
    { valor: dolares(valor, locale) }
  );
