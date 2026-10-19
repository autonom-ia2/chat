# O voto na enquete nativa do plano B do Híbrido (chat#1709, fase 3), recebido pelo evento `poll.vote` da sessão
# (WhatsappHybrid::RichNative::PollVoteWebhook). A enquete é achada pelo id físico: primeiro o registro do ack
# (WhatsappHybrid::WebTransport.message_for, que expira em 7 dias); depois, na caixa (WhatsappHybrid::RichNative::
# PollLookup); sem nenhum, só uma linha de log. Precisa ser nossa e nativa; os títulos viram as opções oferecidas
# (Waha::RichNative::PollVote). O mesmo contrato da caixa WAHA comum: o voto fica agregado na enquete (`poll_votes`,
# Waha::RichNative::PollVotes) e na conversa da enquete fica uma atividade escondida (`c2y_hidden`,
# `poll_vote_applied_to`) como registro de que o voto chegou. Voto feito pelo celular da empresa (fromMe) não entra. O
# mesmo voto (id) não entra duas vezes: a atividade guarda `source_id` 'waha-poll-vote-<id>'.
# A atividade não abre a janela de 24 h da Cloud (`c2y_window_neutral`, WhatsappHybrid::RichNative::WindowNeutral): o
# voto não passou pela Meta. Nasce como escrita interna (Waha::RichNative::InternalWrite), para o ContractGuard manter
# as chaves que o chat2you grava.
class WhatsappHybrid::RichNative::PollVoteJob < ApplicationJob
  queue_as :medium
  SOURCE_PREFIX = 'waha-poll-vote-'.freeze

  def perform(connection_id, fields)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return if connection.nil? || fields['from_me'] || !Waha::RichNative.enabled?(connection.account)

    physical_id = fields['poll_id'].to_s.split('_').last
    poll = poll_for(connection, physical_id)
    return Rails.logger.info("[whatsapp_hybrid] poll vote without our poll inbox=#{connection.inbox_id}") if poll.nil?

    selected = Waha::RichNative::PollVote.selected_for(poll, fields['options'])
    record_vote!(poll, selected, fields) if selected
  end

  private

  def poll_for(connection, physical_id)
    return if physical_id.blank?

    cached = WhatsappHybrid::WebTransport.message_for(connection, physical_id)
    return cached if Waha::RichNative::PollVote.native_poll?(cached)

    WhatsappHybrid::RichNative::PollLookup.find(connection.inbox_id, physical_id)
  end

  def record_vote!(poll, selected, fields)
    vote_id = fields['vote_id']
    source_id = "#{SOURCE_PREFIX}#{vote_id}" if vote_id.present?
    return if source_id && poll.conversation.messages.exists?(source_id: source_id)

    message = poll.conversation.messages.new(account_id: poll.account_id, inbox_id: poll.inbox_id, message_type: :incoming,
                                             sender: poll.conversation.contact, source_id: source_id,
                                             additional_attributes: { WhatsappHybrid::RichNative::WindowNeutral::KEY => true })
    # O voto agregado na enquete e o registro dele, juntos: um sem o outro deixaria o voto contado sem registro (e o job
    # refeito o contaria de novo como turno) ou o registro sem o voto. Sem as validações do modelo, como o resto do pacote.
    ActiveRecord::Base.transaction do
      Waha::RichNative::PollVote.record_vote!(message, poll, selected, timestamp: fields['timestamp'])
      Waha::RichNative::InternalWrite.mark!(message).save!(validate: false)
    end
  end
end
