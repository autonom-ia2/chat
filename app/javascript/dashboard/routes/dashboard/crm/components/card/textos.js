// #1423 — textos de um componente reaproveitado com palavras da gaveta nova.
// `proprio` é o prefixo de i18n com as frases simples (só as que mudam); o que
// não estiver lá usa o texto de sempre (`padrao`). Sem `proprio`, nada muda.
export const textosCom =
  ({ t, te }, proprio, padrao) =>
  (chave, valores) => {
    const nossa = proprio ? `${proprio}.${chave}` : '';
    return t(nossa && te(nossa) ? nossa : `${padrao}.${chave}`, valores);
  };
