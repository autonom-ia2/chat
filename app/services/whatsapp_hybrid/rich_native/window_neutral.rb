# Prepend em Conversations::MessageWindowService (chat#1709, fase 3): numa caixa Cloud (Channel::Whatsapp), a mensagem
# recebida marcada `additional_attributes.c2y_window_neutral` não conta como abertura da janela de 24 h. É o voto na
# enquete do plano B do Híbrido (WhatsappHybrid::RichNative::PollVoteJob): ele chega pelo motor (WhatsApp API), não pela
# Meta, que não abriu a janela por ele. Contado como abertura, o roteador do Híbrido (WhatsappHybrid::Router) mandaria a
# resposta da IA ao voto pela Cloud, em texto livre, fora da janela. Sem contar, a resposta sai pelo plano B, como
# qualquer resposta com a janela fechada. Se a Meta entregar algo de verdade (mensagem do cliente), essa abre a janela
# como sempre. Outras caixas: o cálculo de sempre.
# Segunda rede: o 131047 da Meta já devolve ao plano B a mensagem que a Cloud recusou (WhatsappHybrid::CloudFailureFallback).
module WhatsappHybrid::RichNative::WindowNeutral
  KEY = 'c2y_window_neutral'.freeze

  # CONTRATO PÚBLICO (Followup IA, #1766: messaging_window.rb, service_window.rb, conversa_aberta): a relation de
  # mensagens recebidas sem as neutras (`additional_attributes.c2y_window_neutral`), as que abrem a janela de 24 h. A
  # regra mora só aqui; nome e assinatura não mudam.
  def self.opening(relation)
    relation.where('(messages.additional_attributes ->> ?) IS NULL', KEY)
  end

  private

  def last_incoming_message
    return super unless @conversation.inbox&.channel_type == 'Channel::Whatsapp'

    @last_incoming_message ||= WhatsappHybrid::RichNative::WindowNeutral.opening(
      @conversation.messages.where(account_id: @conversation.account_id).incoming
    ).last
  end
end
