// #2067: com quem a conversa está, do ponto de vista de quem escreve. Decide se o ícone
// "ficar com a conversa ao enviar" aparece e se vem ligado.
export const QUEM_ESTA = {
  MINHA: 'minha',
  NINGUEM: 'ninguem',
  IA: 'ia',
  COLEGA: 'colega',
};

// IA e robô são a mesma coisa na regra: todo dono que não é pessoa (AgentBot, assistente).
export const quemEstaComAConversa = (conversa, meuId) => {
  const dono = conversa?.meta?.assignee;
  if (!dono) return QUEM_ESTA.NINGUEM;
  if ((conversa.meta.assignee_type || 'User') !== 'User') return QUEM_ESTA.IA;
  return dono.id === meuId ? QUEM_ESTA.MINHA : QUEM_ESTA.COLEGA;
};

// Ligado quando ninguém atende ou quando é a IA; desligado quando é de outra pessoa
// (ninguém toma cliente de colega sem querer).
export const ficarVemLigada = quem =>
  quem === QUEM_ESTA.NINGUEM || quem === QUEM_ESTA.IA;
