# Reação do atendente pela caixa WhatsApp API (WAHA), #1702: PUT /api/reaction { session, messageId, reaction }.
# Reação vazia tira a do número. Sem janela de 24 h (não é a API oficial) e vale para recebida ou enviada, como no app.
#
# O messageId do WAHA é "<fromMe>_<chatId>_<id>" (ex.: true_5511999999999@c.us_3EB0…). Quando o source_id da mensagem
# já vem nesse formato, vai como está; quando vem só o id, o messageId é montado com o chat id do contato
# (Waha::ContactChatId) e o lado da mensagem (enviada = true).
class ConversaCanal::ReacaoNoWaha
  LADOS = %w[true_ false_].freeze

  # Sem `client:`, o do motor da caixa (ConversaCanal::ClienteDoMotor, #1709).
  def initialize(message:, client: nil)
    @message = message
    @client = client || ConversaCanal::ClienteDoMotor.para(message.inbox.channel)
  end

  def validar!
    recusar!(:caixa_desconectada) if sessao.blank?
    recusar!(:sem_identificacao) if message_id.blank?
  end

  def enviar(emoji)
    @client.set_reaction(session: sessao, message_id: message_id, reaction: emoji)
  rescue Waha::Client::Error => e
    # A mensagem do erro do cliente traz URL e corpo: no log, só a classe e o status.
    Rails.logger.warn("[conversa_canal][reacao] waha refused message=#{@message.id} #{e.class} status=#{e.status}")
    recusar!(e.is_a?(Waha::Client::Timeout) ? :provedor_fora : :waha_recusou)
  end

  private

  def sessao
    @message.inbox.channel.additional_attributes.to_h['session'].presence
  end

  def message_id
    return @message_id if defined?(@message_id)

    @message_id = montar_message_id
  end

  def montar_message_id
    source_id = @message.source_id.to_s
    return if source_id.blank?
    return source_id if LADOS.any? { |lado| source_id.start_with?(lado) }

    chat_id = Waha::ContactChatId.primary(@message.conversation.contact, contact_inbox: @message.conversation.contact_inbox)
    return if chat_id.blank?

    "#{@message.outgoing?}_#{chat_id}_#{source_id}"
  end

  def recusar!(codigo)
    raise ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t("conversa_canal.reacoes.#{codigo}")
  end
end
