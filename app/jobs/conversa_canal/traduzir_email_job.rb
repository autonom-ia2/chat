# Tradução do e-mail pela IA da conta (#1786), fora da requisição: o HTML do e-mail vai e volta inteiro e passa dos
# 15 s do rack-timeout (o mesmo padrão 202 + job da auditoria de 29/09). Grava em `translations` e o update dispara o
# message.updated de sempre, que leva a tradução ao painel. Já traduzido para o idioma = não paga a IA de novo.
# Falha da IA = log com a classe do erro e o rastreador; a tela avisa quando a tradução não chega.
# Uma tradução por vez para cada mensagem e idioma: 30 cliques seguidos seriam 30 chamadas pagas. O pedido reserva
# (`reservar`, SET NX no Redis) e o job solta no fim; a trava vence sozinha se o job nunca rodar.
class ConversaCanal::TraduzirEmailJob < ApplicationJob
  queue_as :low

  TRAVA = 10.minutes

  def self.reservar(message_id, idioma)
    Redis::Alfred.set(trava(message_id, idioma), 1, nx: true, ex: TRAVA.to_i) ? true : false
  end

  def self.trava(message_id, idioma)
    "conversa_canal:traducao_do_email:#{message_id}:#{idioma}"
  end

  def perform(message_id, idioma)
    message = Message.find_by(id: message_id)
    return if message.nil? || message.translations.to_h[idioma].present?

    texto = ConversaCanal::TraducaoDoEmail.new(message: message, target_language: idioma).texto
    return if texto.blank?

    message.update!(translations: message.translations.to_h.merge(idioma => texto))
  ensure
    Redis::Alfred.delete(self.class.trava(message_id, idioma))
  end
end
