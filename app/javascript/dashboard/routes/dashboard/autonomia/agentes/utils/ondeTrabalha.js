// #1433 (tema 13) — leituras do agente da equipe sobre as caixas da L2 (`canais_ocupados`), sem tela.
// O agente da equipe fica numa caixa que tem agente principal (a porta) atendendo, ou numa caixa atendida
// só por pessoas (sem principal e sem robô, `so_de_pessoas` da L2), e recebe a conversa quando alguém
// passa. Na caixa só de pessoas ele nunca abre conversa sozinho. Caixa com outro robô ou com o principal
// parado não serve.

export const BLOQUEIO = {
  SEM_PRINCIPAL: 'sem_principal',
  PRINCIPAL_PARADO: 'principal_parado',
  OUTRO_ROBO: 'outro_robo',
};

// Caixa atendida só por pessoas: sem principal e sem outro robô (o backend diz, em `so_de_pessoas`).
export const soDePessoas = canal => canal?.so_de_pessoas === true;

// O agente nativo que atende primeiro na caixa, ou null (livre ou outro robô).
export const principalDaCaixa = canal =>
  canal?.occupied_by?.kind === 'agent' ? canal.occupied_by : null;

// Por que a caixa não pode receber este agente da equipe, ou null quando pode.
export const bloqueioDaCaixa = (canal, agenteId) => {
  if (soDePessoas(canal)) return null;
  const principal = principalDaCaixa(canal);
  if (canal?.occupied_by?.kind === 'external') return BLOQUEIO.OUTRO_ROBO;
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
