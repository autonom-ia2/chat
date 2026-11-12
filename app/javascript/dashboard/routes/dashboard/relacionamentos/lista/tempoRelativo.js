import { DIA_EM_MS } from '../fonte/grupos';

// #2894 — "Falou há 3 dias" da segunda linha: hoje, ontem, há N dias, há N
// meses. A data vem em segundos (como a API de contatos devolve). Devolve a
// chave do catálogo e, quando tem número, o `count` do plural.
const LINHA = 'RELACIONAMENTOS.LISTA.LINHA';
const DIAS_NO_MES = 30;
const ONTEM = 1;

export const falouHa = (ultimaEmSegundos, agora = Date.now()) => {
  if (ultimaEmSegundos === null || ultimaEmSegundos === undefined) {
    return { chave: `${LINHA}.NUNCA_CONVERSOU` };
  }
  const dias = Math.max(
    Math.floor((agora - ultimaEmSegundos * 1000) / DIA_EM_MS),
    0
  );
  if (dias === 0) return { chave: `${LINHA}.FALOU_HOJE` };
  if (dias === ONTEM) return { chave: `${LINHA}.FALOU_ONTEM` };
  if (dias < DIAS_NO_MES) {
    return { chave: `${LINHA}.FALOU_HA_DIAS`, count: dias };
  }
  return {
    chave: `${LINHA}.FALOU_HA_MESES`,
    count: Math.floor(dias / DIAS_NO_MES),
  };
};
