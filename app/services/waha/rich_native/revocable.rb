# "Apagar para todos" (chat#1709): o sinal por mensagem `c2y_revocable`, que vai ao painel junto da mensagem (JSON da
# API e evento da tela). É true quando apagar no painel apaga também no WhatsApp do cliente:
# - caixa WAHA comum (Channel::Api com provider 'waha'): mensagem nossa (de saída) que não é nota. O conector apaga no
#   WhatsApp quando a mensagem fica `deleted`, com ou sem a flag `whatsapp_rich_native`;
# - caixa híbrida com a flag: mensagem nossa, não nota, com id físico do motor, a mesma regra do
#   WhatsappHybrid::RichNative::RevokeOnDelete (é ele que pede o apagar ao motor);
# - fora disso, false: apagar some só do painel.
# Inbox e conta vêm pela conversa (já carregada com a lista), para a lista não buscar uma caixa por mensagem.
module Waha::RichNative::Revocable
  KEY = :c2y_revocable

  module_function

  def for(message)
    return false unless message.outgoing? && !message.private?

    conversation = message.conversation
    waha_inbox?(conversation.inbox) || hybrid_revocable?(message, conversation.inbox, conversation.account)
  rescue StandardError => e
    # Sinal de tela: um erro aqui não pode derrubar a lista de mensagens; fica o rótulo de sempre.
    Rails.logger.error("[waha] rich native revocable message=#{message.id} #{e.class}")
    false
  end

  def waha_inbox?(inbox)
    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end

  def hybrid_revocable?(message, inbox, account)
    WhatsappHybrid::RichNative::RevokeOnDelete.revokes?(message, inbox: inbox, account: account) &&
      WhatsappHybrid::RichNative::Quote.physical_id_of(message).present?
  end
end
