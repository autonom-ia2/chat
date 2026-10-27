class Webhooks::InstagramEventsJob < MutexApplicationJob
  queue_as :default
  # This lock is only a short race dampener for first-message conversation creation.
  # ContactInbox creation is already protected by a unique index, but conversation
  # lookup is `find active conversation || create`, so concurrent first messages from
  # the same IG contact can create duplicate conversations.
  #
  # ActiveJob retries are not FIFO, so a longer retry window does not preserve message
  # order. Use deterministic backoff so the final attempt happens after the 3s lock TTL,
  # then process without the lock instead of dropping the webhook.
  retry_on_lock_conflict wait: ->(executions) { executions.seconds }, attempts: 3, on_exhaustion: :process_without_lock

  # @return [Array] We will support further events like reaction or seen in future
  # `:reaction`: o selo na mensagem reagida (Instagram::ReacaoDoCliente, chave `conversa_instagram`, #2113) e o agente da
  # Autonom.ia (operate), que só materializa em inbox com agente ativo + flag on.
  # `:message_edit`: o cliente editou a mensagem (#2113, Instagram::MessageEditService). Só chega com o campo de edição
  # inscrito no app da Meta (ver Channel::Instagram#subscribe).
  SUPPORTED_EVENTS = [:message, :read, :postback, :reaction, :message_edit].freeze
  TEST_EVENT_FIELD = 'messages'.freeze
  COMMENT_FIELDS = %w[comments mentions].freeze
  COMMENT_JOB = 'Webhooks::InstagramCommentJob'.freeze

  def perform(entries)
    @entries = entries
    # Comentário e evento de teste (#2200) só viram job ou o serviço de teste: sem contato, o lock não protege nada.
    return process_entries(entries) if contact_instagram_id.nil?

    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: contact_instagram_id, ig_account_id: ig_account_id)
    # Keep the lock TTL just long enough for the first job to fetch profile data and
    # create the contact/conversation. A longer TTL would add user-visible latency for
    # hot contacts without giving us ordering guarantees.
    with_lock(key, 3.seconds) do
      process_entries(entries)
    end
  end

  def process_without_lock(entries)
    Rails.logger.warn("[#{self.class.name}] Processing without lock after lock retry exhaustion")
    process_entries(entries)
  end

  # https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook
  def process_entries(entries)
    entries.each do |entry|
      process_single_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_single_entry(entry)
    process_changes(entry) if entry[:changes].present?
    process_messages(entry)
  end

  # `changes` (#2200): o evento de teste do painel da Meta chega como field `messages`; comentário real e menção chegam
  # como `comments` e `mentions` e vão para o job dos comentários (#2196), com (instagram_id, field, value, time). Esse
  # job ignora conta que não conhece nesta stack. Sem a classe publicada, o evento só fica no log.
  def process_changes(entry)
    entry[:changes].each do |change|
      next process_test_event(change) if change[:field] == TEST_EVENT_FIELD

      enqueue_comment(entry, change)
    end
  end

  def enqueue_comment(entry, change)
    job = COMMENT_FIELDS.include?(change[:field]) ? COMMENT_JOB.safe_constantize : nil
    return Rails.logger.info("Instagram webhook: no job for field #{change[:field].inspect}") if job.nil?
    return Rails.logger.warn("Instagram webhook: #{change[:field]} without an object value, skipped") unless change[:value].is_a?(Hash)

    job.perform_later(entry[:id].to_s, change[:field], comment_ids(change[:field], change[:value].to_h), entry[:time])
  end

  # Só os ids vão para a fila: os argumentos ficam em claro no Redis do Sidekiq (retry e dead set), e o job busca o
  # texto e o autor na Graph (#2196). Nada de texto do comentário nem de username.
  def comment_ids(field, value)
    return value.slice('comment_id', 'media_id') if field == 'mentions'

    { 'id' => value['id'], 'parent_id' => value['parent_id'], 'from' => value['from']&.slice('id'),
      'media' => value['media']&.slice('id', 'ad_id') }.compact
  end

  def process_messages(entry)
    messages(entry).each do |messaging|
      Rails.logger.info("Instagram Events Job Messaging: #{messaging}")

      instagram_id = instagram_id(messaging)
      channel = find_channel(instagram_id)

      next if channel.blank?

      if (event_name = event_name(messaging))
        send(event_name, messaging, channel)
      end
    end
  end

  def agent_message_via_echo?(messaging)
    messaging[:message].present? && messaging[:message][:is_echo].present?
  end

  def process_test_event(change)
    messaging = change[:value]

    Instagram::TestEventService.new(messaging).perform if messaging.present?
  end

  def instagram_id(messaging)
    if agent_message_via_echo?(messaging)
      messaging[:sender][:id]
    else
      messaging[:recipient][:id]
    end
  end

  def ig_account_id
    @entries&.first&.dig(:id)
  end

  def contact_instagram_id
    entry = @entries&.first
    return nil unless entry

    # Handle both messaging and standby arrays
    messaging = (entry[:messaging].presence || entry[:standby] || []).first
    return nil unless messaging

    # For echo messages (outgoing from our account), use recipient's ID (the contact)
    # For incoming messages (from contact), use sender's ID (the contact)
    if messaging.dig(:message, :is_echo)
      messaging.dig(:recipient, :id)
    else
      messaging.dig(:sender, :id)
    end
  end

  def sender_id
    @entries&.dig(0, :messaging, 0, :sender, :id)
  end

  def find_channel(instagram_id)
    # There will be chances for the instagram account to be connected to a facebook page,
    # so we need to check for both instagram and facebook page channels
    # priority is for instagram channel which created via instagram login
    channel = Channel::Instagram.find_by(instagram_id: instagram_id)
    # If not found, fallback to the facebook page channel
    channel ||= Channel::FacebookPage.find_by(instagram_id: instagram_id)

    channel
  end

  def event_name(messaging)
    # NÃO memoizar: roda por-`messaging` no loop. Memoizar fazia o 1º evento do batch ditar o dispatch
    # de todos os seguintes -> num batch misto, mensagem real seria roteada a `reaction` (perdida) ou
    # reaction a `message` (quebra em agent_message_via_echo?). Bug latente exposto ao incluir :reaction.
    SUPPORTED_EVENTS.find { |key| messaging.key?(key) }
  end

  def message(messaging, channel)
    if channel.is_a?(Channel::Instagram)
      ::Instagram::MessageText.new(messaging, channel).perform
    else
      ::Instagram::Messenger::MessageText.new(messaging, channel).perform
    end
  end

  def read(messaging, channel)
    # Use a single service to handle read status for both channel types since the params are same
    ::Instagram::ReadStatusService.new(params: messaging, channel: channel).perform
  end

  def postback(messaging, channel)
    postback_message = {
      mid: messaging[:postback][:mid],
      text: messaging[:postback][:title]
    }
    message(messaging.merge(message: postback_message), channel)
  end

  # Reação no Instagram. Payload Meta: reaction={mid,action,reaction,emoji}. Dois caminhos independentes:
  # o selo na mensagem reagida (#2113, react e unreact) e o agente da Autonomia (abaixo).
  def reaction(messaging, channel)
    inbox = ::Inbox.find_by(channel: channel)
    return if inbox.nil?

    ::Instagram::ReacaoDoCliente.new(messaging: messaging, inbox: inbox).perform
    materialize_reaction_for_agent(messaging, inbox)
  end

  # AUTONOMIA (Onda 2b): só 'react' (ignora 'unreact'). Materializa via ReactionMaterializer (channel-agnóstico): só em
  # inbox com agente ativo + flag on; senão no-op. Fail-safe. Dedup pelo event_source_id (mid+timestamp), já
  # que o evento de reação do IG não tem id próprio.
  def materialize_reaction_for_agent(messaging, inbox)
    return unless ::Autonomia::Agents::Config.operate_reactions_enabled?

    data = messaging[:reaction] || {}
    return unless data[:action].to_s == 'react'

    ::Autonomia::Agents::Operate::ReactionMaterializer.call(
      inbox: inbox,
      reacted_source_id: data[:mid],
      emoji: data[:emoji],
      event_source_id: "ig_reaction:#{data[:mid]}:#{messaging[:timestamp]}"
    )
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] ig_reaction_failed #{e.class}")
    nil
  end

  def message_edit(messaging, channel)
    ::Instagram::MessageEditService.new(messaging: messaging, channel: channel).perform
  end

  def messages(entry)
    (entry[:messaging].presence || entry[:standby] || [])
  end
end

# Actual response from Instagram webhook (both via Facebook page and Instagram direct)
# [
#   {
#     "time": <timestamp>,
#     "id": <INSTAGRAM_USER_ID>,
#     "messaging": [
#       {
#         "sender": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "recipient": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "timestamp": <timestamp>,
#         "message": {
#           "mid": <MESSAGE_ID>,
#           "text": <MESSAGE_TEXT>
#         }
#       }
#     ]
#   }
# ]

# Instagram's webhook via Instagram direct testing quirk: Test payloads vs Actual payloads
# When testing in Facebook's developer dashboard, you'll get a Page-style
# payload with a "changes" object. But don't be fooled! Real Instagram DMs
# arrive in the familiar Messenger format with a "messaging" array.
# This apparent inconsistency is actually by design - Instagram's webhooks
# use different formats for testing vs production to maintain compatibility
# with both Instagram Direct and Facebook Page integrations.
# See: https://developers.facebook.com/docs/instagram-platform/webhooks#event-notifications

# Test response from via Instagram direct
# [
#   {
#     "id": "0",
#     "time": <timestamp>,
#     "changes": [
#       {
#         "field": "messages",
#         "value": {
#           "sender": {
#             "id": "12334"
#           },
#           "recipient": {
#             "id": "23245"
#           },
#           "timestamp": "1527459824",
#           "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#           }
#         }
#       }
#     ]
#   }
# ]

# Test response via Facebook page
# [
#   {
#     "time": <timestamp>,,
#     "id": "0",
#     "messaging": [
#       {
#         "sender": {
#           "id": "12334"
#         },
#         "recipient": {
#           "id": "23245"
#         },
#         "timestamp": <timestamp>,
#         "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#         }
#       }
#     ]
#   }
# ]
