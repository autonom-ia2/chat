# JSON do link por cliente para o painel (#1190): botão Agendar na conversa e no card. Estado (J1-A10), link,
# texto pronto (J1-A12) e quem criou. Pessoa só por id, nome e foto; e-mail e telefone não saem daqui.
class Crm::BookingV2::InviteSerializer
  def initialize(invite)
    @invite = invite
  end

  def as_json(*)
    timestamps.merge(references).merge(
      id: invite.id, code: invite.code, url: invite.url, text: text,
      state: invite.state, channel: invite.channel, open_count: invite.open_count
    )
  end

  private

  attr_reader :invite

  def references
    {
      booking_page: { id: invite.booking_profile.id, title: invite.booking_profile.title },
      contact: { id: invite.contact.id, name: invite.contact.name },
      created_by: Crm::BookingV2::PageSerializer.person(invite.created_by)
    }
  end

  # Depois de entregue, o texto que de fato saiu na conversa (o agente pode tê-lo editado); antes, o pronto.
  def text
    invite.metadata.to_h['delivered_text'].presence || Crm::BookingV2::InviteText.new(invite).to_s
  end

  def timestamps
    %i[expires_at sent_at first_opened_at scheduled_at canceled_at created_at].index_with { |name| invite.public_send(name)&.iso8601 }
  end
end
