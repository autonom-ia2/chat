// #2894 — o e-mail só pode quebrar de linha no "@": duas partes, que a tela
// separa com <wbr>. Sem "@" (linha com problema), vem inteiro. Sem regex.
export const partesDoEmail = email => {
  const texto = String(email ?? '');
  const arroba = texto.indexOf('@');
  return arroba > 0 ? [texto.slice(0, arroba), texto.slice(arroba)] : [texto];
};
