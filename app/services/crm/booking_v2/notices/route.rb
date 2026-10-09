# Por onde (e se) uma mensagem automática do agendamento pode sair (#1192, PLANO §2.5). Só decide; quem envia é o
# `Notices::Delivery`. Regra por tipo de caixa de avisos:
#
# - WhatsApp oficial (Cloud/360dialog): janela de 24 h aberta pelo cliente (`MessagingWindow`) → texto; fora dela,
#   modelo APROVADO na Meta configurado para o aviso; sem modelo → `template_required`; modelo cujo corpo não leva o
#   `{{3}}` (link de gestão, onde fica o "Parar avisos", J2-A9/RA-18) → `template_without_link`; modelo que pede o que o
#   aviso não preenche (variável além de `{{1}}`..`{{3}}` no corpo, variável ou mídia no topo, botão com link variável:
#   a Meta recusaria) → `template_unsupported`.
# - WAHA (`MessagingWindow` o libera sempre, por isso regra própria): só com mensagem RECEBIDA do cliente nas últimas
#   24 h nesta caixa → texto; senão `waha_outside_window` (risco de bloqueio do número, J5-A5).
# - Canal API de campanhas (não WAHA): janela do canal → texto; fora dela, modelo do canal por id; senão
#   `template_required`.
#
# Conversa: a indicada (a do convite) quando é desta caixa e deste contato; senão a mais recente do contato nesta
# caixa; sem nenhuma, o modelo pode abrir uma nova (o `Delivery` cria). Sem conversa e sem modelo, o número digitado
# no link público não recebe mensagem automática (reduz abuso com número de terceiros).
class Crm::BookingV2::Notices::Route
  WAHA_WINDOW = 24.hours
  # Variável do corpo do modelo da Meta que recebe o link de gestão (`Notices::Delivery`).
  LINK_PLACEHOLDER = '{{3}}'.freeze
  # Variáveis do corpo que o aviso preenche: {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão.
  FILLED_VARIABLES = %w[1 2 3].freeze
  # Topo com mídia pede o arquivo no envio, que o aviso não manda.
  MEDIA_HEADERS = %w[IMAGE VIDEO DOCUMENT LOCATION].freeze

  Decision = Struct.new(:mode, :reason, :conversation, :template, keyword_init: true) do
    def send?
      reason.nil?
    end
  end

  # Texto do corpo de um modelo da Meta (item da lista sincronizada da caixa).
  def self.native_body(template)
    component = Array(template.to_h['components']).find { |item| item['type'].to_s.casecmp?('body') }
    component.to_h['text'].to_s
  end

  # O aviso consegue preencher o modelo: no corpo só {{1}}, {{2}} e {{3}}; no topo, só texto fixo; botão sem link
  # variável. Leitura por `split` (sem regex): o que vem entre `{{` e `}}` é o nome da variável.
  def self.fillable_template?(template)
    variables = native_body(template).split('{{').drop(1).map { |part| part.split('}}').first.to_s.strip }
    variables.all? { |name| FILLED_VARIABLES.include?(name) } && Array(template.to_h['components']).none? { |item| asks_more?(item) }
  end

  def self.asks_more?(component)
    case component.to_h['type'].to_s.upcase
    when 'HEADER' then MEDIA_HEADERS.include?(component['format'].to_s.upcase) || component['text'].to_s.include?('{{')
    when 'BUTTONS' then Array(component['buttons']).any? { |button| button.to_h['url'].to_s.include?('{{') }
    else false
    end
  end
  private_class_method :asks_more?

  # Modelo da lista sincronizada da caixa com o nome e o idioma configurados (qualquer status).
  def self.synced_template(inbox, configured)
    name, language = configured.to_h.values_at('name', 'language').map(&:to_s)
    return if name.blank? || language.blank?

    Array(inbox&.channel.try(:message_templates)).find { |item| item['name'] == name && item['language'].to_s.casecmp?(language) }
  end

  # O mesmo, só se está APROVADO na Meta.
  def self.approved_template(inbox, configured)
    found = synced_template(inbox, configured)
    found if found.to_h['status'].to_s.casecmp?('approved')
  end

  def initialize(inbox:, contact:, conversation: nil, template: nil)
    @inbox = inbox
    @contact = contact
    @preferred = conversation
    @template = template.to_h
  end

  def decide
    return skip('no_inbox') if inbox.blank?
    return skip('no_contact') if contact.blank?

    case Crm::AgentBookingProfile.notice_channel_kind(inbox)
    when 'whatsapp' then official
    when 'waha' then waha
    when 'api' then api
    else skip('unsupported_inbox')
    end
  end

  private

  attr_reader :inbox, :contact, :template

  def official
    return session if conversation && Crm::FollowUps::MessagingWindow.new(conversation).can_send_session_message?

    approved = self.class.approved_template(inbox, template)
    problem = template_problem(approved)
    return skip(problem) if problem
    return skip('no_phone') if conversation.nil? && contact.phone_number.blank?

    Decision.new(mode: :native_template, conversation: conversation, template: approved)
  end

  def template_problem(approved)
    return 'template_required' if approved.blank?
    return 'template_without_link' unless self.class.native_body(approved).include?(LINK_PLACEHOLDER)

    'template_unsupported' unless self.class.fillable_template?(approved)
  end

  def waha
    recent = conversation.present? && conversation.messages.incoming.exists?(['messages.created_at > ?', WAHA_WINDOW.ago])
    recent ? session : skip('waha_outside_window')
  end

  def api
    return session if conversation && Crm::FollowUps::MessagingWindow.new(conversation).can_send_session_message?

    api_template = api_template_record
    return skip('template_required') if api_template.blank?

    Decision.new(mode: :api_template, conversation: conversation, template: api_template)
  end

  def session
    Decision.new(mode: :session, conversation: conversation)
  end

  def skip(reason)
    Decision.new(reason: reason)
  end

  def conversation
    return @conversation if defined?(@conversation)

    @conversation = if @preferred.present? && @preferred.inbox_id == inbox.id && @preferred.contact_id == contact.id
                      @preferred
                    else
                      contact.conversations.where(inbox_id: inbox.id).order(last_activity_at: :desc, id: :desc).first
                    end
  end

  def api_template_record
    id = template['id']
    return if id.blank?

    inbox.account.whatsapp_api_message_templates.active.for_inbox(inbox.id).find_by(id: id)
  end
end
