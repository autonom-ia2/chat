// Filtro "Funil" da lista de conversas (multifunil #1150): a escolha fica guardada por conta e por pessoa no
// navegador e vale para todas as listas (Todas, Menções, Em que participo, Caixa). localStorage pode não existir ou
// recusar (janela privada, cota cheia): nesse caso o filtro só não é lembrado.
export const FUNNEL_ALL = '';
export const FUNNEL_NONE = 'none';
// Até 4 funis, botões lado a lado; mais que isso, campo de escolha (decisão do Rodrigo, 15/10).
export const MAX_FUNNEL_BUTTONS = 4;

export const funnelChoiceKey = (accountId, userId) =>
  `crm_filtro_funil:${accountId}:${userId}`;

export const readFunnelChoice = (accountId, userId) => {
  try {
    return (
      window.localStorage.getItem(funnelChoiceKey(accountId, userId)) ||
      FUNNEL_ALL
    );
  } catch {
    return FUNNEL_ALL;
  }
};

export const writeFunnelChoice = (accountId, userId, value) => {
  try {
    const key = funnelChoiceKey(accountId, userId);
    if (value) {
      window.localStorage.setItem(key, value);
    } else {
      window.localStorage.removeItem(key);
    }
  } catch {
    // Sem armazenamento a escolha vale só nesta tela; nada a avisar.
  }
};

// O funil guardado deixou de ser visível (acesso mudou, funil arquivado): volta para "Sem filtro de funil".
export const visibleFunnelChoice = (value, pipelineIds) => {
  if (value === FUNNEL_ALL || value === FUNNEL_NONE) return value;
  return pipelineIds.map(String).includes(String(value)) ? value : FUNNEL_ALL;
};
