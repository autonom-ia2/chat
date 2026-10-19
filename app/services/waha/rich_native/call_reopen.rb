# Prepend em Message (chat#1709, decisão do Rodrigo de 17/10/2026, "REabre sim"): a ligação perdida ou recusada do
# cliente na caixa WAHA comum com a flag `whatsapp_rich_native` reabre a conversa resolvida (e tira do adiamento), igual
# a uma mensagem nova do cliente. É uma atividade (Waha::RichNative::Inbound::Call: a linha da ligação, ou o desfecho
# escondido), e a reabertura do Chatwoot (Message#reopen_conversation, com o Crm::Entrega::Reabertura do fork) só olha
# mensagem recebida. Aqui ela roda pelo MESMO caminho, sem copiar a regra: só durante `reopen_conversation`, a
# atividade da ligação conta como recebida. A IA continua sem responder (o MessageListener só ouve mensagem recebida, e
# a mensagem continua atividade no banco). Uma ligação (call_id) reabre uma vez só: o mesmo desfecho repetido pelo motor
# (retry, evento duplicado) não reabre a conversa que a equipe resolveu de novo (marca no Redis, com TTL). Redis fora:
# reabre (melhor reabrir a mais que perder a ligação). Sem a flag, ou outra atividade: como na main.
module Waha::RichNative::CallReopen
  REOPENING_OUTCOMES = %w[missed rejected].freeze
  DEDUP_TTL = 7.days.to_i

  def self.reopens?(message)
    summary = message.content_attributes.to_h[Waha::RichNative::Inbound::Call::SUMMARY_KEY]
    message.activity? && summary.is_a?(Hash) && REOPENING_OUTCOMES.include?(summary['outcome']) && summary['ended'] != true &&
      Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(message.account)
  end

  # Primeira vez que esta ligação reabre (marca SET NX por caixa e call_id).
  def self.first_time?(message)
    call_id = message.content_attributes.to_h.dig(Waha::RichNative::Inbound::Call::SUMMARY_KEY, 'call_id')
    ::Redis::Alfred.set("waha:call_reopen:#{message.inbox_id}:#{call_id}", '1', nx: true, ex: DEDUP_TTL) ? true : false
  rescue Redis::BaseError => e
    Rails.logger.error("[waha] rich native call reopen mark failed message=#{message.id} #{e.class}")
    true
  end

  def incoming?
    @c2y_call_reopening == true || super
  end

  private

  def reopen_conversation
    return super unless Waha::RichNative::CallReopen.reopens?(self) && Waha::RichNative::CallReopen.first_time?(self)

    @c2y_call_reopening = true
    super
  ensure
    @c2y_call_reopening = false
  end
end
