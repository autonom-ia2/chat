require 'rails_helper'

RSpec.describe Crm::BookingV2::AttentionReport do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }

  def page_meeting(starts_at, profile: world.profile, host: world.host)
    create_internal_meeting(world: world, starts_at: starts_at, created_by: host, metadata: { 'booking_profile_id' => profile.id })
  end

  def strip_crm_access(user)
    role = create(:custom_role, account: account, permissions: ['campaign_view'])
    user.account_users.find_by(account: account).update!(custom_role: role)
  end

  it 'is empty when every host is eligible' do
    expect(described_class.new(account: account).entries).to be_empty
  end

  it 'flags a fixed page whose host lost CRM access and counts only its upcoming scheduled meetings' do
    page_meeting(2.days.from_now)
    page_meeting(3.days.from_now).update!(status: :canceled)
    other_page = create_booking_profile(account: account, host: world.host, enabled: false)
    page_meeting(4.days.from_now, profile: other_page)
    strip_crm_access(world.host)

    entry = described_class.new(account: account).entries.find { |e| e.profile.id == world.profile.id }

    expect(entry.reason).to eq('host_ineligible')
    expect(entry.user_id).to eq(world.host.id)
    expect(entry.upcoming_meetings_count).to eq(1)
  end

  it 'flags a per_agent page per ineligible link, and attention? reflects it' do
    seller = create(:user, account: account, role: :agent)
    world.profile.update!(assignment_mode: :per_agent)
    world.profile.agent_booking_links.create!(account: account, agent: world.host)
    world.profile.agent_booking_links.create!(account: account, agent: seller)
    strip_crm_access(seller)
    report = described_class.new(account: account)

    expect(report.entries.map { |e| [e.reason, e.user_id, e.link&.agent_id] }).to eq([['host_ineligible', seller.id, seller.id]])
    expect(report.attention?(world.profile)).to be(true)
  end

  it 'flags a per_agent page with no enabled link as host_missing' do
    world.profile.update!(assignment_mode: :per_agent)

    expect(described_class.new(account: account).entries.map(&:reason)).to eq(['host_missing'])
  end

  it 'ignores legacy pages and other accounts' do
    other = build_booking_world(account: create(:account), host_name: 'Outra')
    strip_crm_access(world.host)

    expect(described_class.new(account: account).entries.map { |e| e.profile.id }).to eq([world.profile.id])
    expect(described_class.new(account: other.account).entries).to be_empty
  end
end
