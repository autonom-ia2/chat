# Ações do agente no dia da reunião da página de agendamento nova (#1193, F2-B):
#   POST /api/v1/accounts/:account_id/crm/meetings/:id/remind       — "Lembrar" (J4-A5)
#   POST /api/v1/accounts/:account_id/crm/meetings/:id/rebook_link  — "Enviar link para marcar outro horário" (J4-A6)
#
# Fica atrás da flag da conta (`crm_booking_v2`, 404 desligada). A reunião tem de ser de um card que a pessoa vê
# (`CardPolicy#show?`, o mesmo do detalhe da reunião). A mensagem só vai para uma conversa que a pessoa pode responder
# (`ConversationPolicy#show?`, o critério do envio de mensagem do painel e do botão Agendar); sem nenhuma, a recusa
# devolve o link para copiar. O link para remarcar cria um convite: além disso, precisa poder usar convites
# (`Crm::BookingInvitePolicy#create?`, a mesma regra do botão Agendar).
#
# 200 `{ payload: { reminded_at, message_id } }` (remind) ou `{ payload: <convite> }` (rebook_link).
# 422 `{ error: 'crm.booking_v2.<código>', url? }`: códigos em `MeetingReminder`, `RebookLink` e `InviteError`.
class Api::V1::Accounts::Crm::MeetingActionsController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_booking_v2_enabled
  before_action :fetch_meeting

  rescue_from ::Crm::BookingV2::MeetingActionError do |error|
    render json: { error: "crm.booking_v2.#{error.message}", url: error.url }.compact, status: :unprocessable_entity
  end

  rescue_from ::Crm::BookingV2::InviteError do |error|
    render_unprocessable("crm.booking_v2.#{error.message}")
  end

  def remind
    message = ::Crm::BookingV2::MeetingReminder.new(meeting: @meeting, user: Current.user, client: client).perform
    render json: { payload: { reminded_at: @meeting.reload.metadata['reminded_at'], message_id: message.id } }
  end

  def rebook_link
    authorize ::Crm::BookingInvite, :create?, policy_class: ::Crm::BookingInvitePolicy
    invite = ::Crm::BookingV2::RebookLink.new(meeting: @meeting, user: Current.user, client: client).perform
    render json: { payload: ::Crm::BookingV2::InviteSerializer.new(invite.reload).as_json }
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def fetch_meeting
    @meeting = Current.account.crm_meetings.where(card_id: policy_scope(::Crm::Card).select(:id)).find(params[:id])
    authorize @meeting.card, :show?
  end

  def client
    @client ||= ::Crm::BookingV2::MeetingClient.new(@meeting, visible: ->(conversation) { policy(conversation).show? })
  end
end
