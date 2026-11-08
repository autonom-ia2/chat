import { autorDaBusca } from './acharPapeis';

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

// O título do cartão: "Escritórios · Pinheiros" (o separador vem do i18n).
export const tituloDaBusca = (t, busca) =>
  t('PROSPECTING_ACHAR.CONFIRA.TITULO', {
    oQue: busca.oQue,
    lugar: busca.lugar,
  });

// "Feita por você" / "Feita por Lucas"; vazio na busca antiga sem dono.
export const feitaPorDaBusca = (t, busca, usuarioId) => {
  const autor = autorDaBusca(busca, usuarioId);
  if (!autor) return '';
  return t('PROSPECTING_ACHAR.BUSCAS.FEITA_POR', {
    pessoa: autor === 'voce' ? t('PROSPECTING_ACHAR.COMUM.VOCE') : autor,
  });
};

// "07/11" (ou "11/07" em inglês): o dia e o mês na língua do painel. A língua
// do i18n usa "_" (pt_BR); a etiqueta do navegador usa "-" (pt-BR).
export const diaEMes = (data, lingua) =>
  data.toLocaleDateString(lingua.replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
  });
