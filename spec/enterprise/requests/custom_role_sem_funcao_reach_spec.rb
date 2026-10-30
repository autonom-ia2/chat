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

  describe 'taking someone out of their role, edge cases' do
    it 'lets a manager clear a stale role when custom roles are off (downgraded account)' do
      account.disable_features!('custom_roles')

      take_out_of_role(as: manager)

      expect(response).to have_http_status(:ok)
      expect(holder.reload.custom_role_id).to be_nil
    end

    it 'answers 200 without checking when the person already has no role' do
      holder.update!(custom_role: nil)

      take_out_of_role(as: manager)

      expect(response).to have_http_status(:ok)
      expect(holder.reload.custom_role_id).to be_nil
    end

    # Com crm_numeros_lentes, o sem função não vê os relatórios das vendas: a chave sai do que quem tira precisa alcançar.
    it 'follows crm_numeros_lentes: crm_view_reports is not asked for' do
      account.enable_features!('crm_numeros_lentes')
      asked = []
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(CustomRoles::GrantGuard).to receive(:reach?).and_wrap_original do |original, keys|
        asked << keys
        original.call(keys)
      end
      # rubocop:enable RSpec/AnyInstance

      take_out_of_role(as: manager)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq(CustomRoles::GrantGuard::OUT_OF_REACH)
      expect(asked.last).to include('sales_value_view')
      expect(asked.last).not_to include('crm_view_reports')
    end
  end

  # Toda recusa do GrantGuard no agents leva o código, no corpo do /custom_roles (#2317).
  describe 'every custom role refusal on agents carries its code' do
    let(:big_role) { create(:custom_role, account: account, permissions: %w[conversation_view crm_view]) }

    def expect_out_of_reach
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include('error' => 'out_of_reach', 'message' => I18n.t('errors.custom_role.out_of_reach'))
    end

    it 'when adding someone with a role above the giver' do
      post "/api/v1/accounts/#{account.id}/agents",
           params: { agent: { email: 'nova@loja.com.br', name: 'Nova', role: 'agent', custom_role_id: big_role.id } },
           headers: manager.create_new_auth_token, as: :json

      expect_out_of_reach
    end

    it 'when giving a role above the giver' do
      patch "/api/v1/accounts/#{account.id}/agents/#{holder.user_id}",
            params: { agent: { custom_role_id: big_role.id } }, headers: manager.create_new_auth_token, as: :json

      expect_out_of_reach
      expect(holder.reload.custom_role_id).to eq(role.id)
    end

    it 'when editing or removing someone whose role is above the giver' do
      director = member_of(big_role)

      patch "/api/v1/accounts/#{account.id}/agents/#{director.user_id}",
            params: { agent: { name: 'Outro nome' } }, headers: manager.create_new_auth_token, as: :json
      expect_out_of_reach

      delete "/api/v1/accounts/#{account.id}/agents/#{director.user_id}", headers: manager.create_new_auth_token, as: :json
      expect_out_of_reach
      expect(director.reload.custom_role_id).to eq(big_role.id)
    end

    it 'keeps the generic 401 for refusals that are not about custom roles' do
      patch "/api/v1/accounts/#{account.id}/agents/#{admin.id}",
            params: { agent: { name: 'Outro' } }, headers: manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).not_to eq('out_of_reach')
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
