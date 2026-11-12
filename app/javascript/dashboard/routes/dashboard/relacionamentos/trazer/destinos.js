// #2894 — para onde cada coluna da planilha pode ir, em palavras simples. O
// nome na tela vem do catálogo: RELACIONAMENTOS_TRAZER.DESTINOS.<id>.
export const DESTINOS = {
  NOME: 'nome',
  TELEFONE: 'telefone',
  TELEFONE_DA_EMPRESA: 'telefone_da_empresa',
  EMAIL: 'email',
  EMPRESA: 'empresa',
  CIDADE: 'cidade',
  CLIENTE: 'cliente',
  INFORMACAO: 'informacao',
  NAO_GUARDAR: 'nao_guardar',
};

export const LISTA_DE_DESTINOS = Object.values(DESTINOS);

// Coluna que o sistema não conhecia: vira "informação da pessoa" com o nome dela.
export const ehInformacaoNova = coluna =>
  coluna.destino === DESTINOS.INFORMACAO;
