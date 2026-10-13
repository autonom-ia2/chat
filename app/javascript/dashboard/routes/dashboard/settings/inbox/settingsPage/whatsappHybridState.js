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
