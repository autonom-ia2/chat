require 'rails_helper'

# G52 (#2760): na função personalizada, campaign_view vê as listas e campaign_manage cria, renomeia e apaga.
RSpec.describe 'Email list permissions', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: permissions) }
  let(:headers) { user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/lists" }
  let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }

  before { user.account_users.find_by!(account: account).update!(custom_role: role) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { example.run }
  end

  context 'with campaign_view only' do
    let(:permissions) { ['campaign_view'] }

    it 'vê as listas, mas não cria, renomeia nem apaga' do
      lista
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post path, params: { email_list: { name: 'Nova' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{path}/#{lista.id}", params: { email_list: { name: 'X' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{path}/#{lista.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with campaign_manage' do
    let(:permissions) { ['campaign_manage'] }

    it 'cria a lista' do
      post path, params: { email_list: { name: 'Nova' } }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  # Contar quem tem a etiqueta da lista é ler a base de contatos: sem contact_view, a lista vem sem os números (a mesma
  # regra do Autonomia::Automacao::Tempo::Selecao).
  context 'with campaign_view, sem contact_view' do
    let(:permissions) { %w[campaign_view campaign_manage] }

    it 'vê as listas sem quantos estão nelas, nem ao renomear' do
      create(:contact, account: account, email: 'ana@exemplo.com').update_labels([lista.label.title])

      get path, headers: headers, as: :json
      expect(response.parsed_body).to eq([{ 'id' => lista.id, 'name' => 'Dicas do mês', 'label_id' => lista.label_id,
                                            'contatos_count' => nil, 'recebem_count' => nil }])
      patch "#{path}/#{lista.id}", params: { email_list: { name: 'Novidades' } }, headers: headers, as: :json
      expect(response.parsed_body).to include('contatos_count' => nil, 'recebem_count' => nil)
    end
  end

  context 'with campaign_view e contact_view' do
    let(:permissions) { %w[campaign_view contact_view] }

    it 'vê quantos estão em cada lista' do
      create(:contact, account: account, email: 'ana@exemplo.com').update_labels([lista.label.title])

      get path, headers: headers, as: :json

      expect(response.parsed_body.first).to include('contatos_count' => 1, 'recebem_count' => 1)
    end
  end
end
