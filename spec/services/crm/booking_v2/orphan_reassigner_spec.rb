require 'rails_helper'

RSpec.describe Crm::BookingV2::OrphanReassigner do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:world) { build_booking_world(account: account) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Vendedor') }

  around { |example| with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run } }

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def page_meeting(host, starts_at, profile: world.profile)
    create_internal_meeting(world: world, starts_at: starts_at, created_by: host, metadata: { 'booking_profile_id' => profile.id })
  end

  # Reunião Google do agendamento antigo (sem página nova): gravada sem validação, só para o teste de isolamento.
  def legacy_google_meeting(host, starts_at)
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    meeting = account.crm_meetings.new(card: world.card, created_by: host, inbox: inbox, title: 'Antiga', provider: :google,
                                       online_meeting_type: :google_meet, status: :scheduled, timezone: 'America/Sao_Paulo',
                                       starts_at: starts_at, ends_at: starts_at + 30.minutes, external_event_id: 'evt-1')
    meeting.save!(validate: false)
    meeting.meeting_guests.create!(account: account, email: 'cliente@example.com', guest_type: :external_email)
    expect(meeting).to be_valid # válida: se fosse reatribuída, a gravação passaria
    meeting
  end

  # A reatribuição roda num job enfileirado pelo callback de remoção (a remoção nunca depende dela).
  def remove_from_account(user)
    perform_enqueued_jobs(only: Crm::BookingV2::OrphanReassignJob) { user.account_users.find_by(account: account).destroy! }
  end

  def reassigned_activities
    Crm::Activity.where(account: account, event_type: 'meeting_host_reassigned')
  end

  it 'moves upcoming meetings to the page default host, disables the links and logs one activity per card' do
    world.profile.agent_booking_links.create!(account: account, agent: seller)
    future = page_meeting(seller, 2.days.from_now)
    past = page_meeting(seller, 2.days.ago)

    remove_from_account(seller)

    expect(future.reload.created_by_id).to eq(world.host.id)
    expect(past.reload.created_by_id).to eq(seller.id)
    expect(world.profile.agent_booking_links.find_by(agent: seller).enabled).to be(false)
    expect(reassigned_activities.pluck(:card_id, :payload)).to eq(
      [[world.card.id, { 'meeting_id' => future.id, 'from_user_id' => seller.id, 'to_user_id' => world.host.id,
                         'booking_profile_id' => world.profile.id }]]
    )
  end

  it 'falls back to the first administrator when the page host is the one leaving' do
    meeting = page_meeting(world.host, 1.day.from_now)

    remove_from_account(world.host)

    expect(meeting.reload.created_by_id).to eq(admin.id)
  end

  it 'falls back to the first administrator when the page host is no longer eligible' do
    role = create(:custom_role, account: account, permissions: ['campaign_view'])
    world.host.account_users.find_by(account: account).update!(custom_role: role)
    meeting = page_meeting(seller, 1.day.from_now)

    remove_from_account(seller)

    expect(meeting.reload.created_by_id).to eq(admin.id)
  end

  it 'leaves canceled meetings and other accounts untouched' do
    canceled = page_meeting(seller, 1.day.from_now)
    canceled.update!(status: :canceled)

    remove_from_account(seller)

    expect(canceled.reload.created_by_id).to eq(seller.id)
    expect(reassigned_activities).to be_empty
  end

  it 'remover a pessoa só enfileira o job: a remoção não espera nem depende da reatribuição' do
    page_meeting(seller, 1.day.from_now)

    expect { seller.account_users.find_by(account: account).destroy! }
      .to have_enqueued_job(Crm::BookingV2::OrphanReassignJob).with(account.id, seller.id)
  end

  it 'uma reunião inválida não impede as outras de serem reatribuídas' do
    broken = page_meeting(seller, 1.day.from_now)
    good = page_meeting(seller, 2.days.from_now)
    broken.update_column(:ends_at, broken.starts_at - 1.minute) # rubocop:disable Rails/SkipsModelValidations

    remove_from_account(seller)

    expect(broken.reload.created_by_id).to eq(seller.id)
    expect(good.reload.created_by_id).to eq(world.host.id)
  end

  it 'does nothing when the account flag is off' do
    world.profile.agent_booking_links.create!(account: account, agent: seller)
    meeting = page_meeting(seller, 2.days.from_now)
    account.disable_features('crm_booking_v2')
    account.save!

    remove_from_account(seller)

    expect(meeting.reload.created_by_id).to eq(seller.id)
    expect(world.profile.agent_booking_links.find_by(agent: seller).enabled).to be(true)
    expect(reassigned_activities).to be_empty
  end

  it 'leaves an old Google meeting of the same person untouched' do
    google = legacy_google_meeting(seller, 2.days.from_now)
    internal = page_meeting(seller, 3.days.from_now)

    remove_from_account(seller)

    expect(google.reload.created_by_id).to eq(seller.id)
    expect(internal.reload.created_by_id).to eq(world.host.id)
    expect(reassigned_activities.count).to eq(1)
  end

  it 'deixa intacta reunião interna que não veio de página nova' do
    manual = create_internal_meeting(world: world, starts_at: 2.days.from_now, created_by: seller)

    remove_from_account(seller)

    expect(manual.reload.created_by_id).to eq(seller.id)
    expect(reassigned_activities).to be_empty
  end

  it 'leaves the link of a legacy page untouched' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    create(:inbox_member, inbox: inbox, user: seller)
    legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE,
                                    inbox: inbox, assignment_mode: :per_agent, locations: [])
    legacy_link = legacy.agent_booking_links.create!(account: account, agent: seller, inbox: inbox)
    new_link = world.profile.agent_booking_links.create!(account: account, agent: seller)

    remove_from_account(seller)

    expect(legacy_link.reload.enabled).to be(true)
    expect(new_link.reload.enabled).to be(false)
  end

  it 'logs every reassignment with ids, including the fallback to the first administrator' do
    to_page_host = page_meeting(seller, 2.days.from_now)
    orphan_page = create_booking_profile(account: account, host: seller)
    to_admin = page_meeting(seller, 3.days.from_now, profile: orphan_page)
    allow(Rails.logger).to receive(:info)

    remove_from_account(seller)

    expect(Rails.logger).to have_received(:info)
      .with(include("meeting #{to_page_host.id} reassigned from user #{seller.id} to user #{world.host.id} (page_default_host)"))
    expect(Rails.logger).to have_received(:info)
      .with(include("meeting #{to_admin.id} reassigned from user #{seller.id} to user #{admin.id} (first_administrator)"))
  end

  it 'does nothing while the user is still a member of the account' do
    meeting = page_meeting(seller, 1.day.from_now)

    described_class.new(account_id: account.id, user_id: seller.id).perform

    expect(meeting.reload.created_by_id).to eq(seller.id)
  end

  describe 'removing the user the normal way (DELETE agents/:id)', type: :request do
    it 'reassigns the meeting through the AccountUser destroy callback' do
      meeting = page_meeting(seller, 3.days.from_now)

      perform_enqueued_jobs do
        delete "/api/v1/accounts/#{account.id}/agents/#{seller.id}", headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(account.account_users.exists?(user_id: seller.id)).to be(false)
      expect(meeting.reload.created_by_id).to eq(world.host.id)
      expect(reassigned_activities.count).to eq(1)
    end

    it 'still removes the person when the job cannot be enqueued, and logs the error class' do
      allow(Crm::BookingV2::OrphanReassignJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'redis down')
      allow(Rails.logger).to receive(:error)

      delete "/api/v1/accounts/#{account.id}/agents/#{seller.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.account_users.exists?(user_id: seller.id)).to be(false)
      expect(Rails.logger).to have_received(:error).with(include('orphan reassign not enqueued', 'Redis::CannotConnectError'))
    end
  end
end
