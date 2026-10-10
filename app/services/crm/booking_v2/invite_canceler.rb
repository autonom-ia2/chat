# Cancela o link por cliente (#1190, J1-A9). Cancelado é definitivo: o link público passa a responder como
# inexistente. Cancelar de novo não muda a data do primeiro cancelamento.
class Crm::BookingV2::InviteCanceler
  def initialize(invite)
    @invite = invite
  end

  def perform
    @invite.update!(canceled_at: Time.current) if @invite.canceled_at.blank?
    @invite
  end
end
