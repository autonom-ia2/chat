# A resposta ao convite de evento nativo do plano B do Híbrido (chat#1709, rodada 2), recebida pelo evento
# `event.response` da sessão (WhatsappHybrid::RichNative::PollVoteWebhook), como o voto da enquete
# (WhatsappHybrid::RichNative::PollVoteJob). O evento é achado pelo id físico (registro do ack, depois a caixa) e precisa
# ser nosso e nativo. A resposta fica agregada no evento (`event_responses`, Waha::RichNative::EventResponses) e na
# conversa fica uma atividade escondida, que não abre a janela de 24 h da Cloud. Resposta do celular da empresa (fromMe)
# não entra; a mesma resposta (id) não entra duas vezes (`source_id` 'waha-event-response-<id>').
class WhatsappHybrid::RichNative::EventResponseJob < ApplicationJob
  queue_as :medium
  SOURCE_PREFIX = 'waha-event-response-'.freeze

  def perform(connection_id, fields)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return if connection.nil? || fields['from_me'] || !Waha::RichNative.enabled?(connection.account)
    return unless Waha::RichNative::EventResponses.valid_response?(fields['response'])

    event = event_for(connection, fields['event_id'].to_s.split('_').last)
    return Rails.logger.info("[whatsapp_hybrid] event response without our event inbox=#{connection.inbox_id}") if event.nil?

    record!(event, fields)
  end

  private

  def event_for(connection, physical_id)
    return if physical_id.blank?

    cached = WhatsappHybrid::WebTransport.message_for(connection, physical_id)
    return cached if Waha::RichNative::EventResponses.native_event?(cached)

    WhatsappHybrid::RichNative::PollLookup.find(connection.inbox_id, physical_id, matcher: Waha::RichNative::EventResponses.method(:native_event?))
  end

  def record!(event, fields)
    source_id = "#{SOURCE_PREFIX}#{fields['response_id']}" if fields['response_id'].present?
    return if source_id && event.conversation.messages.exists?(source_id: source_id)

    message = event.conversation.messages.new(account_id: event.account_id, inbox_id: event.inbox_id, message_type: :incoming,
                                              sender: event.conversation.contact, source_id: source_id,
                                              additional_attributes: { WhatsappHybrid::RichNative::WindowNeutral::KEY => true })
    Waha::RichNative::EventResponses.record_response!(message, event, response: fields['response'], extra_guests: fields['extra_guests'])
    Waha::RichNative::InternalWrite.mark!(message).save!
  end
end
