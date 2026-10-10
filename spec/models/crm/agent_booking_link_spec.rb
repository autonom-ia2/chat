require 'rails_helper'

RSpec.describe Crm::AgentBookingLink, type: :model do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def build_link(**attrs)
    account.crm_agent_booking_links.new({ booking_profile: world.profile, agent: agent }.merge(attrs))
  end

  it 'funciona sem caixa de e-mail: quem atende é uma pessoa da conta' do
    link = build_link(inbox: nil)

    expect(link).to be_valid
    expect(link.save).to be(true)
    expect(link.slug).to be_present
  end

  it 'continua recusando caixa que não tem calendário' do
    link = build_link(inbox: create_crm_inbox(account: account, members: [agent]))

    expect(link).not_to be_valid
    expect(link.errors[:inbox]).to include('is not a calendar-enabled inbox')
  end

  it 'recusa agente de outra conta' do
    other = create(:user, account: create(:account), role: :agent)

    expect(build_link(agent: other)).not_to be_valid
  end
end
