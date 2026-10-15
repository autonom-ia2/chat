import { telefoneLegivel } from 'dashboard/components-next/NovaConversa/novaConversa';

// chat#1477 — por que a conexão do WhatsApp API parou, para a tela dizer a coisa certa.
// `phone` só existe quando a sessão chegou a conectar, e é apagado ao pedir um novo QR Code:
// falha com número = o WhatsApp desconectou o aparelho; falha sem número = o QR venceu.
export const stoppedKeyFor = ({ status, phone } = {}) => {
  if (status === 'disconnected') return 'DISCONNECTED';
  if (status === 'failed' && phone) return 'REMOVED';
  return 'EXPIRED';
};

// chat#1480 — até quando o WhatsApp limitou as conversas novas deste número.
// Devolve a data do fim, `true` quando o limite está ativo sem prazo informado, ou null sem limite.
export const timelockEndFor = ({ timelock } = {}, now = Date.now()) => {
  if (!timelock?.active) return null;
  if (!timelock.ends_at) return true;
  const end = new Date(timelock.ends_at * 1000);
  return end.getTime() > now ? end : null;
};

// chat#1487 — o selo de estado da aba. Pausado vem antes do estado do motor: a sessão parada de propósito
// não é "desconectado".
export const statusKeyFor = (data = {}) => {
  if (data.status === 'not_connected') return 'NOT_CONNECTED';
  if (data.paused) return 'PAUSED';
  if (data.connected) return 'CONNECTED';
  // QR vencido (falhou sem nunca ter conectado): o selo diz o mesmo que o título, "expirado".
  if (data.status === 'failed') return data.phone ? 'REMOVED' : 'EXPIRED';
  if (data.status === 'disconnected') return 'DISCONNECTED';
  return 'AWAITING';
};

// chat#1487 — o que a caixa de situação da aba mostra (uma ação principal por estado).
export const phaseFor = (data = {}) => {
  const { status } = data;
  if (['loading', 'unavailable', 'not_connected'].includes(status)) {
    return status;
  }
  if (data.paused) return 'paused';
  if (data.connected) return data.same_number ? 'connected' : 'wrong_number';
  if (['failed', 'disconnected'].includes(status)) return 'stopped';
  return 'pairing';
};

// Selo do estado, sobre o herói azul-marinho (igual nos dois temas): fundo branco e texto azul-marinho, com o ícone
// na cor do estado (verde pronto, âmbar esperando, vermelho com problema, cinza parado). Cores fixas, como o fundo do
// herói, para o contraste AA não depender do tema.
export const STATUS_VISUALS = {
  NOT_CONNECTED: { icon: 'i-lucide-circle-dashed', tone: 'text-[#475569]' },
  AWAITING: { icon: 'i-lucide-clock-3', tone: 'text-[#B45309]' },
  CONNECTED: { icon: 'i-lucide-circle-check', tone: 'text-[#0F766E]' },
  PAUSED: { icon: 'i-lucide-circle-pause', tone: 'text-[#475569]' },
  DISCONNECTED: { icon: 'i-lucide-unplug', tone: 'text-[#475569]' },
  EXPIRED: { icon: 'i-lucide-timer-off', tone: 'text-[#475569]' },
  REMOVED: { icon: 'i-lucide-circle-alert', tone: 'text-[#BE123C]' },
};

// Fundo da caixa de situação, como a caixa de situação do modelo.
export const PHASE_TONES = {
  connected: 'bg-n-teal-2 ring-n-teal-6',
  paused: 'bg-n-slate-2 ring-n-slate-6',
  stopped: 'bg-n-slate-2 ring-n-slate-6',
  wrong_number: 'bg-n-ruby-2 ring-n-ruby-6',
};

// 'pt_BR' (vue-i18n) → 'pt-BR' (Intl).
const intlLocale = locale => (locale || 'en').split('_').join('-');

// chat#1487 — datas dos limites do WhatsApp no fuso e no idioma da conta (fusoDaConta), nunca no do navegador.
// `epochSeconds`: como o motor manda. Sem fuso válido, o Intl usa o padrão dele (só em teste).
export const limitDateTime = (epochSeconds, { locale, timeZone } = {}) =>
  new Date(epochSeconds * 1000).toLocaleString(intlLocale(locale), {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    timeZone,
  });

export const limitDate = (epochSeconds, { locale, timeZone } = {}) =>
  new Date(epochSeconds * 1000).toLocaleDateString(intlLocale(locale), {
    timeZone,
  });

// "551140001487" → "+55 (11) 4000-1487", com o mesmo formatador da Nova conversa. Vazio fica vazio.
export const phoneLabel = digits =>
  digits ? telefoneLegivel(`+${String(digits).split('+').join('')}`) : '';

// chat#1487 — quem pode usar o WhatsApp API depois de 24 horas: as origens do backend (disabled_origins), com o
// ícone e os selos da tela. Atendentes e lembretes do CRM são o uso recomendado; campanha é o de maior risco.
export const ROUTING_ORIGINS = [
  { key: 'human', icon: 'i-lucide-headset', recommended: true },
  { key: 'bot', icon: 'i-lucide-bot' },
  { key: 'automation', icon: 'i-lucide-workflow' },
  { key: 'crm_follow_up', icon: 'i-lucide-bell-ring', recommended: true },
  { key: 'campaign', icon: 'i-lucide-megaphone', risky: true },
];
const ORIGIN_KEYS = ROUTING_ORIGINS.map(origin => origin.key);

export const enabledOriginsFor = (disabled = []) =>
  ORIGIN_KEYS.filter(key => !disabled.includes(key));

export const disabledOriginsFor = (enabled = []) =>
  ORIGIN_KEYS.filter(key => !enabled.includes(key));

// Ritmo: três escolhas na frase e "Outro" para o resto (mesmos limites do servidor: 1 a 120).
export const PACE_OPTIONS = [10, 20, 30];
export const PACE_RECOMMENDED = 20;
export const PACE_MIN = 1;
export const PACE_MAX = 120;
export const PACE_OTHER = 'other';

export const paceChoiceFor = rate =>
  PACE_OPTIONS.includes(rate) ? rate : PACE_OTHER;

export const validPace = value =>
  Number.isInteger(value) && value >= PACE_MIN && value <= PACE_MAX;
