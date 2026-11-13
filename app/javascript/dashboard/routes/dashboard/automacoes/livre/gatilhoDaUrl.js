// #2414 F6.3/F6.5 — "Nova automação para esta etapa" abre o editor com o
// gatilho já escolhido: ?gatilho=card.entrou_na_etapa&etapa=<id>. Só os
// gatilhos de etapa, e só se esta pessoa pode escolhê-lo (flag e chave de
// funis, os mesmos de useGatilhosNovos); senão, o editor abre como sempre.
const DE_ETAPA = ['card.entrou_na_etapa', 'card.saiu_da_etapa'];

export const gatilhoDaUrl = (query, oferecidos) => {
  const tipo = String(query?.gatilho || '');
  const etapaId = Number(query?.etapa);
  if (!DE_ETAPA.includes(tipo)) return null;
  if (!Number.isInteger(etapaId) || etapaId <= 0) return null;
  if (!oferecidos.some(item => item.tipo === tipo)) return null;
  return { tipo, etapa_id: etapaId };
};
