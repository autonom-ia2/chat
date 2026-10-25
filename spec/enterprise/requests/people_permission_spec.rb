require 'rails_helper'

# #1931: people_manage lets a non-administrator (e.g. HR) add, edit and remove agents and manage teams;
# custom_role_manage lets them build roles. The four safeguards are checked here: only administrators make
# administrators, nobody touches administrators or their own access, rule 2 (only roles within reach, unless the
# role has grant_above_own) and the audit log. Lives under spec/enterprise: custom roles are EE.
RSpec.describe 'People permissions (#1931)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:hr) { member_with(%w[people_manage conversation_view]) }
  let(:hr_above) { member_with(%w[people_manage grant_above_own]) }
  let(:small_role) { create(:custom_role, account: account, permissions: %w[conversation_view]) }
  let(:big_role) { create(:custom_role, account: account, permissions: %w[conversation_view crm_view]) }
  let(:people_role) { create(:custom_role, account: account, permissions: %w[people_manage]) }

  before { account.enable_features!('custom_roles') }

  def member_with(permissions, role: nil)
    user = create(:user, account: account, role: :agent)
    membership(user).update!(custom_role: role || create(:custom_role, account: account, permissions: permissions))
    user
  end

  def membership(user)
    user.account_users.find_by(account: account)
  end

  def add_agent(as:, **agent)
    post "/api/v1/accounts/#{account.id}/agents",
         params: { agent: { email: 'nova@loja.com.br', name: 'Nova Pessoa', role: 'agent' }.merge(agent) },
         headers: as.create_new_auth_token, as: :json
  end

  def edit_agent(target, as:, **agent)
    patch "/api/v1/accounts/#{account.id}/agents/#{target.id}",
          params: { agent: agent }, headers: as.create_new_auth_token, as: :json
  end

  def remove_agent(target, as:)
    delete "/api/v1/accounts/#{account.id}/agents/#{target.id}", headers: as.create_new_auth_token, as: :json
  end

  def added_membership
    User.from_email('nova@loja.com.br')&.account_users&.find_by(account: account)
  end

  def integration_role
    role = create(:custom_role, account: account, permissions: %w[crm_view])
    AccountUser.create!(account: account, user: create(:user), role: :agent, integration: true, custom_role: role)
    role
  end

  describe 'adding people' do
    it 'refuses an agent without the key' do
      add_agent(as: create(:user, account: account, role: :agent))

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'lets people_manage add a plain agent, even without grant_above_own' do
      add_agent(as: hr)

      expect(response).to have_http_status(:ok)
      expect(added_membership).to be_agent
      expect(added_membership.custom_role_id).to be_nil
    end

    it 'never lets people_manage add an administrator' do
      add_agent(as: hr_above, role: 'administrator')

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'refuses the administrator role spelled as a number' do
      add_agent(as: hr_above, role: 1)

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'refuses a list where one custom role id is expected' do
      add_agent(as: hr_above, custom_role_id: [small_role.id])

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'hands out a role within reach' do
      add_agent(as: hr, custom_role_id: small_role.id)

      expect(response).to have_http_status(:ok)
      expect(added_membership.custom_role_id).to eq(small_role.id)
    end

    it 'refuses a role above the giver (rule 2)' do
      add_agent(as: hr, custom_role_id: big_role.id)

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'refuses a role with a delegation key, even one the giver holds' do
      add_agent(as: hr, custom_role_id: people_role.id)

      expect(response).to have_http_status(:unauthorized)
      expect(added_membership).to be_nil
    end

    it 'lets grant_above_own hand out any role, delegation keys included' do
      add_agent(as: hr_above, custom_role_id: people_role.id)

      expect(response).to have_http_status(:ok)
      expect(added_membership.custom_role_id).to eq(people_role.id)
    end

    it 'refuses a role of another account' do
      add_agent(as: admin, custom_role_id: create(:custom_role, account: create(:account)).id)

      expect(response).to have_http_status(:not_found)
      expect(added_membership).to be_nil
    end

    it 'refuses the role behind an integration token, even for an administrator' do
      add_agent(as: admin, custom_role_id: integration_role.id)

      expect(response).to have_http_status(:not_found)
      expect(added_membership).to be_nil
    end
  end

  describe 'editing and removing people' do
    let(:plain_agent) { create(:user, account: account, role: :agent) }

    it 'keeps administrators out of reach of people_manage' do
      edit_agent(admin, as: hr_above, name: 'Outro nome')
      expect(response).to have_http_status(:unauthorized)

      remove_agent(admin, as: hr_above)
      expect(response).to have_http_status(:unauthorized)
      expect(membership(admin.reload)).to be_administrator
    end

    it 'never promotes to administrator without being one' do
      edit_agent(plain_agent, as: hr_above, role: 'administrator')

      expect(response).to have_http_status(:unauthorized)
      expect(membership(plain_agent)).to be_agent
    end

    it 'never promotes with the role spelled as a number' do
      edit_agent(plain_agent, as: hr_above, role: 1)

      expect(response).to have_http_status(:unauthorized)
      expect(membership(plain_agent)).to be_agent
    end

    it 'lets an administrator save their own name with the same role' do
      edit_agent(admin, as: admin, name: 'Admin Novo', role: 'administrator')

      expect(response).to have_http_status(:ok)
      expect(admin.reload.name).to eq('Admin Novo')
    end

    it 'lets nobody change their own access' do
      edit_agent(hr_above, as: hr_above, custom_role_id: big_role.id)
      expect(response).to have_http_status(:unauthorized)

      edit_agent(admin, as: admin, role: 'agent')
      expect(response).to have_http_status(:unauthorized)

      remove_agent(admin, as: admin)
      expect(response).to have_http_status(:unauthorized)
      expect(membership(admin.reload)).to be_administrator
    end

    it 'refuses changing or removing someone whose current role is above the giver' do
      director = member_with([], role: big_role)

      edit_agent(director, as: hr, custom_role_id: small_role.id)
      expect(response).to have_http_status(:unauthorized)

      remove_agent(director, as: hr)
      expect(response).to have_http_status(:unauthorized)
      expect(membership(director).custom_role_id).to eq(big_role.id)
    end

    it 'does not edit even the name of someone whose role is above the giver' do
      director = member_with([], role: big_role)

      edit_agent(director, as: hr, name: 'Outro nome')

      expect(response).to have_http_status(:unauthorized)
      expect(director.reload.name).not_to eq('Outro nome')
    end

    it 'lets grant_above_own change the role of someone above' do
      director = member_with([], role: big_role)

      edit_agent(director, as: hr_above, custom_role_id: small_role.id)

      expect(response).to have_http_status(:ok)
      expect(membership(director).custom_role_id).to eq(small_role.id)
    end

    it 'keeps the custom role when an update does not mention it' do
      seller = member_with([], role: small_role)

      edit_agent(seller, as: admin, name: 'Novo nome')

      expect(response).to have_http_status(:ok)
      expect(membership(seller).custom_role_id).to eq(small_role.id)
    end

    it 'lets people_manage remove a plain agent' do
      remove_agent(plain_agent, as: hr)

      expect(response).to have_http_status(:ok)
      expect(membership(plain_agent)).to be_nil
    end
  end

  describe 'custom roles' do
    let(:builder) { member_with(%w[custom_role_manage conversation_view]) }

    def create_role(as:, permissions:)
      post "/api/v1/accounts/#{account.id}/custom_roles",
           params: { custom_role: { name: 'Vendas', permissions: permissions } }, headers: as.create_new_auth_token, as: :json
    end

    it 'lets people_manage read the roles but not build them' do
      get "/api/v1/accounts/#{account.id}/custom_roles", headers: hr.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      create_role(as: hr, permissions: %w[conversation_view])
      expect(response).to have_http_status(:unauthorized)
    end

    it 'builds roles only within reach' do
      create_role(as: builder, permissions: %w[conversation_view])
      expect(response).to have_http_status(:ok)

      create_role(as: builder, permissions: %w[crm_view])
      expect(response).to have_http_status(:unauthorized)

      create_role(as: builder, permissions: %w[people_manage])
      expect(response).to have_http_status(:unauthorized)
      expect(account.custom_roles.where(name: 'Vendas').count).to eq(1)
    end

    it 'never edits the role one holds, nor a role above' do
      own_role = membership(builder).custom_role

      patch "/api/v1/accounts/#{account.id}/custom_roles/#{own_role.id}",
            params: { custom_role: { permissions: %w[conversation_view crm_view] } }, headers: builder.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "/api/v1/accounts/#{account.id}/custom_roles/#{big_role.id}", headers: builder.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(own_role.reload.permissions).to eq(%w[custom_role_manage conversation_view])
      expect(CustomRole.exists?(big_role.id)).to be(true)
    end

    it 'hides the roles behind integration tokens' do
      role = integration_role

      get "/api/v1/accounts/#{account.id}/custom_roles", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('id')).not_to include(role.id)

      patch "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}",
            params: { custom_role: { permissions: %w[crm_admin] } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(role.reload.permissions).to eq(%w[crm_view])
    end
  end

  describe 'teams' do
    it 'lets people_manage create a team' do
      post "/api/v1/accounts/#{account.id}/teams", params: { team: { name: 'vendas' } }, headers: hr.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(account.teams.where(name: 'vendas')).to exist
    end
  end

  describe 'inbox members' do
    it 'refuses a person of another account' do
      inbox = create(:inbox, account: account)
      stranger = create(:user, account: create(:account))

      post "/api/v1/accounts/#{account.id}/inbox_members",
           params: { inbox_id: inbox.id, user_ids: [stranger.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(inbox.members).not_to include(stranger)
    end
  end

  describe 'invitation flow' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('AUTONOMIA_PRODUCT_INVITATIONS_ENABLED', anything).and_return('true')
      allow(Autonomia::ProductInvitations::AgentInviter).to receive(:new).and_return(inviter)
    end

    let(:inviter) do
      result = Autonomia::ProductInvitations::AgentInviter::Result.new(
        email: 'nova@loja.com.br', name: 'Nova Pessoa', role: 'agent', invitation_url: 'https://auth.example/aceitar',
        expires_in_hours: 6, email_delivery_failed: false, manual_share_required: false, email_delivery_error: nil
      )
      instance_double(Autonomia::ProductInvitations::AgentInviter, perform: result)
    end

    it 'puts the person in inboxes when the giver also has inbox_manage' do
      add_agent(as: member_with(%w[people_manage inbox_manage]), inbox_ids: [create(:inbox, account: account).id])

      expect(response).to have_http_status(:created)
      expect(Autonomia::ProductInvitations::AgentInviter).to have_received(:new)
    end

    it 'does not overwrite an invitation someone else made' do
      account.update!(custom_attributes: { 'autonomia_pending_agent_invitations' =>
        { 'nova@loja.com.br' => { 'role' => 'agent', 'invited_by_user_id' => admin.id } } })

      add_agent(as: hr)

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::ProductInvitations::AgentInviter).not_to have_received(:new)
    end

    it 'asks for inbox_manage to put the person in inboxes' do
      add_agent(as: hr, inbox_ids: [create(:inbox, account: account).id])

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::ProductInvitations::AgentInviter).not_to have_received(:new)
    end

    it 'never invites an administrator without being one' do
      add_agent(as: hr_above, role: 'administrator')

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::ProductInvitations::AgentInviter).not_to have_received(:new)
    end
  end

  describe 'audit log' do
    it 'records a change of role and a removal, with who did it' do
      seller = member_with([], role: small_role)
      seller_membership = membership(seller)

      edit_agent(seller, as: admin, custom_role_id: big_role.id)
      remove_agent(seller, as: admin)

      audits = Enterprise::AuditLog.where(auditable_type: 'AccountUser', auditable_id: seller_membership.id)
      change = audits.where(action: 'update').order(:id).last
      expect(change.audited_changes['custom_role_id']).to eq([small_role.id, big_role.id])
      expect(change.user).to eq(admin)
      expect(audits.where(action: 'destroy')).to exist
    end

    it 'records each holder when a role is deleted' do
      holder_membership = membership(member_with([], role: small_role))

      delete "/api/v1/accounts/#{account.id}/custom_roles/#{small_role.id}",
             params: { destination_role_id: 'none' }, headers: admin.create_new_auth_token, as: :json

      expect(holder_membership.reload.custom_role_id).to be_nil
      change = Enterprise::AuditLog.where(auditable_type: 'AccountUser', auditable_id: holder_membership.id, action: 'update').order(:id).last
      expect(change.audited_changes['custom_role_id']).to eq([small_role.id, nil])
    end

    it 'records creating a custom role' do
      post "/api/v1/accounts/#{account.id}/custom_roles",
           params: { custom_role: { name: 'Financeiro', permissions: %w[report_manage] } }, headers: admin.create_new_auth_token, as: :json

      expect(Enterprise::AuditLog.where(auditable_type: 'CustomRole', action: 'create', associated_id: account.id)).to exist
    end
  end
end
