require 'rails_helper'

RSpec.describe 'Brand kits API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/brand_kits" }
  let(:appearance) { attributes_for(:brand_kit)[:appearance] }

  describe 'GET /brand_kits' do
    it 'lists the live kits of the account, default first' do
      create(:brand_kit, account: account, name: 'B')
      default = create(:brand_kit, account: account, name: 'Z', is_default: true)
      create(:brand_kit, account: account, name: 'Arquivado', archived_at: Time.current)
      create(:brand_kit, name: 'Outra conta')

      get base_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      kits = response.parsed_body['payload']
      expect(kits.pluck('name')).to eq(%w[Z B])
      expect(kits.first).to include('id' => default.id, 'is_default' => true, 'archived_at' => nil)
      expect(kits.first['appearance']['palette']).to include('primary' => '#ff1f2d')
    end

    it 'refuses an agent without a custom role' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an anonymous request' do
      get base_path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /brand_kits' do
    it 'creates the first kit as the default and records who created it' do
      post base_path, params: { brand_kit: { name: 'Hub2You', source_url: 'https://hub2you.ai/', appearance: appearance } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body['payload']
      kit = BrandKit.find(body['id'])
      expect(kit).to have_attributes(is_default: true, created_by_id: admin.id, source_url: 'https://hub2you.ai/')
      expect(body['appearance']['typography']['fallback']).to eq('Arial, Helvetica, sans-serif')
    end

    it 'downloads the chosen logo only when saving' do
      downloader = instance_double(BrandKits::LogoDownloader, perform: true)
      allow(BrandKits::LogoDownloader).to receive(:new).and_return(downloader)

      post base_path, params: { brand_kit: { name: 'Hub2You', logo_source_url: 'https://hub2you.ai/logo.png', appearance: appearance } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(BrandKits::LogoDownloader).to have_received(:new).with(BrandKit.last, 'https://hub2you.ai/logo.png')
    end

    it 'keeps the kit and reports a warning when the logo cannot be downloaded' do
      downloader = instance_double(BrandKits::LogoDownloader)
      allow(downloader).to receive(:perform).and_raise(BrandKits::LogoDownloader::Error.new('logo_unsupported_type'))
      allow(BrandKits::LogoDownloader).to receive(:new).and_return(downloader)

      post base_path, params: { brand_kit: { name: 'Hub2You', logo_source_url: 'https://hub2you.ai/logo.svg', appearance: appearance } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['warnings']).to eq(['logo_unsupported_type'])
    end

    it 'returns 422 for an invalid appearance' do
      post base_path, params: { brand_kit: { name: 'X', appearance: appearance.deep_merge(palette: { primary: 'vermelho' }) } },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('appearance')
    end
  end

  describe 'PATCH, set_default and DELETE' do
    let!(:kit) { create(:brand_kit, account: account, is_default: true) }
    let!(:other) { create(:brand_kit, account: account) }

    it 'updates name and appearance' do
      patch "#{base_path}/#{kit.id}", params: { brand_kit: { name: 'Novo', appearance: appearance.deep_merge(palette: { accent: '#123456' }) } },
                                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(kit.reload.name).to eq('Novo')
      expect(kit.appearance.dig('palette', 'accent')).to eq('#123456')
    end

    it 'moves the default to another kit' do
      post "#{base_path}/#{other.id}/set_default", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(other.reload.is_default).to be(true)
      expect(kit.reload.is_default).to be(false)
    end

    it 'archives instead of deleting' do
      delete "#{base_path}/#{kit.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(kit.reload.archived_at).to be_present
      expect(kit.is_default).to be(false)
    end

    it 'refuses to edit an archived kit' do
      other.archive!
      patch "#{base_path}/#{other.id}", params: { brand_kit: { name: 'Y' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('brand_kit.archived')
    end

    it 'does not reach a kit of another account' do
      foreign = create(:brand_kit)
      get "#{base_path}/#{foreign.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
