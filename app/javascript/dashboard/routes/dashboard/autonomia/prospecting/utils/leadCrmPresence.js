// Lead já no CRM e lead descartado (#732). O lead continua da conta: não há
// bloqueio por vendedor nem prazo. O card mostra funil, estágio e responsável
// do card que o lead já tem, e o envio em lote ao CRM deixa de fora quem já
// está lá ou foi descartado. O servidor recusa do mesmo jeito (CrmCardBatch).
export const isLeadInCrm = lead => Boolean(lead?.crm_card_id);

export const isLeadDiscarded = lead => lead?.status === 'discarded';

// Quem mostra a faixa (LeadStatusBanner) no card e no painel.
export const hasLeadStatus = lead => isLeadInCrm(lead) || isLeadDiscarded(lead);

export const isCrmSendable = lead => !hasLeadStatus(lead);

export const crmSendableLeads = leads => leads.filter(isCrmSendable);

// "Funil, estágio, responsável". Card recém-criado pela janela de envio ainda
// não tem o detalhe (vem na próxima leitura do lead): fica só "Já está no CRM".
export const crmPresenceDetail = (lead, noOwnerLabel) => {
  const presence = lead?.crm_presence;
  if (!isLeadInCrm(lead) || !presence) return '';

  return [
    presence.pipeline_name,
    presence.stage_name,
    presence.owner_name || noOwnerLabel,
  ]
    .filter(Boolean)
    .join(', ');
};
