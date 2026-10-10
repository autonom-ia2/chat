require 'rails_helper'

# Matriz de permissões do módulo `agendamento` (#1187, J8-A14) com funções personalizadas (overlay EE).
RSpec.describe Crm::BookingPagePolicy, type: :policy do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:page) { create_booking_profile(account: account, host: admin) }

  let(:read_actions) { %i[index? show? people?] }
  let(:write_actions) { %i[create? update? destroy? publish? pause? preview_token? logo? photo? update_people?] }

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def allowed(user)
    context = { user: user, account: account, account_user: user.account_users.find_by(account: account) }
    (read_actions + write_actions).select { |action| described_class.new(context, page).public_send(action) }
  end

  it 'administrator: everything' do
    expect(allowed(admin)).to match_array(read_actions + write_actions)
  end

  it 'agendamento_manage: everything (manage implies view)' do
    expect(allowed(role_user('agendamento_manage'))).to match_array(read_actions + write_actions)
  end

  it 'agendamento_view: reads only, never writes' do
    expect(allowed(role_user('agendamento_view'))).to match_array(read_actions)
  end

  it 'plain agent with no custom role: nothing' do
    expect(allowed(create(:user, account: account, role: :agent))).to be_empty
  end

  it 'custom role without the module (even with full CRM keys): nothing' do
    expect(allowed(role_user('crm_view', 'crm_admin', 'crm_manage_cards'))).to be_empty
  end
end
