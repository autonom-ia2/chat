# Callback `before_create` de Message (#1941, item 3). Resposta que o atendente manda pelo app do celular numa caixa
# WAHA comum volta pelo conector como eco (`external_echo`), com o texto começando por "*📱 Enviado do WhatsApp*" e uma
# linha em branco. Regra do Rodrigo, igual nos três WhatsApp (WAHA comum, híbrido e oficial com coexistência):
# - o texto fica sem esse prefixo (a tela põe um 📱 pequeno ao lado da hora);
# - `c2y_phone_author_id` guarda quem estava atribuído à conversa NA HORA em que o eco chegou (ou null, sem
#   atribuição). A tela mostra esse nome em cima do balão; reatribuir depois não muda as antigas.
# O remetente continua o dono do token do conector: relatórios e o histórico da IA contam o eco por ele.
# Só o conector (Waha::RichNative::Inbound.from_connector?): um agente não grava autor em mensagem pela API.
class Waha::EcoDoCelular
  PREFIXO = '*📱 Enviado do WhatsApp*'.freeze
  QUEBRAS = ["\r\n", "\n"].freeze
  CHAVE = 'c2y_phone_author_id'.freeze

  def self.before_create(message)
    return unless eco_do_conector?(message)

    message.content_attributes = message.content_attributes.to_h.merge(CHAVE => message.conversation&.assignee_id)
    tirar_prefixo!(message)
  rescue StandardError => e
    Rails.logger.error("[waha] eco do celular #{e.class}")
  end

  def self.eco_do_conector?(message)
    message.outgoing? && message.content_attributes.to_h['external_echo'].present? &&
      Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative::Inbound.from_connector?(message)
  end

  def self.tirar_prefixo!(message)
    return unless message.content.is_a?(String) && message.content.start_with?(PREFIXO)

    message.content = sem_prefixo(message.content).presence
    message.send(:ensure_processed_message_content)
  end

  # Tira o prefixo e as quebras de linha logo depois dele; o resto do texto fica igual.
  def self.sem_prefixo(texto)
    resto = texto.delete_prefix(PREFIXO)
    while (quebra = QUEBRAS.find { |candidata| resto.start_with?(candidata) })
      resto = resto.delete_prefix(quebra)
    end
    resto
  end
end
