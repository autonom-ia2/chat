# Envia uma mensagem automática do agendamento pelo caminho que o `Notices::Route` decidiu (#1192). Sem conversa
# (só no caminho de modelo), abre uma na caixa de avisos para o contato (`ContactInbox` + `ConversationBuilder`).
# Texto já pronto: sai literal (`LiteralMessageBuilder`, sem a passada de Liquid).
#
# Modelo da Meta: variáveis posicionais do corpo {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão; só as
# que o corpo do modelo usa. Modelo do canal API: o corpo do modelo (com as variáveis de contato) mais o dia, o link
# de gestão e a linha de parar.
class Crm::BookingV2::Notices::Delivery
  PLACEHOLDER_COUNT = 3

  # values: os três valores do modelo (ver `Notices::Text#template_values`); appendix: o que vai depois do corpo do
  # modelo do canal API.
  def initialize(decision:, inbox:, contact:, sender:, content:, values: [], appendix: nil) # rubocop:disable Metrics/ParameterLists
    @decision = decision
    @inbox = inbox
    @contact = contact
    @sender = sender
    @content = content
    @values = values
    @appendix = appendix
  end

  def perform
    conversation = decision.conversation || open_conversation!
    case decision.mode
    when :session then build(conversation, content: @content)
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

  def build(conversation, content:, template_params: nil)
    params = { content: content, private: false, message_type: 'outgoing', content_attributes: { crm_booking_notice: true } }
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
