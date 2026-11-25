import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { ehContratado } from './pagina';

// #1181 — leitura das caixas da L2 para a escolha de onde atender.
// Uma caixa pode estar livre (occupied_by null), com um agente nativo ({kind:'agent'}) ou com outro
// sistema ({kind:'external'}, ex.: bot de webhook). A caixa que já é deste agente conta como livre.
export const TIPO_CANAL = {
  LIVRE: 'livre',
  OCUPADO: 'ocupado',
  EXTERNO: 'externo',
};

export const tipoDoCanal = (canal, agenteId) => {
  const dono = canal?.occupied_by;
  if (!dono) return TIPO_CANAL.LIVRE;
  if (dono.kind === 'external') return TIPO_CANAL.EXTERNO;
  if (dono.agent_id === agenteId) return TIPO_CANAL.LIVRE;
  return TIPO_CANAL.OCUPADO;
};

// O que o useComecarAAtender precisa para trocar quem está na caixa escolhida, ou null.
export const trocaNoCanal = (canais, inboxId, agenteId) => {
  const canal = (canais || []).find(item => item.inbox_id === inboxId);
  if (tipoDoCanal(canal, agenteId) !== TIPO_CANAL.OCUPADO) return null;
  return {
    agenteId: canal.occupied_by.agent_id,
    nome: canal.occupied_by.agent_name,
    canal: canal.name,
    // #1366: sair da última caixa para o antigo (a tela avisa); se a troca falhar, ele volta ligado só se atendia.
    atendia: canal.occupied_by.operating === true,
    ultimaCaixa: canal.occupied_by.caixas === 1,
  };
};

// #3211 (nota 5 do mockup) — a caixa que já vem marcada para o agente contratado que começa a atender sem canal
// nenhum (o passo 3 dele): a única livre da conta, com a leitura das caixas pronta e completa (sem a L2, as ocupadas
// não aparecem e toda caixa parece livre). Com nenhuma ou mais de uma livre, a pessoa escolhe. Os outros agentes
// seguem como sempre: nada vem marcado. O primeiro argumento são as props da gaveta de onde e quando.
export const unicaCaixaLivre = (
  { canais, atuais, agente, estadoCanais, semLeitura },
  { comecando = false } = {}
) => {
  if (!ehContratado(agente)) return null;
  if (!comecando || estadoCanais !== 'pronto' || semLeitura) return null;
  if ((atuais || []).length || agente?.channels_count) return null;
  const livres = (canais || []).filter(canal => !canal.occupied_by);
  return livres.length === 1 ? livres[0].inbox_id : null;
};

// #1369 — o tipo de cada caixa na lista de onde atende ("HUBBER COMUNIDADE · WhatsApp"), pelo
// `channel_type` da própria caixa (AGENTS.JORNADA.ONDE_QUANDO.TIPO.<chave>). Tipo sem nome claro para
// quem lê (Twilio, que pode ser SMS ou WhatsApp; X) fica sem etiqueta.
const TIPO_DA_CAIXA = {
  [INBOX_TYPES.WHATSAPP]: 'WHATSAPP',
  [INBOX_TYPES.INSTAGRAM]: 'INSTAGRAM',
  [INBOX_TYPES.WEB]: 'SITE',
  [INBOX_TYPES.EMAIL]: 'EMAIL',
  [INBOX_TYPES.API]: 'API',
  [INBOX_TYPES.FB]: 'FACEBOOK',
  [INBOX_TYPES.TELEGRAM]: 'TELEGRAM',
  [INBOX_TYPES.SMS]: 'SMS',
  [INBOX_TYPES.LINE]: 'LINE',
  [INBOX_TYPES.TIKTOK]: 'TIKTOK',
};

export const chaveDoTipoDaCaixa = canal =>
  TIPO_DA_CAIXA[canal?.channel_type] || null;
