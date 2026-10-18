# Por cima do Messages::MessageBuilder do Chatwoot (#1786): quando a resposta de e-mail pede histórico ou encaminhado
# (`content_attributes.email_citacao`), o HTML e o texto do e-mail ganham o trecho citado montado por
# ConversaCanal::CitacaoDoEmail. Os dois envios (SMTP e caixas Microsoft/Google) já usam `email.html_content.reply`
# quando ele existe, então nenhum deles muda. Sem o pedido, tudo como antes.
module ConversaCanal::MessageBuilderComCitacao
  private

  def build_html_content(normalized_content)
    html_content = super
    return html_content unless citacao_do_email.valida?

    completo = "#{html_content[:reply]}#{citacao_do_email.html}"
    html_content.merge(full: completo, reply: completo)
  end

  def build_text_content(normalized_content)
    text_content = super
    return text_content unless citacao_do_email.valida?

    completo = "#{text_content[:reply]}#{citacao_do_email.texto}"
    text_content.merge(full: completo, reply: completo)
  end

  def citacao_do_email
    @citacao_do_email ||= ConversaCanal::CitacaoDoEmail.new(
      conversation: @conversation,
      pedido: (@message.content_attributes || {}).with_indifferent_access[:email_citacao]
    )
  end
end
