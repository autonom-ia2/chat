require 'rails_helper'

# Funções personalizadas, lote 3 (#1797): `assignment_manage` libera as regras de distribuição e capacidade sem ser
# administrador. Sem a chave, nada muda: só o administrador.
RSpec.describe 'Regras de distribuição e capacidade com assignment_manage', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:operacao) { pessoa_com(%w[assignment_manage]) }
  let(:headers) { operacao.create_new_auth_token }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  describe 'antes: sem a chave' do
    let(:sem_chave) { pessoa_com(%w[conversation_manage inbox_manage]).create_new_auth_token }

    it 'recusa as regras de distribuição e as de capacidade' do
      get "#{base}/assignment_policies", headers: sem_chave, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/agent_capacity_policies", headers: sem_chave, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'regras de distribuição' do
    let(:regra) { create(:assignment_policy, account: account) }

    it 'lista, cria, edita e exclui' do
      get "#{base}/assignment_policies", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/assignment_policies", params: { assignment_policy: { name: 'Fila da manhã' } }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      criada = AssignmentPolicy.find_by!(account: account, name: 'Fila da manhã')

      get "#{base}/assignment_policies/#{criada.id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      patch "#{base}/assignment_policies/#{criada.id}", params: { assignment_policy: { name: 'Fila da tarde' } }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(criada.reload.name).to eq('Fila da tarde')

      delete "#{base}/assignment_policies/#{criada.id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(AssignmentPolicy.exists?(criada.id)).to be(false)
    end

    it 'liga a regra numa caixa, lê e desliga' do
      get "#{base}/assignment_policies/#{regra.id}/inboxes", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/inboxes/#{inbox.id}/assignment_policy", params: { assignment_policy_id: regra.id }, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      get "#{base}/inboxes/#{inbox.id}/assignment_policy", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      delete "#{base}/inboxes/#{inbox.id}/assignment_policy", headers: headers, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'capacidade' do
    let(:politica) { create(:agent_capacity_policy, account: account) }
    let(:atendente) { create(:user, account: account, role: :agent) }

    it 'lista, cria, edita e exclui' do
      get "#{base}/agent_capacity_policies", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/agent_capacity_policies", params: { agent_capacity_policy: { name: 'Plantão' } }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      criada = AgentCapacityPolicy.find_by!(account: account, name: 'Plantão')

      patch "#{base}/agent_capacity_policies/#{criada.id}", params: { agent_capacity_policy: { name: 'Plantão 2' } }, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      delete "#{base}/agent_capacity_policies/#{criada.id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(AgentCapacityPolicy.exists?(criada.id)).to be(false)
    end

    it 'põe e tira pessoa da política' do
      post "#{base}/agent_capacity_policies/#{politica.id}/users", params: { user_id: atendente.id }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(AccountUser.find_by(account: account, user: atendente).agent_capacity_policy_id).to eq(politica.id)

      get "#{base}/agent_capacity_policies/#{politica.id}/users", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.sole).to include('id' => atendente.id, 'name' => atendente.name)
      expect(response.parsed_body.sole.keys).not_to include('access_token', 'pubsub_token', 'hmac_identifier', 'message_signature')

      delete "#{base}/agent_capacity_policies/#{politica.id}/users/#{atendente.id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(AccountUser.find_by(account: account, user: atendente).agent_capacity_policy_id).to be_nil
    end

    it 'devolve a pessoa adicionada sem token' do
      post "#{base}/agent_capacity_policies/#{politica.id}/users", params: { user_id: atendente.id }, headers: headers, as: :json

      expect(response.parsed_body.keys).not_to include('access_token', 'pubsub_token')
    end

    it 'não tira pela política A quem está na política B' do
      outra = create(:agent_capacity_policy, account: account)
      AccountUser.find_by(account: account, user: atendente).update!(agent_capacity_policy: outra)

      delete "#{base}/agent_capacity_policies/#{politica.id}/users/#{atendente.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(AccountUser.find_by(account: account, user: atendente).agent_capacity_policy_id).to eq(outra.id)
    end

    it 'define, muda e apaga o limite por caixa' do
      limites = "#{base}/agent_capacity_policies/#{politica.id}/inbox_limits"
      post limites, params: { inbox_id: inbox.id, conversation_limit: 10 }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      limite = politica.inbox_capacity_limits.find_by!(inbox: inbox)

      put "#{limites}/#{limite.id}", params: { conversation_limit: 15 }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(limite.reload.conversation_limit).to eq(15)

      delete "#{limites}/#{limite.id}", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
      expect(InboxCapacityLimit.exists?(limite.id)).to be(false)
    end
  end
end
