require 'rails_helper'

# #2414 G23 (#2737): o "ausente até" da pessoa. A de outra pessoa só pela edição de agente da Equipe, com a régua de
# people_manage (#1931): quem não é administrador não mexe na de um administrador. A própria pelo perfil, só na conta
# dela. Os quatro primeiros casos são os que a Funções pediu no parecer prévio.
RSpec.describe 'Ausente até (#2737)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:rh) do
    user = create(:user, account: account, role: :agent)
    membership(user).update!(custom_role: create(:custom_role, account: account, permissions: %w[people_manage]))
    user
  end
  let(:ferias) { 10.days.from_now.change(usec: 0) }

  before { account.enable_features!('custom_roles') }

  def membership(user) = user.account_users.find_by(account: account)

  def marcar(alvo, como:, ausente_ate: ferias.iso8601)
    patch "/api/v1/accounts/#{account.id}/agents/#{alvo.id}",
          params: { agent: { ausente_ate: ausente_ate } }, headers: como.create_new_auth_token, as: :json
  end

  def marcar_a_minha(como:, conta_id: account.id, ausente_ate: ferias.iso8601)
    post '/api/v1/profile/ausencia', params: { profile: { account_id: conta_id, ausente_ate: ausente_ate } },
                                     headers: como.create_new_auth_token, as: :json
  end

  describe 'na Equipe' do
    it 'people_manage marca a ausência de um agente' do
      marcar(agente, como: rh)

      expect(response).to have_http_status(:ok)
      expect(membership(agente).reload.ausente_ate).to eq(ferias)
      expect(response.parsed_body['ausente_ate']).to be_present
    end

    it 'people_manage não marca a de um administrador' do
      marcar(admin, como: rh)

      expect(response).to have_http_status(:unauthorized)
      expect(membership(admin).reload.ausente_ate).to be_nil
    end

    it 'agente comum não marca a de outra pessoa' do
      marcar(create(:user, account: account, role: :agent), como: agente)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'vazio limpa a ausência, e o resto da pessoa fica como estava' do
      membership(agente).update!(ausente_ate: ferias, availability: :busy)

      marcar(agente, como: admin, ausente_ate: nil)

      expect(response).to have_http_status(:ok)
      expect(membership(agente).reload.ausente_ate).to be_nil
      expect(membership(agente).availability).to eq('busy')
    end

    it 'texto que não é data, espaço ou false é recusado e não apaga a ausência marcada' do
      membership(agente).update!(ausente_ate: ferias)

      ['semana que vem', '   ', false].each do |errado|
        marcar(agente, como: admin, ausente_ate: errado)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(membership(agente).reload.ausente_ate).to eq(ferias)
      end
    end

    it 'editar só o nome não mexe na ausência' do
      membership(agente).update!(ausente_ate: ferias)

      patch "/api/v1/accounts/#{account.id}/agents/#{agente.id}",
            params: { agent: { name: 'Novo Nome' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(membership(agente).reload.ausente_ate).to eq(ferias)
    end
  end

  describe 'no perfil' do
    it 'a própria pessoa marca a sua ausência nesta conta' do
      marcar_a_minha(como: agente)

      expect(response).to have_http_status(:ok)
      expect(membership(agente).reload.ausente_ate).to eq(ferias)
      conta = response.parsed_body['accounts'].find { |item| item['id'] == account.id }
      expect(conta['ausente_ate']).to be_present
    end

    it 'sem a chave ausente_ate é erro, e nulo explícito limpa', :aggregate_failures do
      membership(agente).update!(ausente_ate: ferias)

      post '/api/v1/profile/ausencia', params: { profile: { account_id: account.id } },
                                       headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(membership(agente).reload.ausente_ate).to eq(ferias)

      marcar_a_minha(como: agente, ausente_ate: nil)
      expect(response).to have_http_status(:ok)
      expect(membership(agente).reload.ausente_ate).to be_nil
    end

    it 'com uma conta que não é a da pessoa, não encontrado' do
      outra = create(:account)

      marcar_a_minha(como: agente, conta_id: outra.id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
