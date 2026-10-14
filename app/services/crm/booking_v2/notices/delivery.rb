# Envia uma mensagem automática do agendamento pelo caminho que o `Notices::Route` decidiu (#1192). Sem conversa
# (só no caminho de modelo), abre uma na caixa de avisos para o contato (`ContactInbox` + `ConversationBuilder`).
# Pelo WhatsApp Híbrido (`decision.via == :hybrid_web`, #1349) a mensagem fica marcada em `crm_booking_notice_via`
# para auditoria — essa marca só reflete a decisão no momento do envio: se o cliente responder antes de o job de
# conferência de entrega rodar, ela pode já estar desatualizada para quem a lê depois. A origem que o roteador do
# Híbrido dá à mensagem (`automation` com remetente ausente, `human` com usuário) é escolha de quem chama (`sender:`):
# o aviso automático do `Notices::Sender` manda sem remetente; o "Testar no meu WhatsApp" (`TestInvite`) manda com o
# usuário, porque é uma ação manual do atendente.
# Texto já pronto: sai literal (`LiteralMessageBuilder`, sem a passada de Liquid). Botão "Ver meu horário" (#1517): o
# `rich_message` que `Notices::Button` liberou vai em `content_attributes` só no caminho `:session`. `marks` (#1562):
# marcas a mais em `content_attributes`, como as da mensagem 2 do aviso com botão (`crm_booking_notice_part: 'stop'` e
# `crm_booking_notice_id`), que o `NoticeDispatchJob` usa para conferir a entrega dela.
#
# Modelo da Meta: variáveis posicionais do corpo {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão; só as
# que o corpo do modelo usa. Modelo do canal API: o corpo do modelo (com as variáveis de contato) mais o dia, o link
# de gestão e a linha de parar.
class Crm::BookingV2::Notices::Delivery
  PLACEHOLDER_COUNT = 3

  # values: os três valores do modelo (ver `Notices::Text#template_values`); appendix: o que vai depois do corpo do
  # modelo do canal API; rich_message: o do botão (`Notices::Text#rich_message`), ou nil; marks: marcas a mais na mensagem.
  def initialize(decision:, inbox:, contact:, sender:, content:, values: [], appendix: nil, rich_message: nil, marks: {}) # rubocop:disable Metrics/ParameterLists
    @decision = decision
    @inbox = inbox
    @contact = contact
    @sender = sender
    @content = content
    @values = values
    @appendix = appendix
    @rich_message = rich_message
    @marks = marks
  end

  def perform
    conversation = decision.conversation || open_conversation!
    case decision.mode
    when :session then build(conversation, content: @content, rich_message: @rich_message)
    when :native_template then build(conversation, content: native_content, template_params: native_params)
    when :api_template then build(conversation, content: api_content)
    end
  end

  private

  attr_reader :decision, :inbox, :contact, :sender

  def open_conversation!
    contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
                    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: nil).perform
    ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end

  def build(conversation, content:, template_params: nil, rich_message: nil)
    attributes = { crm_booking_notice: true }.merge(@marks)
    attributes[:crm_booking_notice_via] = decision.via.to_s if decision.via
    attributes[RichMessages::KEY] = rich_message if rich_message
    params = { content: content, private: false, message_type: 'outgoing', content_attributes: attributes }
    params[:template_params] = template_params if template_params
    Autonomia::LiteralMessageBuilder.new(sender, conversation, ActionController::Parameters.new(params),
                                         literal_content: true, literal_template_params: template_params.present?).perform
  end

  def native_body
    Crm::BookingV2::Notices::Route.native_body(decision.template)
  end

  def used_positions
    (1..PLACEHOLDER_COUNT).select { |position| native_body.include?("{{#{position}}}") }
  end

  def native_params
    body = used_positions.to_h { |position| [position.to_s, @values[position - 1].to_s] }
    { name: decision.template['name'], language: decision.template['language'], processed_params: { body: body } }
  end

  # O que o painel mostra: o corpo do modelo com os valores no lugar (troca de string, sem regex).
  def native_content
    used_positions.reduce(native_body) { |text, position| text.gsub("{{#{position}}}") { @values[position - 1].to_s } }
  end

  def api_content
    rendered = WhatsappApiCampaigns::TemplateRenderer.new(template: decision.template.body, contact: contact).render
    [rendered, @appendix].compact_blank.join("\n\n")
  end
end
