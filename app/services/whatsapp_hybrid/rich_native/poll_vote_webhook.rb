# Prepend em Webhooks::WhatsappHybridController (chat#1709, fase 3 e rodada 2): os eventos `poll.vote` (voto na enquete)
# e `event.response` (resposta ao convite de evento) do motor, com a flag `whatsapp_rich_native` na conta. Passam pelas
# mesmas travas do controller (HMAC no before_action, janela de 5 minutos e evento já visto). Só o que o job usa vai à
# fila. Sem a flag (ou outro evento), segue o original, que ignora o que não conhece.
module WhatsappHybrid::RichNative::PollVoteWebhook
  EVENT = WhatsappHybrid::RichNative::PollVoteEvents::EVENT
  EVENT_RESPONSE = WhatsappHybrid::RichNative::PollVoteEvents::EVENT_RESPONSE
  # Resposta do motor => resposta gravada (Waha::RichNative::EventResponses::RESPONSES). UNKNOWN fica de fora.
  RESPONSES = { 'GOING' => 'going', 'NOT_GOING' => 'not_going', 'MAYBE' => 'maybe' }.freeze

  def create
    body = rich_native_body
    return super if body.nil?
    return head :bad_request unless fresh?(body)
    return head :ok unless first_delivery?(body['id'])

    enqueue_rich_native(body)
    head :ok
  end

  private

  def rich_native_body
    body = JSON.parse(request.raw_post)
    body if body.is_a?(Hash) && [EVENT, EVENT_RESPONSE].include?(body['event']) && Waha::RichNative.enabled?(@connection.account)
  rescue JSON::ParserError
    nil
  end

  def enqueue_rich_native(body)
    if body['event'] == EVENT
      WhatsappHybrid::RichNative::PollVoteJob.perform_later(@connection.id, poll_vote_fields(body))
    else
      fields = event_response_fields(body)
      WhatsappHybrid::RichNative::EventResponseJob.perform_later(@connection.id, fields) if fields
    end
  end

  def poll_vote_fields(body)
    payload = body['payload'].is_a?(Hash) ? body['payload'] : {}
    poll = payload['poll'].is_a?(Hash) ? payload['poll'] : {}
    vote = payload['vote'].is_a?(Hash) ? payload['vote'] : {}
    { 'poll_id' => poll['id'].to_s, 'options' => Array(vote['selectedOptions']).grep(String), 'vote_id' => vote['id'].to_s,
      'from_me' => vote['fromMe'] == true }
  end

  # payload: { id, from, fromMe, eventCreationKey: { id }, eventResponse: { response, timestampMs, extraGuestCount } }.
  def event_response_fields(body)
    payload = body['payload'].is_a?(Hash) ? body['payload'] : {}
    key = payload['eventCreationKey'].is_a?(Hash) ? payload['eventCreationKey'] : {}
    answer = payload['eventResponse'].is_a?(Hash) ? payload['eventResponse'] : {}
    response = RESPONSES[answer['response'].to_s]
    return if response.nil?

    { 'event_id' => key['id'].to_s, 'response' => response, 'extra_guests' => answer['extraGuestCount'].to_i,
      'response_id' => payload['id'].to_s, 'from_me' => payload['fromMe'] == true }
  end
end
