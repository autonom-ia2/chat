// #1433 (tema 13) — leituras do agente da equipe sobre as caixas da L2 (`canais_ocupados`), sem tela.
// O agente da equipe fica numa caixa ATIVA que já tem agente principal (a porta) e recebe a conversa
// quando alguém passa. Caixa sem principal, com outro robô ou com o principal parado não serve.

export const BLOQUEIO = {
  SEM_PRINCIPAL: 'sem_principal',
  PRINCIPAL_PARADO: 'principal_parado',
};

// O agente nativo que atende primeiro na caixa, ou null (livre ou outro robô).
export const principalDaCaixa = canal =>
  canal?.occupied_by?.kind === 'agent' ? canal.occupied_by : null;

// Por que a caixa não pode receber este agente da equipe, ou null quando pode.
export const bloqueioDaCaixa = (canal, agenteId) => {
  const principal = principalDaCaixa(canal);
  if (!principal || principal.agent_id === agenteId) {
    return BLOQUEIO.SEM_PRINCIPAL;
  }
  return principal.operating ? null : BLOQUEIO.PRINCIPAL_PARADO;
};

// Caixas em que o agente está na equipe agora.
export const caixasDaEquipe = (agenteId, canais) =>
  (canais || []).filter(canal =>
    (canal.areas || []).some(area => area.agent_id === agenteId)
  );

// A caixa da store (ícone do canal, número do WhatsApp) pelo id da L2.
export const caixaPeloId = (caixas, id) =>
  (caixas || []).find(caixa => caixa.id === id) || null;

// O que identifica o canal para quem lê: o número do WhatsApp; nos outros, o nome já basta.
export const enderecoDaCaixa = caixa =>
  caixa?.channel_type === 'Channel::Whatsapp' ? caixa.phone_number || '' : '';

// O que muda ao salvar a escolha: caixas que entram e que saem.
export const mudancaDaEquipe = (antes, depois) => ({
  entram: depois.filter(id => !antes.includes(id)),
  saem: antes.filter(id => !depois.includes(id)),
});
