# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473, P4): quem cria pela API uma mensagem de
# WhatsApp com 2 ou mais anexos recebe 422 com o motivo, e nada é gravado. Nota privada, mensagem de entrada e modelo
# são criados como sempre; o pedido da integração MCP segue o caminho próprio, como no RichMessages::CreationCheck.
# Ver RichMessages::AttachmentLimit.
# Entra como before_action, sem sobrescrever `create`: o Guia da Plataforma lê o formato da ação no método original.
module RichMessages::AttachmentLimitCheck
  def self.prepended(controller)
    controller.before_action :reject_attachments_over_limit, only: :create
  end

  private

  def reject_attachments_over_limit
    return if mcp_integration_token_request?

    error = RichMessages::AttachmentLimit.error_for(Array(params[:attachments]).size)
    render_could_not_create_error(error) if error && RichMessages::AttachmentLimit.checked?(attachment_limit_draft)
  end

  # A mensagem como o builder a montaria, sem gravar: caixa, tipo e privacidade (pela mesma leitura do
  # RichMessages::CreationCheck#requested_kind) e a marca de modelo.
  def attachment_limit_draft
    draft = Message.new(inbox: @conversation.inbox, **requested_kind)
    draft.additional_attributes = { 'template_params' => true } if params[:template_params].present?
    draft
  end
end
