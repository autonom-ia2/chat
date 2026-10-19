# Por cima do ConversationReplyMailer (#1786): o encaminhado da conversa de e-mail nova sai como e-mail novo para quem
# recebe, com "Enc: <assunto>" e sem In-Reply-To/References do fio do cliente (a pesquisa D.4 pedia assunto próprio).
# Os anexos do original já vêm na mensagem (ConversaCanal::MessageBuilderComCitacao). Fora do encaminhado, nada muda.
module ConversaCanal::EncaminhadoNoMailer
  private

  def mail_subject
    encaminhado_do_email_novo? ? citacao_encaminhada.assunto_do_encaminhado : super
  end

  def in_reply_to_email
    encaminhado_do_email_novo? ? nil : super
  end

  def references_header
    encaminhado_do_email_novo? ? nil : super
  end

  def encaminhado_do_email_novo?
    @message.present? && @account.feature_enabled?('conversa_email_nova') && citacao_encaminhada.encaminhado? &&
      citacao_encaminhada.valida?
  end

  def citacao_encaminhada
    @citacao_encaminhada ||= ConversaCanal::CitacaoDoEmail.new(
      conversation: @conversation, pedido: @message.content_attributes.to_h.with_indifferent_access[:email_citacao]
    )
  end
end
