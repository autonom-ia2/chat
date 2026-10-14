# Bloco `meeting` do GET público do convite agendado (#1192, contrato F2-A): o que a página de gestão mostra. Só
# dados da própria reunião do cliente: horário no fuso da página, local com rótulo leigo, nome do responsável,
# estado, confirmação, prazo para mudar, avisos parados e o arquivo de calendário. Nenhum id interno, e-mail ou
# telefone.
class Crm::BookingV2::ManagePayload
  def self.ics_url(invite)
    token = Crm::BookingV2::Tokens.generate('ics', { 'c' => invite.code }, expires_in: Public::Api::V2::IcsController::TOKEN_TTL)
    "#{Crm::BookingInvite.base_url}/public/api/v2/ics/#{token}"
  end

  def initialize(invite)
    @invite = invite
    @meeting = invite.meeting
    @profile = invite.booking_profile
  end

  def as_json(*)
    {
      starts_at: local(meeting.starts_at), ends_at: local(meeting.ends_at), timezone: meeting.timezone, title: meeting.title,
      agent_name: agent_name, location: location
    }.merge(state)
  end

  private

  attr_reader :invite, :meeting, :profile

  def state
    deadline = Crm::BookingV2::ManageMeeting.change_deadline(meeting, profile)
    {
      status: meeting.canceled? ? 'canceled' : 'scheduled', confirmation_status: meeting.confirmation_status,
      can_change: meeting.scheduled? && Time.current < deadline, change_deadline: local(deadline),
      notices_stopped: notices_stopped?, ics_url: self.class.ics_url(invite)
    }
  end

  def agent_name
    meeting.created_by&.available_name.presence || profile.public_agent_name
  end

  def local(time)
    time.in_time_zone(ActiveSupport::TimeZone[meeting.timezone.to_s] || Time.zone).iso8601
  end

  def location
    data = { 'type' => meeting.online_meeting_type }.merge(meeting.metadata.to_h['location'].to_h)
    { type: data['type'], label: Crm::BookingV2::LocationLabel.for(data, account: meeting.account),
      join_url: meeting.online_meeting_url.presence, address: data['address'].presence }
  end

  def notices_stopped?
    meeting.reminders_stopped_at.present? || Crm::BookingNoticeStop.stopped?(account_id: invite.account_id, contact_id: invite.contact_id)
  end
end
