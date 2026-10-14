# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473, P4): quem cria pela API uma mensagem de
# WhatsApp com 2 ou mais anexos recebe 422 com o motivo, e nada é gravado. Nota privada e mensagem de entrada não vão
# ao canal e são criadas como sempre. Ver RichMessages::AttachmentLimit.
# Entra como before_action, sem sobrescrever `create`: o Guia da Plataforma lê o formato da ação no método original.
module RichMessages::AttachmentLimitCheck
  def self.prepended(controller)
    controller.before_action :reject_attachments_over_limit, only: :create
  end

  private

  def reject_attachments_over_limit
    error = RichMessages::AttachmentLimit.error_for(@conversation.inbox, Array(params[:attachments]).size)
    render_could_not_create_error(error) if error && RichMessages.goes_to_channel?(attachment_limit_draft)
  end

  # Tipo e privacidade como o Messages::MessageBuilder os lê, sem gravar: só o que decide se a mensagem vai ao canal.
  def attachment_limit_draft
    message_type = Message.message_types.key?(params[:message_type]) ? params[:message_type] : 'outgoing'
    Message.new(private: params[:private] || false, message_type: message_type)
  end
end
