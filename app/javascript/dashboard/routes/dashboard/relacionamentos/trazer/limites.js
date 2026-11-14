// #2896 — até onde o servidor aceita cada texto de "Trazer minha lista". Os
// campos já param aqui (`maxlength`); se passar mesmo assim, o servidor recusa
// com o motivo `muito_longo`.
export const LIMITES = {
  // O valor que conserta uma linha (o e-mail ou o nome certo).
  VALOR: 255,
  // A informação nova: o nome do campo e o "Para que serve?".
  NOME_DO_CAMPO: 255,
  PARA_QUE_SERVE: 1000,
};
