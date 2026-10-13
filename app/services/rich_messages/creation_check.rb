# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473): quem cria a mensagem pela API
# sabe na hora que errou o formato. `rich_message` que nunca poderia sair (RichMessages.format_error, a mesma
# regra da trava do envio) responde 422 com o motivo, e a mensagem não é criada. Só para o que iria ao canal:
# nota privada e mensagem de entrada são criadas como sempre. A trava do envio continua valendo para quem cria
# a mensagem sem passar por aqui (o agente nativo). O caminho MCP não aceita `content_attributes` e segue como era.
# Entra como before_action, sem sobrescrever `create`: o Guia da Plataforma lê o formato da ação no método
# original (lib/operator_guide/formatos-das-acoes.json) e perderia os campos dela.
module RichMessages::CreationCheck
  def self.prepended(controller)
    controller.before_action :reject_invalid_rich_message, only: :create
  end

  private

  def reject_invalid_rich_message
    return if params[:content_attributes].blank?

    content_attributes = requested_content_attributes
    return unless content_attributes.key?(RichMessages::KEY) && !mcp_integration_token_request?

    draft = rich_message_draft(content_attributes)
    error = RichMessages.format_error(draft) if RichMessages.goes_to_channel?(draft)
    render_could_not_create_error(error) if error
  end

  # A mensagem como o Messages::MessageBuilder a montaria, sem gravar: só o que a regra do formato lê.
  def rich_message_draft(content_attributes)
    draft = Message.new(account: @conversation.account, inbox: @conversation.inbox, conversation: @conversation,
                        content: params[:content], content_attributes: content_attributes, **requested_kind)
    draft.additional_attributes = { 'template_params' => true } if params[:template_params].present?
    draft.attachments.build if params[:attachments].present?
    draft
  end

  # Tipo, privacidade e formato de conteúdo como o builder os lê; valor que o modelo não conhece fica no padrão.
  def requested_kind
    kind = { private: params[:private] || false, message_type: 'outgoing' }
    kind[:message_type] = params[:message_type] if Message.message_types.key?(params[:message_type])
    kind[:content_type] = params[:content_type] if Message.content_types.key?(params[:content_type])
    kind
  end

  # O builder aceita `content_attributes` como objeto ou como JSON em texto (envio com arquivo).
  def requested_content_attributes
    raw = params[:content_attributes]
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw = raw.to_unsafe_h if raw.is_a?(ActionController::Parameters)
    raw.is_a?(Hash) ? raw : {}
  rescue JSON::ParserError
    {}
  end
end
