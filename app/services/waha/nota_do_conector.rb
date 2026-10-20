# Callback `before_create` de Message (#1941, item 2). Quando o conector do WAHA comum não consegue trazer uma mensagem
# do WhatsApp (3 tentativas), ele cria na conversa uma nota privada técnica: "⚠️ **Não foi possível receber uma
# mensagem do WhatsApp**", "Tentativa 3/3", o link do job no motor e "API Error 404". O atendente não entende e não tem
# o que fazer com ela. Decisão do Rodrigo (20/10): no lugar, uma linha curta e humana, como os avisos do próprio
# WhatsApp. A nota não diz de quem era a mensagem nem qual era, então a linha também não diz.
# - vira atividade (não privada): não vai ao webhook do conector nem ganha "Falha ao enviar";
# - o detalhe técnico (a linha "Detalhes:", com o job) vai só para o log;
# - só a nota que o próprio conector cria, na caixa WAHA comum (Waha::RichNative::Inbound.from_connector?).
# As notas antigas, já gravadas, a tela mostra do mesmo jeito (PR do Frontend geral).
class Waha::NotaDoConector
  PREFIXO = '⚠️ **Não foi possível receber uma mensagem do WhatsApp**'.freeze
  DETALHES = 'Detalhes:'.freeze
  TEXT_KEY = 'waha.receive_failed'.freeze

  def self.before_create(message)
    return unless nota_de_recebimento?(message)

    # Tudo calculado antes de mudar a mensagem: um erro aqui deixa a nota como veio, nunca meio trocada.
    texto = I18n.t(TEXT_KEY, locale: message.account.locale, default: I18n.t(TEXT_KEY))
    atributos = message.content_attributes.to_h.except('external_error')
    registrar(message)
    message.assign_attributes(message_type: :activity, private: false, content: texto, content_attributes: atributos)
    message.send(:ensure_processed_message_content)
  rescue StandardError => e
    Rails.logger.error("[waha] nota do conector #{e.class}")
  end

  def self.nota_de_recebimento?(message)
    message.outgoing? && message.private? && message.content.is_a?(String) && message.content.start_with?(PREFIXO) &&
      Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative::Inbound.from_connector?(message)
  end

  # Só o evento e o número do job no motor ("message.any => 583011"), nunca o link nem o resto da nota.
  def self.registrar(message)
    Rails.logger.warn("[waha] mensagem do WhatsApp não recebida account=#{message.account_id} inbox=#{message.inbox_id} " \
                      "conversation=#{message.conversation_id} job=#{job_do_motor(message.content)}")
  end

  def self.job_do_motor(content)
    detalhe = content.lines.map(&:strip).find { |linha| linha.start_with?(DETALHES) }
    return '?' unless detalhe

    detalhe.split('[', 2).last.to_s.split(']', 2).first.to_s.split('|', 2).last.to_s.strip.presence || '?'
  end
end
