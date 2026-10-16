# Prepend em Webhooks::WhatsappHybridController (chat#1709, fase 3): o evento `poll.vote` do motor, com a flag
# `whatsapp_rich_native` na conta. Passa pelas mesmas travas do controller (HMAC no before_action, janela de 5 minutos
# e evento já visto). Só o que o job usa vai à fila: o id da enquete, os títulos marcados, o id e o autor do voto.
# Sem a flag (ou outro evento), segue o original, que ignora o que não conhece.
module WhatsappHybrid::RichNative::PollVoteWebhook
  EVENT = WhatsappHybrid::RichNative::PollVoteEvents::EVENT

  def create
    body = poll_vote_body
    return super if body.nil?
    return head :bad_request unless fresh?(body)
    return head :ok unless first_delivery?(body['id'])

    WhatsappHybrid::RichNative::PollVoteJob.perform_later(@connection.id, poll_vote_fields(body))
    head :ok
  end

  private

  def poll_vote_body
    body = JSON.parse(request.raw_post)
    body if body.is_a?(Hash) && body['event'] == EVENT && Waha::RichNative.enabled?(@connection.account)
  rescue JSON::ParserError
    nil
  end

  def poll_vote_fields(body)
    payload = body['payload'].is_a?(Hash) ? body['payload'] : {}
    poll = payload['poll'].is_a?(Hash) ? payload['poll'] : {}
    vote = payload['vote'].is_a?(Hash) ? payload['vote'] : {}
    { 'poll_id' => poll['id'].to_s, 'options' => Array(vote['selectedOptions']).grep(String), 'vote_id' => vote['id'].to_s,
      'from_me' => vote['fromMe'] == true }
  end
end
