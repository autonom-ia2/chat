// Lead atualizado no servidor (evento prospecting.lead.updated, #678): o
// enriquecimento e a verificação de WhatsApp rodam em fila e chegam por aqui. A
// tela troca o lead que já mostra; lead que não está na tela é ignorado.
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export const useLeadLiveUpdates = applyLead =>
  useEmitter(BUS_EVENTS.PROSPECTING_LEAD_UPDATED, data => {
    if (data?.lead?.id) applyLead(data.lead);
  });
