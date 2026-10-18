// Etiquetas de dia presas no topo (#1702): a de cima some quando a do dia seguinte a
// alcança, como no WhatsApp. Funções puras para o SeparadorDeDia.vue.
const SEPARADOR = 'data-separador-de-dia';

// A próxima etiqueta de dia na mesma lista (irmã mais abaixo), ou null.
export const proximoSeparador = elemento => {
  let irmao = elemento.nextElementSibling;
  while (irmao && !irmao.hasAttribute(SEPARADOR))
    irmao = irmao.nextElementSibling;
  return irmao;
};

// Coberta: a etiqueta seguinte já encostou nesta (as duas presas no topo, ou a de
// baixo chegando). Sem etiqueta seguinte, fica à mostra.
export const coberta = (elemento, proximo) => {
  if (!proximo) return false;
  return (
    proximo.getBoundingClientRect().top <=
    elemento.getBoundingClientRect().bottom
  );
};
