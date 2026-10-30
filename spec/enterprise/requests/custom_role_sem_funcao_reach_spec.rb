require 'rails_helper'

# #2317: deixar alguém sem função é pôr essa pessoa numa função com as chaves do "Sem função"
# (CustomRoles::SemFuncaoCapacidades). Quem não é administrador só faz isso quando poderia dar essas chaves, a mesma
# régua de dar qualquer outra função. Vale para tirar a pessoa da função e para apagar uma função com destino "none".
RSpec.describe 'Leaving someone without a role (#2317)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:role) { create(:custom_role, account: account, permissions: %w[conversation_view]) }
  # Gerente sem alcance: tem Pessoas, monta funções e alcança a função da pessoa, mas não as chaves do "Sem função".
  let(:manager) { member_with(%w[people_manage custom_role_manage conversation_view]) }
  # Gerente com alcance: grant_above_own alcança toda função, o "Sem função" também.
  let(:manager_above) { member_with(%w[people_manage custom_role_manage grant_above_own]) }
  let!(:holder) { member_of(role) }

  before { account.enable_features!('custom_roles') }

  def member_with(permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def member_of(custom_role)
    membership = create(:user, account: account, role: :agent).account_users.find_by(account: account)
    membership.update!(custom_role: custom_role)
    membership
  end

  def take_out_of_role(as:)
    patch "/api/v1/accounts/#{account.id}/agents/#{holder.user_id}",
          params: { agent: { custom_role_id: nil } }, headers: as.create_new_auth_token, as: :json
  end

  def delete_role_to_none(as:)
    delete "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}",
           params: { destination_role_id: 'none' }, headers: as.create_new_auth_token, as: :json
  end

  describe 'taking someone out of their role' do
    it 'lets the administrator' do
      take_out_of_role(as: admin)

      expect(response).to have_http_status(:ok)
      expect(holder.reload.custom_role_id).to be_nil
    end

    it 'lets a manager who reaches the "Sem função" keys' do
      take_out_of_role(as: manager_above)

      expect(response).to have_http_status(:ok)
      expect(holder.reload.custom_role_id).to be_nil
    end

    it 'refuses a manager who does not, with the reason code of /custom_roles, and changes nothing' do
      take_out_of_role(as: manager)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq(CustomRoles::GrantGuard::OUT_OF_REACH)
      expect(holder.reload.custom_role_id).to eq(role.id)
    end

    it 'still lets that manager move the person to a role within reach' do
      other = create(:custom_role, account: account, permissions: %w[conversation_view])

      patch "/api/v1/accounts/#{account.id}/agents/#{holder.user_id}",
            params: { agent: { custom_role_id: other.id } }, headers: manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(holder.reload.custom_role_id).to eq(other.id)
    end
  end

  describe "deleting a role with destination 'none'" do
    it 'lets the administrator' do
      delete_role_to_none(as: admin)

      expect(response).to have_http_status(:ok)
      expect(CustomRole.exists?(role.id)).to be(false)
      expect(holder.reload.custom_role_id).to be_nil
    end

    it 'lets a manager who reaches the "Sem função" keys' do
      delete_role_to_none(as: manager_above)

      expect(response).to have_http_status(:ok)
      expect(CustomRole.exists?(role.id)).to be(false)
      expect(holder.reload.custom_role_id).to be_nil
    end

    it 'refuses a manager who does not, with the reason code of /custom_roles, and changes nothing' do
      delete_role_to_none(as: manager)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq(CustomRoles::GrantGuard::OUT_OF_REACH)
      expect(CustomRole.exists?(role.id)).to be(true)
      expect(holder.reload.custom_role_id).to eq(role.id)
    end

    it 'lets that manager delete a role nobody has: nobody is left without a role' do
      empty_role = create(:custom_role, account: account, permissions: %w[conversation_view])

      delete "/api/v1/accounts/#{account.id}/custom_roles/#{empty_role.id}",
             params: { destination_role_id: 'none' }, headers: manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(CustomRole.exists?(empty_role.id)).to be(false)
    end
  end
end
