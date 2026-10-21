// #2067: com quem a conversa está, do ponto de vista de quem escreve. Decide se a opção
// "ficar com a conversa ao enviar" aparece e se vem ligada.
export const QUEM_ESTA = {
  MINHA: 'minha',
  NINGUEM: 'ninguem',
  IA: 'ia',
  COLEGA: 'colega',
};

export const quemEstaComAConversa = (conversa, meuId) => {
  const dono = conversa?.meta?.assignee;
  if (!dono) return QUEM_ESTA.NINGUEM;
  if (conversa.meta.assignee_type === 'AgentBot') return QUEM_ESTA.IA;
  return dono.id === meuId ? QUEM_ESTA.MINHA : QUEM_ESTA.COLEGA;
};

// Ligada quando ninguém atende ou quando é a IA; desligada quando é de outra pessoa
// (ninguém toma cliente de colega sem querer).
export const ficarVemLigada = quem =>
  quem === QUEM_ESTA.NINGUEM || quem === QUEM_ESTA.IA;
