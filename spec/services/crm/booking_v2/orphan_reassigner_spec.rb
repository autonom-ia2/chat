require 'rails_helper'

RSpec.describe Crm::BookingV2::OrphanReassigner do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:world) { build_booking_world(account: account) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Vendedor') }

  def page_meeting(host, starts_at, profile: world.profile)
    create_internal_meeting(world: world, starts_at: starts_at, created_by: host, metadata: { 'booking_profile_id' => profile.id })
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
  end
end
