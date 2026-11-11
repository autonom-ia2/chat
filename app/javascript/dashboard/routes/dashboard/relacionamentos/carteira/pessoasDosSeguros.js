// #2897 — as pessoas de uma lista de seguros, cada uma uma vez só, na ordem em
// que apareceram: a mensagem vai por pessoa, não por seguro.
export const pessoasDosSeguros = (seguros = []) => [
  ...new Map(seguros.map(({ pessoa }) => [pessoa.id, pessoa])).values(),
];
