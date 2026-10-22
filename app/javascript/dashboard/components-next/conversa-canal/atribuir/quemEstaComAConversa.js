// #2067: com quem a conversa está, do ponto de vista de quem escreve. Decide se o ícone
// "ficar com a conversa ao enviar" aparece e se vem ligado.
export const QUEM_ESTA = {
  MINHA: 'minha',
  NINGUEM: 'ninguem',
  IA: 'ia',
  COLEGA: 'colega',
};

// IA e robô são a mesma coisa na regra: todo dono que não é pessoa (AgentBot, assistente),
// inclusive a Lia (Agente de Cotação), que atende pelo robô espelho dela.
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

// O dono que a tela viu, como vai no envio (`ficar_com_a_conversa_de`): o servidor só
// atribui se, na hora de gravar, o dono ainda é esse (Conversations::FicarAoEnviar).
export const donoVisto = conversa => {
  const quem = quemEstaComAConversa(conversa, null);
  if (quem === QUEM_ESTA.NINGUEM) return { tipo: 'ninguem' };
  if (quem === QUEM_ESTA.IA) return { tipo: 'ia' };
  return { tipo: 'pessoa', id: conversa.meta.assignee.id };
};

// Identifica o dono para a escolha guardada: mudou o dono, a escolha volta ao padrão. IA e
// ninguém são a mesma situação ('livre'), como no servidor (Conversations::FicarAoEnviar::
// LIVRES): a IA que passa a conversa a ninguém não apaga a escolha de quem escreve.
export const chaveDoVisto = visto =>
  visto?.tipo === 'pessoa' ? `pessoa:${visto.id}` : 'livre';

export const chaveDoDono = conversa => chaveDoVisto(donoVisto(conversa));

// #2067: o evento ao vivo da conversa não traz `veio_da_ia` (só a troca de dono traz, e as
// leituras). Enquanto o dono é o mesmo, a tela guarda o que já sabia; trocou o dono sem
// dizer de onde veio, esquece.
export const veioDaIaPreservado = (antes, depois) => {
  if (!depois || 'veio_da_ia' in depois || !antes?.veio_da_ia) return depois;
  const mesmoDono =
    antes.assignee_type === depois.assignee_type &&
    antes.assignee?.id === depois.assignee?.id;
  return mesmoDono ? { ...depois, veio_da_ia: antes.veio_da_ia } : depois;
};
