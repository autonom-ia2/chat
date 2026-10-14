# Caixas que a página de agendamento nova usa (BookingPagesController): a caixa de agenda para Meet/Teams e a caixa
# de WhatsApp dos avisos (#1192). As duas vêm do escopo de caixas que a própria pessoa já enxerga: escolher uma caixa
# não é conectar caixa (J8-A5).
module Crm::BookingPageInboxes
  extend ActiveSupport::Concern

  # A mensagem é o código devolvido (caixa de agenda ou de avisos fora do que a pessoa pode escolher).
  class InvalidInbox < StandardError; end

  private

  # Meet/Teams pedem uma caixa Google/Microsoft com agenda JÁ conectada.
  def calendar_inboxes
    policy_scope(::Inbox).includes(:channel).select do |inbox|
      channel = inbox.channel
      channel.is_a?(::Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
    end
  end

  def calendar_inbox_options
    calendar_inboxes.map { |inbox| { id: inbox.id, name: inbox.name, provider: inbox.channel.google? ? 'google' : 'microsoft' } }
  end

  def calendar_inbox_attributes
    body = params[:booking_page]
    return {} unless body.respond_to?(:key?) && body.key?(:calendar_inbox_id)

    raw = body[:calendar_inbox_id]
    return { inbox_id: nil } if raw.blank?
    # A tela manda a caixa em todo PATCH: só confere o escopo quando muda (quem não enxerga a caixa salva os outros
    # passos sem trocar a caixa que já estava lá).
    return {} if raw.to_s == @page.inbox_id.to_s

    inbox = calendar_inboxes.find { |item| item.id == raw.to_i } || (raise InvalidInbox, 'crm.booking_v2.calendar_inbox_invalid')
    { inbox_id: inbox.id }
  end

  # Caixas que podem mandar avisos (#1192).
  def notice_inboxes
    @notice_inboxes ||= ::Crm::BookingV2::NoticeInboxOptions.new(policy_scope(::Inbox))
  end

  def notice_inbox_attributes
    body = params[:booking_page]
    return {} unless body.respond_to?(:key?) && body.key?(:notice_inbox_id)
    return { notice_inbox_id: nil } if body[:notice_inbox_id].blank?
    return {} if body[:notice_inbox_id].to_s == @page.notice_inbox_id.to_s

    inbox = notice_inboxes.find(body[:notice_inbox_id]) || (raise InvalidInbox, 'crm.booking_v2.notice_inbox_invalid')
    { notice_inbox_id: inbox.id }
  end
end
