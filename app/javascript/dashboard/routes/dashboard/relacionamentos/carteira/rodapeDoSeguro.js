// #2897 — o que vai no rodapé da gaveta do seguro e o que vai no "⋯" (molde:
// passoDoSeguro.js). Função pura: devolve os nomes; quem desenha traduz. O
// rodapé tem sempre três peças: o botão azul do passo, um botão secundário e o
// "⋯", que anda junto do secundário (nunca sozinho numa linha). Quando o passo
// traz dois botões (o azul e o que ele tirou do lugar), o secundário é o do
// passo e "Corrigir", o menos urgente, entra no "⋯"; sem isso, "Corrigir" é o
// secundário.
export const DO_RODAPE = {
  CORRIGIR: 'CORRIGIR',
  ANEXAR_OUTRO_PDF: 'ANEXAR_OUTRO_PDF',
  MARCAR_CANCELADO: 'MARCAR_CANCELADO',
  VOLTAR_A_ATIVO: 'VOLTAR_A_ATIVO',
};

// `passo`: { azul, depois } (carteira/passoDoSeguro.js).
export const rodapeDoSeguro = (passo, { cancelado = false } = {}) => {
  const sempreNoMenu = [
    DO_RODAPE.ANEXAR_OUTRO_PDF,
    cancelado ? DO_RODAPE.VOLTAR_A_ATIVO : DO_RODAPE.MARCAR_CANCELADO,
  ];
  return passo.depois
    ? {
        azul: passo.azul,
        secundario: passo.depois,
        menu: [DO_RODAPE.CORRIGIR, ...sempreNoMenu],
      }
    : { azul: passo.azul, secundario: DO_RODAPE.CORRIGIR, menu: sempreNoMenu };
};
