require 'rails_helper'

# #2454: "O que eu vi na foto" no passo 1 do "Cuidar dos comentários" do post. Só depois do clique (o passo 1 pede), só
# com a flag meta_ads_comentarios_ia, só para quem pode mudar o cuidado, e cada conta só vê e corrige a dela.
RSpec.describe 'Seus posts: o que eu vi na foto do post', type: :request do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:post_id) { '17900000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: '17841400000000001', provider_name: 'lojaexemplo') }
  let(:perfil) { "instagram-#{canal.id}" }
  let(:base) { "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_id}/cuidado/foto" }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:media) do
    stub_request(:get, %r{#{ig}/#{post_id}\?.*fields=media_type})
      .to_return(status: 200, headers: json, body: { media_type: 'IMAGE', media_url: 'https://cdn.exemplo/bolo.jpg' }.to_json)
  end

  def json = { 'Content-Type' => 'application/json' }

  def liga!(conta)
    conta.enable_features!('seus_posts', 'seus_posts_comentarios', 'meta_ads_comentarios_ia')
  end

  before do
    liga!(account)
    allow(SeusPosts::Posts).to receive(:para).and_return(
      instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [{ id: post_id, created_time: 1.day.ago.iso8601 }], normal: {} })
    )
    media
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: :hook }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create).and_return({ text: { description: 'Um bolo de cenoura com cobertura de chocolate.' }.to_json })
  end

  it 'sem a flag meta_ads_comentarios_ia: 404, sem ler a Meta nem chamar a IA' do
    account.disable_features!('meta_ads_comentarios_ia')

    post base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(media).not_to have_been_made
    expect(cliente).not_to have_received(:create)
  end

  it 'o passo 1 pede: lê a foto do post uma vez e devolve o que viu' do
    2.times { post base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'ready', 'text' => 'Um bolo de cenoura com cobertura de chocolate.', 'corrected' => false)
    expect(cliente).to have_received(:create).once
    expect(Crm::MetaAdsPostReading.sole).to have_attributes(account_id: account.id, network: 'instagram', post_id: post_id)
  end

  it 'o bloco de antes do clique (resumo) não lê a foto nem grava nada' do
    stub_request(:get, %r{#{ig}/#{post_id}/comments}).to_return(status: 200, headers: json, body: { data: [] }.to_json)
    stub_request(:get, %r{#{ig}/#{post_id}\?.*fields=comments_count}).to_return(status: 200, headers: json, body: { comments_count: 0 }.to_json)

    get "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_id}/resumo", params: { perfil: perfil },
                                                                             headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(media).not_to have_been_made
    expect(Crm::MetaAdsPostReading.count).to eq(0)
    expect(Crm::AiUsageEvent.count).to eq(0)
  end

  it 'corrigir: o texto do dono vira a correção e passa a valer' do
    post base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    put base, params: { perfil: perfil, correction: 'Bolo de cenoura do e-book, receita de vó' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'ready', 'text' => 'Bolo de cenoura do e-book, receita de vó', 'corrected' => true)
    expect(Crm::MetaAdsPostReading.sole).to have_attributes(correction: 'Bolo de cenoura do e-book, receita de vó', corrected_by_id: admin.id)
  end

  it 'corrigir com texto em forma errada ou longo demais: recusado, nada gravado' do
    put base, params: { perfil: perfil, correction: ['lista'] }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('error' => 'invalid_correction')

    put base, params: { perfil: perfil, correction: 'a' * 1001 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('error' => 'invalid_correction')
    expect(Crm::MetaAdsPostReading.count).to eq(0)
  end

  it 'PUT sem a chave correction: 422, sem apagar a correção; correction "" explícito volta para a leitura da IA' do
    post base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json
    put base, params: { perfil: perfil, correction: 'Bolo de cenoura do e-book' }, headers: admin.create_new_auth_token, as: :json

    put base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'missing_correction')
    expect(Crm::MetaAdsPostReading.sole.correction).to eq('Bolo de cenoura do e-book')

    put base, params: { perfil: perfil, correction: '' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'ready', 'corrected' => false)
    expect(Crm::MetaAdsPostReading.sole.correction).to be_nil
  end

  it 'agente sem posts_manage: 403 antes de ler a Meta' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: canal.inbox)
    allow(Pundit).to receive(:policy!).and_call_original
    allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

    post base, params: { perfil: perfil }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    put base, params: { perfil: perfil, correction: 'x' }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(media).not_to have_been_made
  end

  describe 'isolamento entre contas' do
    let(:outra) { create(:account) }
    let(:dono_da_outra) { create(:user, account: outra, role: :administrator) }
    let!(:canal_da_outra) { create(:channel_instagram, account: outra, instagram_id: '17841400000000009', provider_name: 'outraloja') }

    before do
      liga!(outra)
      create(:crm_meta_ads_post_reading, account: account, network: 'instagram', post_id: post_id, description: 'Leitura da conta A',
                                         correction: 'Correção da conta A')
    end

    it 'quem é de outra conta não lê nem corrige a foto desta conta' do
      post base, params: { perfil: perfil }, headers: dono_da_outra.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      put base, params: { perfil: perfil, correction: 'invadi' }, headers: dono_da_outra.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect(Crm::MetaAdsPostReading.sole.correction).to eq('Correção da conta A')
    end

    it 'o mesmo post na outra conta tem a leitura dela, sem ver a desta' do
      url = "/api/v1/accounts/#{outra.id}/seus_posts/posts/#{post_id}/cuidado/foto"

      post url, params: { perfil: "instagram-#{canal_da_outra.id}" }, headers: dono_da_outra.create_new_auth_token, as: :json

      expect(response.parsed_body['text']).to eq('Um bolo de cenoura com cobertura de chocolate.')
      expect(Crm::MetaAdsPostReading.where(account_id: account.id).sole.texto_para_ia).to eq('Correção da conta A')
    end
  end
end
