# "Salvar na minha agenda" da página pública v2 (#1189, J2-A11): arquivo de calendário da reunião agendada.
#
# O token vai no CAMINHO (não na query), é CIFRADO com `purpose` próprio ('ics'), vale 2 dias e carrega só o código
# do convite (nenhum id interno). Cifrado porque esse código é o link de gestão do cliente: quem visse o token (log,
# histórico) não pode extrair dele o acesso à reunião. Token inválido ou vencido, convite cancelado ou inativo, reunião
# que não está agendada ou flag da conta desligada: o mesmo 404 uniforme. O arquivo não tem e-mail de ninguém
# (`IcsBuilder`).
class Public::Api::V2::IcsController < PublicController
  TOKEN_TTL = 2.days
  FILENAME = 'reuniao.ics'.freeze

  def show
    meeting = find_meeting
    return render json: { error: 'not_found' }, status: :not_found if meeting.blank?

    location = { 'type' => meeting.online_meeting_type }.merge(meeting.metadata.to_h['location'].to_h)
    label = ::Crm::BookingV2::LocationLabel.for(location, account: meeting.account)
    send_data ::Crm::Meetings::IcsBuilder.new(meeting: meeting, location_label: label).build,
              type: 'text/calendar; charset=utf-8', disposition: 'attachment', filename: FILENAME
  end

  private

  def find_meeting
    payload = ::Crm::BookingV2::Tokens.verify('ics', params[:token].to_s)
    return unless payload.is_a?(Hash) && payload['c'].present?

    invite = ::Crm::BookingInvite.includes(meeting: :account).find_by(code: payload['c'].to_s)
    scheduled_meeting(invite) if invite&.active?
  end

  def scheduled_meeting(invite)
    meeting = invite.meeting
    meeting if meeting&.scheduled? && ::Crm::Config.booking_v2_enabled?(meeting.account)
  end
end
