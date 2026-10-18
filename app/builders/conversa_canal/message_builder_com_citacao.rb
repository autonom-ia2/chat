# Por cima do Messages::MessageBuilder do Chatwoot (#1786), na resposta de e-mail:
# - histórico ou encaminhado (`content_attributes.email_citacao`): o trecho citado de ConversaCanal::CitacaoDoEmail
#   entra depois do texto do atendente;
# - modelo de e-mail das Campanhas (`content_attributes.email_modelo`): o HTML do modelo vira o corpo, com o texto do
#   atendente no começo e o histórico no fim (ConversaCanal::ModeloNaResposta).
# Os dois envios (SMTP e caixas Microsoft/Google) já usam `email.html_content.reply` quando ele existe, então nenhum
# deles muda. Sem os pedidos, tudo como antes.
module ConversaCanal::MessageBuilderComCitacao
  private

  # Depois de montar o e-mail, o HTML do modelo (até 500 mil caracteres) não fica guardado de novo no pedido: a mensagem
  # já o tem em `email.html_content`. Fica só qual modelo foi usado.
  def process_email_content
    super
    pedido = pedidos_do_email[:email_modelo]
    return if pedido.blank?

    atributos = (@message.content_attributes || {}).with_indifferent_access
    @message.content_attributes = atributos.merge(email_modelo: pedido.to_h.with_indifferent_access.slice(:template_id, :so_modelo))
  end

  def build_html_content(normalized_content)
    html_content = super
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
    partes = []
    partes << text_content[:reply] unless modelo_na_resposta.valido? && modelo_na_resposta.so_modelo?
    partes << modelo_na_resposta.texto if modelo_na_resposta.valido?
    completo = partes.join("\n\n") + (citacao_do_email.valida? ? citacao_do_email.texto : '')
    text_content.merge(full: completo, reply: completo)
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
