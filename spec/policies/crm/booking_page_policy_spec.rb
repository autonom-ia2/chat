require 'rails_helper'

RSpec.describe Crm::BookingPagePolicy, type: :policy do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:page) { create_booking_profile(account: account, host: admin) }

  let(:read_actions) { %i[index? show? people?] }
  let(:write_actions) { %i[create? update? destroy? publish? pause? preview_token? logo? photo? update_people?] }

  def policy_for(user, record)
    described_class.new({ user: user, account: account, account_user: user.account_users.find_by(account: account) }, record)
  end

  it 'gives the administrator every action' do
    (read_actions + write_actions).each do |action|
      expect(policy_for(admin, page).public_send(action)).to be(true), "administrator denied #{action}"
    end
  end

  it 'gives a plain agent with no custom role nothing' do
    (read_actions + write_actions).each do |action|
      expect(policy_for(agent, page).public_send(action)).to be(false), "agent allowed #{action}"
    end
  end

  it 'denies every action on a page of another account, even to the administrator' do
    other_account = create(:account)
    other_page = create_booking_profile(account: other_account, host: create(:user, account: other_account, role: :administrator))

    (read_actions + write_actions).each do |action|
      expect(policy_for(admin, other_page).public_send(action)).to be(false), "cross-account #{action} allowed"
    end
  end

  it 'scopes to new pages of the current account only' do
    # Página antiga sem caixa só para o escopo: a validação de caixa de calendário é da gaveta v1.
    legacy = account.crm_agent_booking_profiles.new(page_version: 1, title: 'Legacy', enabled: false, slug: SecureRandom.uuid)
    legacy.save!(validate: false)
    other_account = create(:account)
    create_booking_profile(account: other_account, host: create(:user, account: other_account, role: :administrator))
    context = { user: admin, account: account, account_user: admin.account_users.find_by(account: account) }

    expect(described_class::Scope.new(context, Crm::AgentBookingProfile).resolve).to contain_exactly(page)
  end
end
