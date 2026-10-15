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

// #1589 — o tempo de cada lembrete, em horas, escolhido na própria frase.
// No servidor: `<lembrete>_after_hours` em metadata.ai.service_reminders
// (Crm::Ai::Config::SERVICE_REMINDER_HOURS, as mesmas opções); padrão 1 dia.
export const TEMPOS_DO_LEMBRETE = {
  progress: [4, 24, 48, 72],
  resolved_check: [24, 48, 72, 168],
};
export const TEMPO_PADRAO = 24;
export const chaveDoTempo = lembrete => `${lembrete}_after_hours`;
// Só as opções dos botões valem (a mesma regra do servidor); outro valor é 1 dia.
export const tempoDoLembrete = (ligados, lembrete) => {
  const horas = Number(ligados?.[chaveDoTempo(lembrete)]);
  return (TEMPOS_DO_LEMBRETE[lembrete] || []).includes(horas)
    ? horas
    : TEMPO_PADRAO;
};
export const rotuloDoTempo = horas =>
  `CRM_FUNIL.ATENDER.LEMBRETES.TEMPOS.H${horas}`;
