require 'rails_helper'

# #1716: quem atende a caixa (membro ou administrador) manda modelo de produto e carrossel pela conversa: lê o catálogo,
# vê as fotos aprovadas do modelo e sobe a foto do computador para um cartão. Só naquela caixa e sem a tela de Modelos
# (decisão do Rodrigo, 16/10/2026). Graph falsa (WebMock).
RSpec.describe 'Api::V1::Accounts::Inboxes::WhatsappConversationAssets', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:other_inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: []).inbox
  end
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('whatsapp_campaign_products')
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: outsider, inbox: other_inbox)
    catalogs = { data: [{ id: 'cat-1', name: 'Loja', product_count: 1 }] }.to_json
    stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
                                                                      .to_return(status: 200, headers: json, body: catalogs)
    stub_request(:get, "#{graph}/cat-1/products").with(query: hash_including({}))
                                                 .to_return(status: 200, headers: json,
                                                            body: { data: [{ retailer_id: 'tenis', name: 'Tênis', price: 'R$ 99',
                                                                             availability: 'in stock' }] }.to_json)
  end

  def base(target = inbox)
    "/api/v1/accounts/#{account.id}/inboxes/#{target.id}/whatsapp_conversation_assets"
  end

  def call(method, path, user:, params: {})
    public_send(method, path, params: params, headers: user.create_new_auth_token)
  end

  def photo(name = 'sample.png', type = 'image/png')
    Rack::Test::UploadedFile.new(Rails.root.join("spec/assets/#{name}"), type)
  end

  describe 'who attends the inbox (member, without whatsapp_templates_view)' do
    it 'reads the catalog and the products, and rereads the chosen ones' do
      call(:get, "#{base}/catalog", user: agent)
      expect(response.parsed_body).to eq('catalog' => { 'name' => 'Loja', 'product_count' => 1 })

      call(:get, "#{base}/products", user: agent, params: { q: 'ten' })
      expect(response.parsed_body['payload'].pluck('id')).to eq(['tenis'])

      call(:get, "#{base}/products", user: agent, params: { ids: ['tenis'] })
      expect(response.parsed_body['payload'].pluck('id')).to eq(['tenis'])
    end

    it 'sees the approved card photos and the fields of the template profile' do
      profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'vitrine',
                                                language: 'pt_BR', fields: { '1' => 'cliente.primeiro_nome' })
      blob = ActiveStorage::Blob.create_and_upload!(io: photo, filename: 'cartao.png', content_type: 'image/png',
                                                    metadata: { 'account_id' => account.id, 'card_index' => 0 })
      profile.card_files.attach(blob)

      call(:get, "#{base}/template", user: agent, params: { name: 'vitrine', language: 'pt_BR' })

      expect(response.parsed_body['fields']).to eq('1' => 'cliente.primeiro_nome')
      media = response.parsed_body['card_media'].sole
      expect(media).to include('card_index' => 0, 'file_name' => 'cartao.png', 'preview_url' => a_string_starting_with('http'))
      expect(ActiveStorage::Blob.find_signed(media['blob_signed_id'])).to eq(blob)
    end

    it 'uploads a photo for a card: a file of this account, never sent to Meta, with a reference that expires' do
      call(:post, "#{base}/media", user: agent, params: { file: photo })

      expect(response).to have_http_status(:created)
      blob = ActiveStorage::Blob.find_signed(response.parsed_body['blob_signed_id'])
      expect(blob.metadata).to include('account_id' => account.id, 'conversation_upload' => true)
      expect(Whatsapp::Templates::HeaderMedia.blob_accepted?(blob, 'image', account.id)).to be(true)
      expect(a_request(:any, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.include?('uploads') })).not_to have_been_made
      travel 2.days do
        expect(ActiveStorage::Blob.find_signed(response.parsed_body['blob_signed_id'])).to be_nil
      end
    end

    it 'refuses what is not a JPG or PNG photo' do
      call(:post, "#{base}/media", user: agent, params: { file: photo('sample.pdf', 'application/pdf') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('card_photo_invalid')
    end

    it 'keeps the catalog behind the whatsapp_campaign_products flag' do
      account.disable_features!('whatsapp_campaign_products')

      call(:get, "#{base}/catalog", user: agent)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('feature_disabled')
    end

    it 'still has no access to the Templates screen API' do
      call(:get, "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_catalog", user: agent)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'who attends another inbox' do
    it 'is refused on every route, before Meta' do
      [[:get, 'catalog'], [:get, 'products'], [:get, 'template'], [:post, 'media']].each do |method, path|
        call(method, "#{base}/#{path}", user: outsider, params: path == 'media' ? { file: photo } : {})
        expect(response).to have_http_status(:unauthorized), "#{method} #{path}: #{response.status}"
      end
      expect(a_request(:get, ->(uri) { uri.host == 'graph.facebook.com' })).not_to have_been_made
    end
  end

  it 'an administrator attends every inbox of the account' do
    admin = create(:user, account: account, role: :administrator)

    call(:get, "#{base}/catalog", user: admin)
    expect(response).to have_http_status(:ok)
  end
end
