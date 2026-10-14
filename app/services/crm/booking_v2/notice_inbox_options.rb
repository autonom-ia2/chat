# Caixas que podem mandar os avisos da página (#1192): WhatsApp oficial (Cloud ou 360dialog), WAHA e canal API de
# WhatsApp, dentro do escopo de caixas que a própria pessoa já enxerga (`policy_scope(::Inbox)`, passado por quem
# chama). Escolher uma não é conectar caixa (J8-A5). `needs_templates`: WhatsApp oficial, que fora da janela de 24 h
# só manda modelo aprovado na Meta.
class Crm::BookingV2::NoticeInboxOptions
  def initialize(inbox_scope)
    @inboxes = inbox_scope.includes(:channel).select { |inbox| Crm::AgentBookingProfile.notice_inbox_supported?(inbox) }
  end

  def find(id)
    @inboxes.find { |inbox| inbox.id == id.to_i }
  end

  def as_json(*)
    @inboxes.map do |inbox|
      kind = Crm::AgentBookingProfile.notice_channel_kind(inbox)
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, provider: provider(inbox, kind), needs_templates: kind == 'whatsapp' }
    end
  end

  private

  def provider(inbox, kind)
    return kind unless kind == 'whatsapp'

    inbox.channel.provider == 'whatsapp_cloud' ? 'whatsapp_cloud' : '360dialog'
  end
end
