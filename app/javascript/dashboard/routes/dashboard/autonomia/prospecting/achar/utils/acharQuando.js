// #2692 — "hoje", "ontem" ou "há {n} dias" no cartão de uma busca.
export const quandoDe = (t, diasAtras) => {
  if (!diasAtras) return t('PROSPECTING_ACHAR.COMUM.QUANDO.HOJE');
  if (diasAtras === 1) return t('PROSPECTING_ACHAR.COMUM.QUANDO.ONTEM');
  return t('PROSPECTING_ACHAR.COMUM.QUANDO.DIAS', { n: diasAtras });
};

export const fatoDaBusca = (t, busca) =>
  t('PROSPECTING_ACHAR.PORTA.ULTIMAS.FATO', {
    achadas: busca.achadas,
    noFunil: busca.noFunil,
    quando: quandoDe(t, busca.diasAtras),
  });
