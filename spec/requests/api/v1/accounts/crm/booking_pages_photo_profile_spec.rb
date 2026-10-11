require 'rails_helper'

# A foto de quem atende ligada à foto do perfil (#1298): o envio da foto da página pode virar também a foto do perfil,
# mas só quando quem envia É a pessoa que atende. O perfil de outra pessoa nunca é tocado, peça a tela o que pedir.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages photo and profile', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:host) { world.host }
  let(:page) { world.profile }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    # Quem atende também gerencia páginas (e vê cards, para poder atender): é ela quem monta a própria página.
    role = create(:custom_role, account: account, permissions: %w[agendamento_manage crm_view])
    host.account_users.find_by(account: account).update!(custom_role: role)
  end

  def png(name = 'avatar.png')
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', name), 'image/png')
  end

  def upload_photo(user, target = page, **params)
    post "#{base}/#{target.id}/photo", params: { file: png }.merge(params), headers: user.create_new_auth_token
  end

  def give_avatar(user)
    user.avatar.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'perfil.png', content_type: 'image/png')
    user.avatar.blob
  end

  def owner
    response.parsed_body.dig('payload', 'photo_owner')
  end

  describe 'a própria pessoa, com foto no perfil' do
    let!(:profile_blob) { give_avatar(host) }

    it 'a página diz de quem é a foto e mostra a foto do perfil em uso' do
      get "#{base}/#{page.id}", headers: host.create_new_auth_token, as: :json

      expect(owner).to include('name' => host.name, 'mine' => true, 'profile_updated' => false)
      expect(owner['profile_url']).to be_present
      expect(response.parsed_body.dig('payload', 'photo_url')).to be_nil
    end

    it 'trocar "só nesta página" (sem o pedido) não mexe no perfil' do
      upload_photo(host)

      expect(response).to have_http_status(:ok)
      expect(page.reload.photo).to be_attached
      expect(host.reload.avatar.blob).to eq(profile_blob)
      expect(owner).to include('mine' => true, 'profile_updated' => false)
    end

    it 'apply_to_profile false, vazio ou texto qualquer também não mexe no perfil' do
      ['false', '0', '', 'talvez'].each do |value|
        upload_photo(host, apply_to_profile: value)

        expect(host.reload.avatar.blob).to eq(profile_blob), "trocou o perfil com #{value.inspect}"
      end
    end

    it 'trocar "também no meu perfil" põe o mesmo arquivo no perfil, sem enviar de novo' do
      expect { upload_photo(host, apply_to_profile: 'true') }.to change(ActiveStorage::Blob, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(host.reload.avatar.blob).to eq(page.reload.photo.blob)
      expect(owner).to include('mine' => true, 'profile_updated' => true)
      expect(owner['profile_url']).to be_present
    end

    it 'tirar a foto do agendamento depois não tira a do perfil' do
      upload_photo(host, apply_to_profile: 'true')
      shared = page.reload.photo.blob

      perform_enqueued_jobs { page.photo.purge_later }

      expect(page.reload.photo).not_to be_attached
      expect(host.reload.avatar).to be_attached
      expect(host.avatar.blob).to eq(shared)
      expect(shared.download).to be_present
    end
  end

  describe 'a própria pessoa, sem foto no perfil' do
    it 'a foto enviada com o pedido vale para o agendamento e vira a foto do perfil' do
      expect(host.avatar).not_to be_attached

      upload_photo(host, apply_to_profile: 'true')

      expect(response).to have_http_status(:ok)
      expect(page.reload.photo).to be_attached
      expect(host.reload.avatar.blob).to eq(page.photo.blob)
      expect(owner).to include('profile_updated' => true)
    end

    it 'antes de enviar, a página diz que ela não tem foto no perfil' do
      get "#{base}/#{page.id}", headers: host.create_new_auth_token, as: :json

      expect(owner).to include('mine' => true, 'profile_url' => nil)
    end
  end

  describe 'administrador montando a página de outra pessoa' do
    it 'grava só a foto do agendamento: o pedido de trocar o perfil é ignorado para os dois' do
      host_blob = give_avatar(host)
      admin_blob = give_avatar(admin)

      upload_photo(admin, apply_to_profile: 'true')

      expect(response).to have_http_status(:ok)
      expect(page.reload.photo).to be_attached
      expect(host.reload.avatar.blob).to eq(host_blob)
      expect(admin.reload.avatar.blob).to eq(admin_blob)
      expect(owner).to include('name' => host.name, 'mine' => false, 'profile_updated' => false)
    end

    it 'pessoa sem foto no perfil continua sem: o administrador não cria a foto do perfil dela' do
      upload_photo(admin, apply_to_profile: 'true')

      expect(page.reload.photo).to be_attached
      expect(host.reload.avatar).not_to be_attached
      expect(admin.reload.avatar).not_to be_attached
    end

    it 'na página do próprio administrador, o perfil dele muda' do
      own = create_booking_profile(account: account, host: admin)

      upload_photo(admin, own, apply_to_profile: 'true')

      expect(admin.reload.avatar.blob).to eq(own.reload.photo.blob)
    end
  end

  describe 'página com um link por pessoa' do
    before do
      page.update!(assignment_mode: :per_agent)
      page.agent_booking_links.create!(account: account, agent: host)
    end

    it 'a foto é da página: o perfil de ninguém muda, nem o de quem envia e atende' do
      upload_photo(host, apply_to_profile: 'true')

      expect(response).to have_http_status(:ok)
      expect(page.reload.photo).to be_attached
      expect(host.reload.avatar).not_to be_attached
      expect(owner).to be_nil
    end
  end

  describe 'quem não gerencia páginas' do
    it 'não envia foto nem troca o próprio perfil por aqui' do
      agent = create(:user, account: account, role: :agent)
      own = create_booking_profile(account: account, host: agent)

      upload_photo(agent, own, apply_to_profile: 'true')

      expect(response).to have_http_status(:unauthorized)
      expect(agent.reload.avatar).not_to be_attached
    end
  end

  describe 'página pública' do
    it 'sem foto própria nem guardada, usa a foto do perfil de quem atende' do
      give_avatar(host)

      get "/public/api/v2/booking/#{page.slug}"

      expect(response).to have_http_status(:ok)

      expect(response.parsed_body['agent_photo_url']).to be_present
      expect(response.parsed_body.dig('brand', 'photo_url')).to be_nil
    end
  end
end
