require 'rails_helper'

# Funções personalizadas, lote 5b (#1849, brecha A2): a função sem "Contatos" não lista, não busca e não abre a base.
# O contato de uma conversa que a pessoa vê continua com ligar, nova mensagem e origem; nome, telefone e e-mail vêm
# com a própria conversa. Administrador e agente sem função não mudam.
RSpec.describe 'Ver contatos vale na leitura', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let!(:da_conversa) { create(:contact, account: account, name: 'Cliente da conversa', email: 'cliente@example.test') }
  let!(:da_base) { create(:contact, account: account, name: 'Outro da base', email: 'outro@example.test') }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    create(:inbox_member, user: user, inbox: inbox)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def conversa_de(contact, assignee)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, assignee: assignee)
  end

  describe 'quem atende sem a chave de contatos' do
    let(:atendente) { pessoa_com(%w[conversation_participating_manage]) }
    let(:headers) { atendente.create_new_auth_token }

    before { conversa_de(da_conversa, atendente) }

    it 'não lista, não busca, não filtra e não abre a base' do
      get "#{base}/contacts", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/contacts/search", params: { q: 'Outro' }, headers: headers
      expect(response).to have_http_status(:unauthorized)

      post "#{base}/contacts/filter", params: { payload: [] }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/contacts/#{da_base.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/contacts/#{da_conversa.id}/notes", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'a busca global não devolve contatos' do
      get "#{base}/search", params: { q: 'Outro' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('payload', 'contacts')).to eq([])
    end

    it 'liga, manda nova mensagem e vê a origem só do contato de uma conversa que vê' do
      get "#{base}/contacts/#{da_conversa.id}/contactable_inboxes", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      get "#{base}/campaign_journey/contact_origins/#{da_conversa.id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      get "#{base}/contacts/#{da_base.id}/contactable_inboxes", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'não consulta os pedidos do Shopify de um contato' do
      create(:integrations_hook, :shopify, account: account)
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_id).and_return('id')
      allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_secret).and_return('secret')
      # rubocop:enable RSpec/AnyInstance

      get "#{base}/integrations/shopify/orders", params: { contact_id: da_base.id }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'continua vendo as conversas anteriores do contato da conversa' do
      get "#{base}/contacts/#{da_conversa.id}/conversations", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].size).to eq(1)
    end
  end

  describe 'quem só lê a caixa' do
    let(:leitora) { pessoa_com(%w[conversation_view]) }

    before { conversa_de(da_conversa, nil) }

    it 'vê a origem do contato da conversa, mas não liga nem manda mensagem nova' do
      get "#{base}/campaign_journey/contact_origins/#{da_conversa.id}", headers: leitora.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      get "#{base}/contacts/#{da_conversa.id}/contactable_inboxes", headers: leitora.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'empresas' do
    before { account.enable_features!(:companies) }

    it 'fecha para quem não tem a chave e abre para quem tem' do
      get "#{base}/companies", headers: pessoa_com(%w[conversation_participating_manage]).create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/companies", headers: pessoa_com(%w[contact_view]).create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  it 'quem tem contact_view ou contact_manage lista a base' do
    %w[contact_view contact_manage].each do |chave|
      get "#{base}/contacts", headers: pessoa_com([chave]).create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  it 'o agente sem função continua listando e buscando' do
    agente = create(:user, account: account, role: :agent)
    get "#{base}/contacts", headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)

    get "#{base}/search", params: { q: 'Outro' }, headers: agente.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('payload', 'contacts').size).to eq(1)
  end
end
