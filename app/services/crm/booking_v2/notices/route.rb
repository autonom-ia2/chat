# Por onde (e se) uma mensagem automática do agendamento pode sair (#1192, PLANO §2.5). Só decide; quem envia é o
# `Notices::Delivery`. Regra por tipo de caixa de avisos:
#
# - WhatsApp oficial (Cloud/360dialog): janela de 24 h aberta pelo cliente (`MessagingWindow`) → texto; fora dela,
#   modelo APROVADO na Meta configurado para o aviso; sem modelo → `template_required`.
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

  Decision = Struct.new(:mode, :reason, :conversation, :template, keyword_init: true) do
    def send?
      reason.nil?
    end
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

    approved = approved_native_template
    return skip('template_required') if approved.blank?
    return skip('no_phone') if conversation.nil? && contact.phone_number.blank?

    Decision.new(mode: :native_template, conversation: conversation, template: approved)
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

  # Modelo da Meta só vale se está APROVADO na lista sincronizada da caixa, com o mesmo nome e idioma.
  def approved_native_template
    name = template['name'].to_s
    language = template['language'].to_s
    return if name.blank? || language.blank?

    Array(inbox.channel.message_templates).find do |item|
      item['name'] == name && item['language'].to_s.casecmp?(language) && item['status'].to_s.casecmp?('approved')
    end
  end

  def api_template_record
    id = template['id']
    return if id.blank?

    inbox.account.whatsapp_api_message_templates.active.for_inbox(inbox.id).find_by(id: id)
  end
end
