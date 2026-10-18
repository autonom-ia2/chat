# Tradução do e-mail pela IA da conta (#1786), fora da requisição: o HTML do e-mail vai e volta inteiro e passa dos
# 15 s do rack-timeout (o mesmo padrão 202 + job da auditoria de 29/09). Grava em `translations` e o update dispara o
# message.updated de sempre, que leva a tradução ao painel. Já traduzido para o idioma = não paga a IA de novo.
# Falha da IA = log com a classe do erro e o rastreador; a tela avisa quando a tradução não chega.
class ConversaCanal::TraduzirEmailJob < ApplicationJob
  queue_as :low

  def perform(message_id, idioma)
    message = Message.find_by(id: message_id)
    return if message.nil? || message.translations.to_h[idioma].present?

    texto = ConversaCanal::TraducaoDoEmail.new(message: message, target_language: idioma).texto
    return if texto.blank?

    message.update!(translations: message.translations.to_h.merge(idioma => texto))
  end
end
