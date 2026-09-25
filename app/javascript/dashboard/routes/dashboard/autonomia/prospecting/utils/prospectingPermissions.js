// Enviar ao CRM e Adicionar à campanha alteram outros módulos: o servidor diz
// no payload das configurações se quem está na tela pode (#682), pela mesma
// regra com que recusaria o envio. A permissão de prospecção (canManage)
// continua valendo por cima.
export const canSendToCrm = (canManage, settings) =>
  canManage && settings?.can_send_to_crm === true;

// Adicionar à campanha cria o segmento (lista e etiqueta nos contatos), e isso
// só pede a prospecção: o servidor só exige campaign_manage quando vem uma
// campanha (authorize_campaign_update!). Por isso o botão segue a prospecção,
// e só a escolha da campanha, dentro da janela, pede campaign_manage.
export const canAddToCampaign = canManage => canManage;

export const canChooseCampaign = (canManage, settings) =>
  canManage && settings?.can_manage_campaigns === true;
