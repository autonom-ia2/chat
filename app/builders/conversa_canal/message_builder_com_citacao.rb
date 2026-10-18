# Por cima do Messages::MessageBuilder do Chatwoot (#1786), na resposta de e-mail:
# - histórico ou encaminhado (`content_attributes.email_citacao`): o trecho citado de ConversaCanal::CitacaoDoEmail
#   entra depois do texto do atendente; o encaminhado leva também os anexos do original;
# - modelo de e-mail das Campanhas (`content_attributes.email_modelo`): o HTML do modelo vira o corpo, com o texto do
#   atendente no começo e o histórico no fim (ConversaCanal::ModeloNaResposta). Modelo sem texto também é conteúdo.
# Os dois envios (SMTP e caixas Microsoft/Google) já usam `email.html_content.reply` quando ele existe, então nenhum
# deles muda. Sem os pedidos, ou com a chave `conversa_email_nova` desligada, tudo como antes.
module ConversaCanal::MessageBuilderComCitacao
  private

  # Encaminhar sem Para iria para o próprio cliente (o envio cai no contato da conversa): recusa antes de gravar.
  def process_emails
    super
    return unless email_novo? && encaminhado? && @message.content_attributes[:to_emails].blank?

    raise ArgumentError, I18n.t('conversa_canal.email.encaminhar_sem_para')
  end

  def process_attachments
    @attachments = Array(@attachments) + citacao_do_email.anexos_assinados if email_novo? && encaminhado?
    super
  end

  def should_process_email_content?
    super || (email_novo? && email_inbox? && !@private && modelo_na_resposta.valido?)
  end

  # Depois de montar o e-mail, o HTML do modelo (até 500 mil caracteres) não fica guardado de novo no pedido: a mensagem
  # já o tem em `email.html_content`. Fica só qual modelo foi usado.
  def process_email_content
    super
    pedido = pedidos_do_email[:email_modelo]
    return if !email_novo? || pedido.blank?

    atributos = (@message.content_attributes || {}).with_indifferent_access
    @message.content_attributes = atributos.merge(email_modelo: pedido.to_h.with_indifferent_access.slice(:template_id, :so_modelo))
  end

  def build_html_content(normalized_content)
    html_content = super
    return html_content unless email_novo?

    citacao = citacao_do_email.valida? ? citacao_do_email.html : ''
    completo = if modelo_na_resposta.valido?
                 modelo_na_resposta.html(texto_html: html_content[:reply], citacao_html: citacao)
               else
                 "#{html_content[:reply]}#{citacao}"
               end
    html_content.merge(full: completo, reply: completo)
  end

  def build_text_content(normalized_content)
    text_content = super
    return text_content unless email_novo?

    partes = []
    partes << text_content[:reply] unless modelo_na_resposta.valido? && modelo_na_resposta.so_modelo?
    partes << modelo_na_resposta.texto if modelo_na_resposta.valido?
    completo = partes.compact_blank.join("\n\n") + (citacao_do_email.valida? ? citacao_do_email.texto : '')
    text_content.merge(full: completo, reply: completo)
  end

  def email_novo?
    return @email_novo if defined?(@email_novo)

    @email_novo = @conversation.inbox&.email? && @conversation.account.feature_enabled?('conversa_email_nova')
  end

  def encaminhado?
    citacao_do_email.encaminhado?
  end

  def citacao_do_email
    @citacao_do_email ||= ConversaCanal::CitacaoDoEmail.new(conversation: @conversation, pedido: pedidos_do_email[:email_citacao])
  end

  def modelo_na_resposta
    @modelo_na_resposta ||= ConversaCanal::ModeloNaResposta.new(account: @conversation.account, pedido: pedidos_do_email[:email_modelo])
  end

  def pedidos_do_email
    (@message.content_attributes || {}).with_indifferent_access
  end
end
