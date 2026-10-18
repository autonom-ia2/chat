# "Apagar para todos" (chat#1709): o sinal por mensagem `c2y_revocable`, que vai ao painel junto da mensagem (JSON da
# API e evento da tela). Só com a flag `whatsapp_rich_native` na conta (sem ela, false: o menu fica como hoje). É true
# quando apagar no painel apaga também no WhatsApp do cliente:
# - caixa WAHA comum (Channel::Api com provider 'waha'): mensagem nossa (de saída) que não é nota. O conector apaga no
#   WhatsApp quando a mensagem fica `deleted`;
# - caixa híbrida com a flag: mensagem nossa, não nota, com id físico do motor, a mesma regra do
#   WhatsappHybrid::RichNative::RevokeOnDelete (é ele que pede o apagar ao motor);
# - mensagem que falhou (nunca chegou ao cliente) e fora disso, false: apagar some só do painel.
# Custo (roda em todo evento e em toda mensagem da lista): primeiro os campos da própria mensagem, depois a flag (pela
# conta da requisição, sem carregar a conversa); só então a caixa, pela conversa, que a lista de mensagens já tem
# carregada (a mensagem aponta a mesma conversa): a lista não busca uma caixa nem uma conta por mensagem (spec conta).
module Waha::RichNative::Revocable
  KEY = :c2y_revocable

  module_function

  def for(message)
    # A que falhou nunca chegou ao cliente: apagar some só do painel.
    return false unless message.outgoing? && !message.private? && !message.failed?

    account = account_of(message)
    return false unless Waha::RichNative.enabled?(account)

    conversation = message.conversation
    waha_inbox?(conversation.inbox) || hybrid_revocable?(message, conversation.inbox, account)
  rescue StandardError => e
    # Sinal de tela: um erro aqui não pode derrubar a lista de mensagens; fica o rótulo de sempre.
    Rails.logger.error("[waha] rich native revocable message=#{message.id} #{e.class}")
    false
  end

  # A flag antes da conversa: a conta da requisição (Current.account, a mesma da mensagem na lista) ou a da mensagem.
  def account_of(message)
    Current.account&.id == message.account_id ? Current.account : message.account
  end

  def waha_inbox?(inbox)
    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end

  def hybrid_revocable?(message, inbox, account)
    WhatsappHybrid::RichNative::RevokeOnDelete.revokes?(message, inbox: inbox, account: account) &&
      WhatsappHybrid::RichNative::Quote.physical_id_of(message).present?
  end
end
