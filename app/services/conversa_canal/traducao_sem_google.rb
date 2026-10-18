# Entra por cima do tradutor do Chatwoot (Integrations::GoogleTranslate::ProcessorService), sem editar o arquivo dele:
# com o Google ligado, nada muda; sem ele, a conversa de e-mail nova traduz pela IA da conta (#1786).
module ConversaCanal::TraducaoSemGoogle
  def perform
    resultado = super
    return resultado if resultado.present? || hook.present?
    return unless ConversaCanal::TraducaoDoEmail.aplica?(message)

    ConversaCanal::TraducaoDoEmail.new(message: message, target_language: target_language).texto
  end
end
