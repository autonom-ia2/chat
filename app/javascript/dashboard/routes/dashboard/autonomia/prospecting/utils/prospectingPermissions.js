// Enviar ao CRM altera outro módulo: o servidor diz no payload das
// configurações se quem está na tela pode (#682), pela mesma regra com que
// recusaria o envio. A permissão de prospecção (canManage) continua valendo
// por cima. (Adicionar à campanha por etiqueta saiu no #2695: a lista vira
// Público pelo "Guardar para mandar mensagem" da tela Achar empresas.)
export const canSendToCrm = (canManage, settings) =>
  canManage && settings?.can_send_to_crm === true;
