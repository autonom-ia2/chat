require 'rails_helper'

# Reunião marcada pela equipe no painel (#1265) e o motivo do aviso (#1271): com "Avisar o cliente no WhatsApp"
# ligado, a reunião guarda `notice_basis: 'combinado_com_atendente'`; desligado, não guarda motivo nenhum.
RSpec.describe Crm::BookingV2::PanelBooking do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:booker) { create(:user, account: account, role: :administrator, name: 'Juliana Melo') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.utc(2026, 10, 12, 11, 0, 0)) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def book(notify:)
    described_class.new(page: world.profile, user: booker, client: { card: world.card },
                        params: { starts_at: '2026-10-20T10:00:00-03:00', notify: notify }).perform.meeting
  end

  it 'records who booked and why the client is notified when notify is on' do
    meeting = book(notify: true)

    expect(meeting.source).to eq('panel')
    expect(meeting.metadata).to include('booked_by_user_id' => booker.id, 'notify_client' => true,
                                        'notice_basis' => 'combinado_com_atendente')
  end

  it 'records no notice basis when notify is off' do
    meeting = book(notify: false)

    expect(meeting.metadata).to include('booked_by_user_id' => booker.id, 'notify_client' => false)
    expect(meeting.metadata).not_to have_key('notice_basis')
  end
end
