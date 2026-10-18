// #1433 (tema 13) — leituras do agente da equipe sobre as caixas da L2 (`canais_ocupados`), sem tela.
// O agente da equipe fica numa caixa que tem agente principal (a porta) atendendo, ou numa caixa atendida
// só por pessoas (sem principal e sem robô, `so_de_pessoas` da L2), e recebe a conversa quando alguém
// passa. Na caixa só de pessoas ele nunca abre conversa sozinho. Caixa com outro robô ou com o principal
// parado não serve.

export const BLOQUEIO = {
  SEM_PRINCIPAL: 'sem_principal',
  PRINCIPAL_PARADO: 'principal_parado',
  OUTRO_ROBO: 'outro_robo',
  // Regra G (#1788): a pessoa não é membro da caixa nem tem inbox_manage (o backend diz, em `alcanca`).
  FORA_DO_ALCANCE: 'fora_do_alcance',
};

// Caixa atendida só por pessoas: sem principal e sem outro robô (o backend diz, em `so_de_pessoas`).
export const soDePessoas = canal => canal?.so_de_pessoas === true;

// O agente nativo que atende primeiro na caixa, ou null (livre ou outro robô).
export const principalDaCaixa = canal =>
  canal?.occupied_by?.kind === 'agent' ? canal.occupied_by : null;

// Por que a caixa não pode receber este agente da equipe, ou null quando pode.
// `comOutroSistema` (#1648, opção B): com a aba "Agente de IA" por caixa ligada na conta, o canal com
// agente de outro sistema atendendo primeiro também aceita (o servidor confere de novo).
export const bloqueioDaCaixa = (
  canal,
  agenteId,
  { comOutroSistema = false } = {}
) => {
  if (canal?.alcanca === false) return BLOQUEIO.FORA_DO_ALCANCE;
  if (soDePessoas(canal)) return null;
  const principal = principalDaCaixa(canal);
  if (canal?.occupied_by?.kind === 'external') {
    return comOutroSistema ? null : BLOQUEIO.OUTRO_ROBO;
  }
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

// #1433 (gaveta "Onde e quando", decisão do Rodrigo de 15/10: "a, para todos os agentes") — quem atende
// primeiro numa caixa também pode receber, quando alguém passar, em OUTRAS caixas. Só quem fala com
// cliente: o interno (Copiloto) e o ajudante não; a Lia (cotação) sim. O servidor confere de novo.
export const recebeEmOutrasCaixas = agente =>
  Boolean(agente) &&
  agente.actuation !== 'internal' &&
  agente.ajudante !== true &&
  !(agente.ajuda || []).length;

// As outras caixas da seção "Também recebe quando alguém passar em": fora as em que ele é o principal e a
// escolhida em "Onde atende" (`fora`). [{ canal, bloqueio }], na ordem da leitura. Onde ele já está na
// equipe continua escolhível mesmo bloqueada, para poder sair, menos na caixa fora do alcance (regra G, #1788):
// ali a pessoa não mexe, e a área fica como está no servidor.
export const outrasCaixasDaEquipe = (
  canais,
  agenteId,
  fora = [],
  opcoes = {}
) =>
  (canais || [])
    .filter(
      canal =>
        !fora.includes(canal.inbox_id) &&
        principalDaCaixa(canal)?.agent_id !== agenteId
    )
    .map(canal => {
      const naEquipe = (canal.areas || []).some(
        area => area.agent_id === agenteId
      );
      const bloqueio = bloqueioDaCaixa(canal, agenteId, opcoes);
      return {
        canal,
        bloqueio:
          naEquipe && bloqueio !== BLOQUEIO.FORA_DO_ALCANCE ? null : bloqueio,
      };
    });
