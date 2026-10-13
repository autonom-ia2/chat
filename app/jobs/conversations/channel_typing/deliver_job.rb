# chat#1442 — A chamada ao canal sai do request: os serviços de canal usam HTTParty sem timeout próprio,
# o que deixa valer o padrão do Net::HTTP (60 s para abrir e 60 s para ler), e a toggle_typing_status do
# robô não pode esperar a Meta.
# Fila medium: atrás da high, que envia as respostas (SendReplyJob), e a mesma da entrega do agente nativo.
# No job a chamada ao canal é limitada a CHANNEL_TIMEOUT_SECONDS, para não prender thread da fila.
# "Digitando" que chega tarde é pior que não chegar. O pedido é descartado (com log) quando:
# - ficou mais velho que MAX_AGE (stale);
# - é um "on" e a resposta já saiu depois dele: reacenderia o indicador (already_replied);
# - é um "on" pedido antes de um "off" que já foi processado: "on" e "off" são jobs independentes e podem
#   rodar fora de ordem, o que deixaria o indicador preso (superseded).
# O instante do último "off" de cada conversa fica no Redis por OFF_MARK_TTL_SECONDS. Sem Redis, o job
# segue como se não houvesse "off" gravado.
class Conversations::ChannelTyping::DeliverJob < ApplicationJob
  queue_as :medium

  MAX_AGE = 10.seconds
  CHANNEL_TIMEOUT_SECONDS = 3
  OFF_MARK_TTL_SECONDS = 60

  # Chave própria do fork: lib/redis/redis_keys.rb é do Chatwoot oficial.
  def self.last_off_key(conversation_id)
    "channel_typing:last_off:#{conversation_id}"
  end

  def perform(conversation, typing_status, requested_at)
    remember_off(conversation, requested_at) if typing_status == 'off'
    reason = drop_reason(conversation, typing_status, requested_at)
    return log_drop(conversation, typing_status, requested_at, reason) if reason

    Conversations::ChannelTyping::Deliverer.new(conversation: conversation, typing_status: typing_status, timeout: CHANNEL_TIMEOUT_SECONDS).perform
  end

  private

  def drop_reason(conversation, typing_status, requested_at)
    return 'stale' if requested_at < MAX_AGE.ago
    return unless typing_status == 'on'
    return 'already_replied' if replied_since?(conversation, requested_at)

    'superseded' if stopped_since?(conversation, requested_at)
  end

  def replied_since?(conversation, requested_at)
    conversation.messages.outgoing.exists?(private: false, created_at: requested_at..)
  end

  def stopped_since?(conversation, requested_at)
    last_off = ::Redis::Alfred.get(self.class.last_off_key(conversation.id))
    last_off.present? && last_off.to_f > requested_at.to_f
  rescue Redis::BaseError => e
    log_redis_failure(conversation, e)
    false
  end

  def remember_off(conversation, requested_at)
    ::Redis::Alfred.setex(self.class.last_off_key(conversation.id), requested_at.to_f, OFF_MARK_TTL_SECONDS)
  rescue Redis::BaseError => e
    log_redis_failure(conversation, e)
  end

  def log_redis_failure(conversation, error)
    Rails.logger.warn("[channel_typing] off mark unavailable conversation=#{conversation.id} #{error.class}")
  end

  def log_drop(conversation, typing_status, requested_at, reason)
    age = (Time.current - requested_at).round
    Rails.logger.info("[channel_typing] dropped conversation=#{conversation.id} status=#{typing_status} reason=#{reason} age_seconds=#{age}")
  end
end
