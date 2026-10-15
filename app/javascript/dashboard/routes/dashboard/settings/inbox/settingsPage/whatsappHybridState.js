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
  if (data.status === 'failed') return data.phone ? 'REMOVED' : 'FAILED';
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

// Selo do estado: as mesmas cores e ícones das situações dos modelos (verde pronto, âmbar esperando, vermelho com
// problema, cinza parado).
export const STATUS_VISUALS = {
  NOT_CONNECTED: {
    icon: 'i-lucide-circle-dashed',
    chip: 'bg-n-slate-3 text-n-slate-11',
  },
  AWAITING: { icon: 'i-lucide-clock-3', chip: 'bg-n-amber-3 text-n-amber-11' },
  CONNECTED: {
    icon: 'i-lucide-circle-check',
    chip: 'bg-n-teal-3 text-n-teal-11',
  },
  PAUSED: {
    icon: 'i-lucide-circle-pause',
    chip: 'bg-n-slate-3 text-n-slate-11',
  },
  DISCONNECTED: {
    icon: 'i-lucide-unplug',
    chip: 'bg-n-slate-3 text-n-slate-11',
  },
  FAILED: { icon: 'i-lucide-circle-alert', chip: 'bg-n-ruby-3 text-n-ruby-11' },
  REMOVED: {
    icon: 'i-lucide-circle-alert',
    chip: 'bg-n-ruby-3 text-n-ruby-11',
  },
};

// Fundo da caixa de situação, como a caixa de situação do modelo.
export const PHASE_TONES = {
  connected: 'bg-n-teal-2 ring-n-teal-6',
  paused: 'bg-n-slate-2 ring-n-slate-6',
  stopped: 'bg-n-slate-2 ring-n-slate-6',
  wrong_number: 'bg-n-ruby-2 ring-n-ruby-6',
};
