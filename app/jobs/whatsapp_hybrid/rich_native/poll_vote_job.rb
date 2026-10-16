# O voto na enquete nativa do plano B do Híbrido (chat#1709, fase 3), recebido pelo evento `poll.vote` da sessão
# (WhatsappHybrid::RichNative::PollVoteWebhook). A enquete é achada pelo id físico (o mesmo registro do ack,
# WhatsappHybrid::WebTransport.message_for) e precisa ser nossa e nativa; os títulos viram as opções oferecidas
# (Waha::RichNative::PollVote). Cria na conversa da enquete a mensagem do cliente com o voto (o mesmo contrato da caixa
# WAHA comum): `selected_option`, `selected_options` e `in_reply_to`; voto retirado = atividade escondida. Voto feito
# pelo celular da empresa (fromMe) não entra. O mesmo voto (id) não entra duas vezes.
class WhatsappHybrid::RichNative::PollVoteJob < ApplicationJob
  queue_as :medium
  SOURCE_PREFIX = 'waha-poll-vote-'.freeze
  REMOVED_KEY = 'waha.poll.vote_removed'.freeze

  def perform(connection_id, fields)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return if connection.nil? || fields['from_me'] || !Waha::RichNative.enabled?(connection.account)

    poll = WhatsappHybrid::WebTransport.message_for(connection, fields['poll_id'].to_s.split('_').last)
    return unless Waha::RichNative::PollVote.native_poll?(poll)

    selected = Waha::RichNative::PollVote.selected_for(poll, fields['options'])
    create_vote!(poll, selected, fields['vote_id']) if selected
  end

  private

  def create_vote!(poll, selected, vote_id)
    source_id = "#{SOURCE_PREFIX}#{vote_id}" if vote_id.present?
    return if source_id && poll.conversation.messages.exists?(source_id: source_id)

    message = poll.conversation.messages.new(account_id: poll.account_id, inbox_id: poll.inbox_id, message_type: :incoming,
                                             sender: poll.conversation.contact, source_id: source_id,
                                             content: content_for(poll, selected))
    Waha::RichNative::PollVote.assign!(message, poll, selected)
    message.save!
  end

  def content_for(poll, selected)
    return selected.pluck('title').join(', ') if selected.any?

    I18n.t(REMOVED_KEY, locale: poll.account.locale, default: I18n.t(REMOVED_KEY))
  end
end
