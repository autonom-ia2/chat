// Enviar ao CRM e Adicionar à campanha alteram outros módulos: o servidor diz
// no payload das configurações se quem está na tela pode (#682), pela mesma
// regra com que recusaria o envio. A permissão de prospecção (canManage)
// continua valendo por cima.
export const canSendToCrm = (canManage, settings) =>
  canManage && settings?.can_send_to_crm === true;

export const canAddToCampaign = (canManage, settings) =>
  canManage && settings?.can_manage_campaigns === true;
