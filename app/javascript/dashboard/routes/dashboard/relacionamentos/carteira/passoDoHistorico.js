// #2898 — a frase de um passo do histórico do seguro. Função pura: devolve a
// chave do catálogo (dentro de RELACIONAMENTOS_CARTEIRA.HISTORIA) e, quando o
// passo traz um detalhe, qual é. Três passos da renovação têm detalhe: o motivo
// de um toque, o motivo escrito e o número da apólice anterior. Sem o detalhe,
// vale a frase curta do passo ("Não renovou."), nunca uma frase com buraco.
export const DETALHES = {
  MOTIVO: 'motivo',
  TEXTO: 'texto',
  ANTERIOR: 'anterior',
};

const DETALHE_DO_TIPO = {
  nao_renovou: DETALHES.MOTIVO,
  nao_renovou_outro: DETALHES.TEXTO,
  apolice_nova: DETALHES.ANTERIOR,
};

export const fraseDoPasso = ({ tipo, valores }) => {
  const nome = String(tipo).toUpperCase();
  const detalhe = DETALHE_DO_TIPO[tipo];
  const valor = detalhe ? valores?.[detalhe] : null;
  return valor
    ? { chave: `TIPOS_COM.${nome}`, detalhe, valor }
    : { chave: `TIPOS.${nome}`, detalhe: null, valor: null };
};
