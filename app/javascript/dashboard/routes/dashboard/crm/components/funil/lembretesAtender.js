// #1498 — os lembretes que já vêm num funil de Atender. Cobrança lembra do
// vencimento; os outros avisam o andamento e perguntam se resolveu. A chave é
// a mesma do servidor (metadata.ai.service_reminders).
export const LEMBRETES_DO_MODELO = {
  COBRANCA: ['payment'],
  PADRAO: ['progress', 'resolved_check'],
};
export const lembretesDoModelo = modelo =>
  LEMBRETES_DO_MODELO[modelo] || LEMBRETES_DO_MODELO.PADRAO;

export const CHAVE_DO_LEMBRETE = {
  progress: 'ANDAMENTO',
  resolved_check: 'RESOLVEU',
  payment: 'COBRAR',
};
