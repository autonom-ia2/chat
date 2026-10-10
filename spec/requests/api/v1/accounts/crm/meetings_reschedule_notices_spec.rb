require 'rails_helper'

# Remarcar pelo painel uma reunião da página de agendamento nova (#1192): os avisos no WhatsApp vão para o novo
# horário (com o "remarcado" na hora) e a confirmação do cliente volta a pendente, como no remarcar pelo cliente.
RSpec.describe 'Api::V1::Accounts::Crm::Meetings reschedule notices', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:starts_at) { Time.zone.parse('2026-10-20T13:00:00Z') }
  let(:new_start) { Time.zone.parse('2026-10-22T15:00:00Z') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
  end

  def reschedule(meeting)
    patch "/api/v1/accounts/#{account.id}/crm/meetings/#{meeting.id}",
          params: { meeting: { starts_at: new_start.iso8601, ends_at: (new_start + 30.minutes).iso8601 } },
          headers: admin.create_new_auth_token, as: :json
  end

  it 'reprograma os avisos e volta a confirmação a pendente' do
    meeting = create_internal_meeting(world: world, starts_at: starts_at, metadata: { 'booking_profile_id' => world.profile.id })
    Crm::BookingV2::Notices::Scheduler.new(meeting).schedule!
    meeting.update!(confirmation_status: :confirmed, confirmed_at: Time.current)

    reschedule(meeting)

    expect(response).to have_http_status(:ok)
    expect(meeting.reload).to have_attributes(starts_at: new_start, confirmation_status: 'pending', confirmed_at: nil)
    expect(meeting.notices.order(:kind).pluck(:kind, :status, :due_at, :skip_reason)).to eq(
      [
        ['booked', 'skipped', Time.current, 'replaced'],
        ['day_before', 'pending', new_start - 1.day, nil],
        ['hour_before', 'pending', new_start - 1.hour, nil],
        ['rescheduled', 'pending', Time.current, nil]
      ]
    )
    expect(response.parsed_body['payload']).to include('confirmation_status' => 'pending')
  end

  it 'reunião marcada pelo painel (sem página nova) não ganha aviso nem muda a confirmação' do
    meeting = create_internal_meeting(world: world, starts_at: starts_at)

    reschedule(meeting)

    expect(response).to have_http_status(:ok)
    expect(meeting.reload).to have_attributes(starts_at: new_start, confirmation_status: 'pending')
    expect(meeting.notices).to be_empty
  end
end
