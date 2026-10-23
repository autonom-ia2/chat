# Refaz todo dia a inscrição de cada caixa do Instagram nos campos de Channel::Instagram::SUBSCRIBED_FIELDS (#2113).
#
# A Meta guarda a lista de campos por conta conectada, e ela só era gravada na criação da caixa: um campo novo
# (como a edição) não chegava às caixas já conectadas, e uma inscrição derrubada não voltava sozinha. O POST
# substitui a lista inteira, então repetir é seguro. Token vencido ou revogado fica de fora (a caixa já pede
# reconexão). O log leva só o id do canal, nunca o token.
class Instagram::RenovarInscricaoJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    resultados = Channel::Instagram.where('expires_at > ?', Time.current).find_each.map { |channel| renovar(channel) }
    falhas = resultados.count(false)
    mensagem = "[#{self.class.name}] #{resultados.size - falhas} de #{resultados.size} caixas inscritas"
    falhas.zero? ? Rails.logger.info(mensagem) : Rails.logger.warn(mensagem)
  end

  private

  def renovar(channel)
    resposta = channel.renew_subscription
    return true if confirmada?(resposta)

    Rails.logger.warn("[#{self.class.name}] channel #{channel.id}: Meta recusou a inscrição (HTTP #{resposta.code})")
    false
  rescue StandardError => e
    Rails.logger.error("[#{self.class.name}] channel #{channel.id}: #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
    false
  end

  # O corpo é lido aqui: o tipo que a Meta declara na resposta nem sempre é application/json.
  def confirmada?(resposta)
    resposta.success? && JSON.parse(resposta.body.to_s)['success'] == true
  rescue JSON::ParserError, TypeError
    false
  end
end
