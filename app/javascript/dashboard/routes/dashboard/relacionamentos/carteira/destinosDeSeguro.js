// #2897 — para onde as colunas de seguro de uma planilha podem ir, além dos
// destinos do bloco A (trazer/destinos.js). O nome na tela vem do catálogo de
// seguros.
export const DESTINOS_DE_SEGURO = {
  DOCUMENTO: 'documento',
  NUMERO: 'seguro_numero',
  TIPO: 'seguro_tipo',
  SEGURADORA: 'seguro_seguradora',
  COMECA: 'seguro_comeca',
  TERMINA: 'seguro_termina',
  VALOR: 'seguro_valor',
  BEM: 'seguro_bem',
};

const CAMPOS = 'RELACIONAMENTOS_CARTEIRA.PDF.CAMPOS';

export const CHAVES_DOS_DESTINOS_DE_SEGURO = {
  [DESTINOS_DE_SEGURO.DOCUMENTO]:
    'RELACIONAMENTOS_CARTEIRA.TRAZER.DESTINO_DOCUMENTO',
  [DESTINOS_DE_SEGURO.NUMERO]: `${CAMPOS}.NUMERO`,
  [DESTINOS_DE_SEGURO.TIPO]: `${CAMPOS}.TIPO`,
  [DESTINOS_DE_SEGURO.SEGURADORA]: `${CAMPOS}.SEGURADORA`,
  [DESTINOS_DE_SEGURO.COMECA]: `${CAMPOS}.COMECA`,
  [DESTINOS_DE_SEGURO.TERMINA]: `${CAMPOS}.TERMINA`,
  [DESTINOS_DE_SEGURO.VALOR]: `${CAMPOS}.VALOR`,
  [DESTINOS_DE_SEGURO.BEM]: `${CAMPOS}.BEM`,
};
