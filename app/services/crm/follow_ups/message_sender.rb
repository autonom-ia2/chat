class Crm::FollowUps::MessageSender
  Result = Struct.new(:status, :message, :error, keyword_init: true) do
    def self.sent(message)
      new(status: :sent, message: message)
    end

    def self.failed(error)
      new(status: :failed, error: error)
    end

    def self.skipped
      new(status: :skipped)
    end

    # O contato recusou mensagens ativas (chat#737). Não é falha: cada chamador encerra do seu jeito.
    def self.opted_out
      new(status: :opted_out, error: OPTED_OUT_REASON)
    end
  end

  OPTED_OUT_REASON = 'opt_out'.freeze
  # Follow-ups que a plataforma agenda sozinha em sequência; o resto é retorno combinado (#2048).
  CADENCE_SOURCES = %w[ai_followup service_reminder stage_automation].freeze
  # Gravado no metadata pelos runners de IA (nunca por follow-up manual): o texto livre sai pelo WhatsApp API
  # do Híbrido, fora das 24h (chat#1349). O envio só obedece se o Híbrido continuar pronto neste momento.
  AI_SOURCES = %w[ai_followup ai_callback service_reminder].freeze
  TRANSPORT_KEY = 'delivery_transport'.freeze
  WHATSAPP_API_TRANSPORT = 'whatsapp_api'.freeze
  WHATSAPP_API_UNAVAILABLE = 'whatsapp_api_unavailable'.freeze

  def initialize(follow_up:)
    @follow_up = follow_up
  end

  def perform
    return Result.skipped unless deliverable?
    return Result.opted_out if contact_opted_out?

    precondition_error = delivery_precondition_error
    return delivery_failure(precondition_error) if precondition_error

    message = deliver_message!
    persist_sent_message!(message)
    Result.sent(message)
  rescue StandardError => e
    Result.failed(e.message)
  end

  def delivery_precondition_error
    return Crm::FollowUps::SendFailure::CONVERSATION_REQUIRED if @follow_up.conversation.blank?
    return Crm::FollowUps::SendFailure::NOT_WHATSAPP_CAPABLE unless whatsapp_window.whatsapp_capable?
    return Crm::FollowUps::SendFailure::SENDER_REQUIRED if sender.blank?

    # Nunca cai para template quando o texto era livre pelo WhatsApp API: falha clara e o runner recompõe.
    WHATSAPP_API_UNAVAILABLE if whatsapp_api_requested? && !whatsapp_api_available?
  end

  def deliverable?
    @follow_up.auto_send_message? && sent_message_id.blank?
  end

  # Relido do banco a cada envio: a recusa pode ter sido gravada depois de o follow-up ser agendado.
  def contact_opted_out?
    contact_id = @follow_up.conversation&.contact_id || @follow_up.contact_id
    contact_id.present? && Contact.opted_out.exists?(id: contact_id)
  end

  def deliver_message!
    conversation = @follow_up.conversation
    return create_session_message(conversation, sender) if whatsapp_window.can_send_session_message? || whatsapp_api_requested?

    create_template_message(conversation, sender)
  end

  # Texto livre pelo WhatsApp API do Híbrido, por duas vias que nunca leem valor do cliente:
  # - IA: os runners gravam o transporte no metadata; só a origem de IA o honra, então metadata arbitrária de um
  #   follow-up manual pela API não vira WhatsApp API.
  # - Equipe (manual ou etapa do funil): sem modelo, fora das 24h, em caixa com Híbrido. Deriva do estado de agora,
  #   não de uma marca gravada, e vale também para o follow-up criado dentro da janela que venceu fora dela.
  def whatsapp_api_requested?
    return @whatsapp_api_requested if defined?(@whatsapp_api_requested)

    @whatsapp_api_requested = ai_whatsapp_api_requested? || team_whatsapp_api_requested?
  end

  def ai_whatsapp_api_requested?
    AI_SOURCES.include?(metadata['source']) && metadata[TRANSPORT_KEY] == WHATSAPP_API_TRANSPORT
  end

  def team_whatsapp_api_requested?
    return false if AI_SOURCES.include?(metadata['source'])
    # Mesma regra do AutoSendValidator (nome E idioma): nome sozinho não conta como modelo configurado, senão
    # os dois lados divergem e o sender tenta o caminho de template com idioma vazio (achado da revisão).
    return false if Crm::FollowUps::MetadataSanitizer.native_template_configured?(metadata)

    whatsapp_window.hybrid_configured? && !whatsapp_window.can_send_session_message?
  end

  def whatsapp_api_available?
    whatsapp_window.can_send_session_message? || whatsapp_window.hybrid_web_available?
  end

  def delivery_failure(error)
    Result.failed(error)
  end

  def sender
    @sender ||= @follow_up.created_by || @follow_up.assignee
  end

  def whatsapp_window
    @whatsapp_window ||= Crm::FollowUps::MessagingWindow.new(@follow_up.conversation)
  end

  private

  def create_session_message(conversation, sender)
    Messages::MessageBuilder.new(
      sender,
      conversation,
      ActionController::Parameters.new(
        content: metadata['message_body'].to_s.strip,
        private: false,
        content_attributes: session_content_attributes
      )
    ).perform
  end

  def session_content_attributes
    # Só marca o transporte quando o texto realmente depende do Híbrido (a janela oficial pode ter reaberto até o envio).
    return follow_up_marks unless whatsapp_api_requested? && !whatsapp_window.can_send_session_message?

    follow_up_marks.merge(crm_follow_up_transport: WHATSAPP_API_TRANSPORT)
  end

  def create_template_message(conversation, sender)
    inbox = conversation.inbox
    if inbox.channel_type == 'Channel::Api'
      create_api_template_message(conversation, sender)
    else
      create_native_template_message(conversation, sender)
    end
  end

  def create_api_template_message(conversation, sender)
    template = load_api_template!(conversation)
    contact = conversation.contact
    rendered_body = WhatsappApiCampaigns::TemplateRenderer.new(
      template: template.body,
      contact: contact,
      variables: template_variables
    ).render

    # Already filled by TemplateRenderer: contact values stay literal (chat#1021).
    Autonomia::LiteralMessageBuilder.new(
      sender,
      conversation,
      ActionController::Parameters.new(
        content: rendered_body,
        private: false,
        content_attributes: follow_up_marks.merge(
          crm_follow_up_template_id: template.id,
          crm_follow_up_send_mode: 'template'
        )
      ),
      literal_content: true
    ).perform
  end

  def create_native_template_message(conversation, sender)
    # O JSON schema do Message exige a CHAVE 'name', mas string vazia passa. E o AutoSendValidator
    # pula a checagem de template para follow-up de IA (no create-time o template ainda não foi
    # escolhido). Sem esta barreira, um nome vazio viraria chamada inválida na API da Meta em vez de
    # erro nosso. Vira Result.failed pelo rescue do #perform, com motivo legível.
    raise Crm::FollowUps::SendFailure::TEMPLATE_NAME_REQUIRED if metadata['template_name'].to_s.strip.blank?

    # processed_params are final values written by the AI composer (template_processed_params), so they
    # stay literal (chat#1021). message_body keeps the Liquid pass: a person may have written it.
    Autonomia::LiteralMessageBuilder.new(
      sender,
      conversation,
      ActionController::Parameters.new(
        content: metadata['message_body'].to_s.strip.presence,
        private: false,
        template_params: native_template_params,
        content_attributes: follow_up_marks.merge(crm_follow_up_send_mode: 'template')
      ),
      literal_template_params: true
    ).perform
  end

  # A marca do follow-up em toda mensagem que ele manda. `crm_follow_up_origem` (#2048) diz ao painel o nome do balão:
  # 'follow_up' ("Follow-up automático") para a cadência que a plataforma monta sozinha (IA, lembrete de serviço,
  # automação de etapa); 'retorno' ("Retorno automático") para o retorno combinado, pela IA ou marcado por uma pessoa.
  def follow_up_marks
    origem = CADENCE_SOURCES.include?(metadata['source']) ? 'follow_up' : 'retorno'
    { crm_follow_up_id: @follow_up.id, crm_follow_up_origem: origem }
  end

  def load_api_template!(conversation)
    template_id = metadata['whatsapp_api_message_template_id'].presence
    raise Crm::FollowUps::SendFailure::API_TEMPLATE_REQUIRED if template_id.blank?

    template = @follow_up.account.whatsapp_api_message_templates.active.find_by(id: template_id, inbox_id: conversation.inbox_id)
    raise Crm::FollowUps::SendFailure::API_TEMPLATE_INVALID if template.blank?

    template
  end

  # A chave `namespace` é OMITIDA quando não há valor, em vez de ir como nil. O TEMPLATE_PARAMS_SCHEMA
  # do Message declara namespace como 'string' e exige só 'name'; mandar nil reprova a validação com
  # "Template params/namespace must be of type string" e derruba o envio inteiro. Namespace só existe
  # na API on-premise do WhatsApp — nada no follow-up preenche `template_namespace`, então ele nunca
  # era string e TODO envio por template morria aqui (104 falhas numa conta de produção entre 07 e
  # 08/2026, com o template certo já escolhido pela IA).
  def native_template_params
    params = {
      name: metadata['template_name'].to_s.strip,
      language: metadata['template_language'].to_s.strip,
      processed_params: template_variables
    }
    namespace = metadata['template_namespace'].to_s.strip
    params = params.merge(namespace: namespace) if namespace.present?
    # #1498: o modelo escolhido pelo Garantir vai com a categoria, como o contrato do upstream pede.
    category = metadata['template_params_category'].to_s.strip
    category.present? ? params.merge(category: category) : params
  end

  # Slot values composed by the AI follow-up composer (keys "1", "2", …). On the
  # native WhatsApp path these become the template's positional processed_params;
  # on the Channel::Api path they feed TemplateRenderer's named-variable lookup
  # (TemplateRenderer still ignores anything it does not support). Returns {} for
  # plain auto-send follow-ups that carry no template variables.
  def template_variables
    metadata['template_processed_params'].presence&.to_h || {}
  end

  def persist_sent_message!(message)
    updated_metadata = metadata.merge(
      'sent_message_id' => message.id,
      'sent_at' => Time.current.iso8601,
      'send_mode' => message.content_attributes.to_h['crm_follow_up_send_mode'] || 'session'
    )
    @follow_up.update!(metadata: updated_metadata)
  end

  def sent_message_id
    metadata['sent_message_id']
  end

  def metadata
    @metadata ||= (@follow_up.metadata || {}).to_h.stringify_keys
  end
end
