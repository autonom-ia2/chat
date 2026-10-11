require 'rails_helper'

# Identidade salva das páginas de agendamento (#1289): guardar logo, cor, lado da logo, frase e a foto de quem atende
# uma vez; página nova já nasce com isso; "Usar a identidade salva" e "Salvar como identidade da conta".
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages identity', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }
  let(:identity) { Crm::BookingV2::BrandIdentity.new(account.reload) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def image(name = 'avatar.png')
    { io: Rails.root.join('spec/assets', name).open, filename: name, content_type: 'image/png' }
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def dress(target, color: '#FFE066', align: 'center', headline: 'Vamos conversar')
    target.logo.attach(image)
    target.photo.attach(image)
    target.update!(brand: { 'color' => color, 'logo_align' => align, 'headline' => headline })
    target
  end

  describe 'PATCH update' do
    it 'aceita cor escolhida pela pessoa e o lado da logo, e devolve os dois' do
      call(admin, :patch, "#{base}/#{page.id}", { brand: { color: '#ffe066', headline: 'Oi', logo_align: 'right' } })

      expect(response).to have_http_status(:ok)
      expect(page.reload.brand).to eq({ 'color' => '#ffe066', 'headline' => 'Oi', 'logo_align' => 'right' })
      expect(body.dig('payload', 'brand')).to eq({ 'color' => '#ffe066', 'headline' => 'Oi', 'logo_align' => 'right' })
    end

    it 'recusa cor que não é #RRGGBB e lado que não existe, sem gravar' do
      [{ color: 'amarelo' }, { color: '#ffe06' }, { color: '#ffe066', logo_align: 'top' }].each do |brand|
        call(admin, :patch, "#{base}/#{page.id}", { brand: brand })

        expect(response).to have_http_status(:unprocessable_entity), "aceitou #{brand}"
        expect(body['errors']).to have_key('brand')
      end
      expect(page.reload.brand).to eq({})
    end
  end

  describe 'GET show' do
    it 'sem nada salvo, diz que não há identidade' do
      call(admin, :get, "#{base}/#{page.id}")

      expect(body.dig('payload', 'identity')).to eq({ 'saved' => false, 'logo_url' => nil, 'photo_url' => nil })
    end
  end

  describe 'POST save_identity' do
    it 'guarda cor, lado, frase e logo na conta e a foto na pessoa que atende' do
      dress(page)

      call(admin, :post, "#{base}/#{page.id}/save_identity")

      expect(response).to have_http_status(:ok)
      expect(identity.data).to eq({ 'color' => '#FFE066', 'logo_align' => 'center', 'headline' => 'Vamos conversar' })
      expect(account.reload.booking_identity_logo.blob).to eq(page.logo.blob)
      expect(identity.photo_of(world.host).blob).to eq(page.photo.blob)
      expect(body.dig('payload', 'identity')).to include(
        'saved' => true, 'color' => '#FFE066', 'logo_align' => 'center', 'headline' => 'Vamos conversar'
      )
      expect(body.dig('payload', 'identity', 'logo_url')).to be_present
      expect(body.dig('payload', 'identity', 'photo_url')).to be_present
    end

    it 'não mexe no resto das configurações da conta' do
      account.update!(settings: account.settings.to_h.merge('auto_resolve_after' => 30))
      dress(page)

      call(admin, :post, "#{base}/#{page.id}/save_identity")

      expect(account.reload.settings).to include('auto_resolve_after' => 30)
      expect(account.settings['booking_identity']).to include('color' => '#FFE066')
    end

    it 'página sem logo não apaga a logo que já estava salva' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      bare = create_booking_profile(account: account, host: world.host, brand: { 'color' => '#0D2344' })

      call(admin, :post, "#{base}/#{bare.id}/save_identity")

      expect(identity.data).to eq({ 'color' => '#0D2344', 'logo_align' => nil, 'headline' => nil })
      expect(account.reload.booking_identity_logo).to be_attached
      expect(identity.photo_of(world.host)).to be_present
    end

    it 'não cria horário próprio nem pausa a agenda de quem atende ao guardar a foto' do
      dress(page)

      call(admin, :post, "#{base}/#{page.id}/save_identity")

      availability = Crm::AgentAvailability.find_by!(account: account, user: world.host)
      expect(availability.paused).to be(false)
      expect(availability.custom_hours?).to be(false)
    end

    it 'trocar a logo da página depois não derruba a logo da identidade' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      saved_blob = account.reload.booking_identity_logo.blob

      perform_enqueued_jobs do
        page.reload.logo.attach(image('sample.png'))
      end

      expect(ActiveStorage::Blob.exists?(saved_blob.id)).to be(true)
      expect(account.reload.booking_identity_logo.blob).to eq(saved_blob)
      expect(saved_blob.download).to be_present
    end
  end

  describe 'POST apply_identity' do
    it 'traz logo, cor, lado, frase e a foto de quem atende para a página' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      other = create_booking_profile(account: account, host: world.host, brand: { 'color' => '#0D2344' })

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      other.reload
      expect(other.brand).to eq({ 'color' => '#FFE066', 'logo_align' => 'center', 'headline' => 'Vamos conversar' })
      expect(other.logo.blob).to eq(page.logo.blob)
      expect(other.photo.blob).to eq(page.photo.blob)
      expect(body.dig('payload', 'logo_url')).to be_present
    end

    it 'identidade sem frase e sem lado limpa a frase e o lado da página' do
      bare = create_booking_profile(account: account, host: world.host, brand: { 'color' => '#0D2344' })
      call(admin, :post, "#{base}/#{bare.id}/save_identity")
      dress(page)

      call(admin, :post, "#{base}/#{page.id}/apply_identity")

      expect(page.reload.brand).to eq({ 'color' => '#0D2344' })
      expect(page.logo).to be_attached
    end

    it 'a foto é de cada pessoa: página de outra pessoa não recebe a foto de quem salvou' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      other_host = create(:user, account: account, role: :agent, name: 'Bruno')
      other = create_booking_profile(account: account, host: other_host)

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(other.reload.logo).to be_attached
      expect(other.photo).not_to be_attached
    end

    it 'sem identidade salva, deixa a página como está' do
      dress(page, color: '#0B7A5A', align: 'right', headline: 'Oi')

      call(admin, :post, "#{base}/#{page.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      expect(page.reload.brand).to eq({ 'color' => '#0B7A5A', 'logo_align' => 'right', 'headline' => 'Oi' })
      expect(page.logo).to be_attached
    end

    it 'a identidade é da conta: outra conta não enxerga nem usa' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      other_account = create(:account)
      other_account.enable_features('crm_booking_v2')
      other_account.save!
      other_admin = create(:user, account: other_account, role: :administrator)
      other_page = create_booking_profile(account: other_account, host: other_admin)

      call(other_admin, :post, "/api/v1/accounts/#{other_account.id}/crm/booking_pages/#{other_page.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'identity', 'saved')).to be(false)
      expect(other_page.reload.logo).not_to be_attached
      expect(other_page.brand).to eq({})

      call(other_admin, :post, "/api/v1/accounts/#{other_account.id}/crm/booking_pages/#{page.id}/apply_identity")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST create' do
    it 'página nova já nasce com a identidade salva' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")

      call(admin, :post, base, { template_key: 'sales_30' })

      expect(response).to have_http_status(:created)
      created = account.crm_agent_booking_profiles.find(body.dig('payload', 'id'))
      expect(created.brand).to eq({ 'color' => '#FFE066', 'logo_align' => 'center', 'headline' => 'Vamos conversar' })
      expect(created.logo.blob).to eq(page.logo.blob)
      expect(body.dig('payload', 'logo_url')).to be_present
      expect(body.dig('payload', 'identity', 'saved')).to be(true)
    end

    it 'identidade que a página recusa não deixa página pela metade' do
      account.update!(settings: account.settings.to_h.merge('booking_identity' => { 'color' => 'amarelo' }))

      expect { call(admin, :post, base, { template_key: 'sales_30' }) }.not_to change(account.crm_agent_booking_profiles, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sem identidade salva, nasce sem marca como antes' do
      call(admin, :post, base, { template_key: 'sales_30' })

      created = account.crm_agent_booking_profiles.find(body.dig('payload', 'id'))
      expect(created.brand).to eq({})
      expect(created.logo).not_to be_attached
    end
  end

  describe 'permissão' do
    let(:manager) { role_user('agendamento_manage') }

    it 'salvar a identidade é só do administrador: grava na conta e a foto de outra pessoa' do
      dress(page)

      [manager, role_user('agendamento_view'), create(:user, account: account, role: :agent)].each do |user|
        call(user, :post, "#{base}/#{page.id}/save_identity")
        expect(response).to have_http_status(:unauthorized)
      end
      expect(identity.data).to eq({})
      expect(account.reload.booking_identity_logo).not_to be_attached

      call(admin, :post, "#{base}/#{page.id}/save_identity")
      expect(response).to have_http_status(:ok)
    end

    it 'usar a identidade salva é de quem gerencia páginas; quem só vê e o agente comum, não' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")

      call(manager, :post, "#{base}/#{page.id}/apply_identity")
      expect(response).to have_http_status(:ok)

      [role_user('agendamento_view'), create(:user, account: account, role: :agent)].each do |user|
        call(user, :post, "#{base}/#{page.id}/apply_identity")
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'a página diz à tela quem pode salvar a identidade' do
      call(admin, :get, "#{base}/#{page.id}")
      expect(body.dig('payload', 'can_save_identity')).to be(true)

      call(manager, :get, "#{base}/#{page.id}")
      expect(body.dig('payload', 'can_save_identity')).to be(false)
    end
  end

  describe 'quem sai da conta' do
    it 'leva junto a foto guardada para as páginas' do
      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      availability = Crm::AgentAvailability.find_by!(account: account, user: world.host)
      expect(availability.booking_photo).to be_attached

      world.host.account_users.find_by(account: account).delete
      Crm::BookingV2::OrphanReassigner.new(account_id: account.id, user_id: world.host.id).perform

      expect(Crm::AgentAvailability.where(id: availability.id)).to be_empty
      expect(ActiveStorage::Attachment.where(record_type: 'Crm::AgentAvailability', record_id: availability.id)).to be_empty
    end
  end

  describe 'contrato da prévia do painel com a página pública' do
    let(:public_path) { "/public/api/v2/booking/#{page.slug}" }

    # A prévia monta a página com o que o painel recebe. O teste de fidelidade do front (previewFidelity.spec.js)
    # parte destas igualdades: fuso, feriados fechados e a foto de quem atende.
    it 'o painel recebe o mesmo fuso, os mesmos feriados fechados e a mesma foto que a página pública' do
      travel_to Time.utc(2026, 10, 9, 15, 0, 0) do
        page.update!(close_holidays: true, timezone: 'Brasilia')
        dress(page)
        call(admin, :post, "#{base}/#{page.id}/save_identity")
        page.reload.photo.detach

        call(admin, :get, "#{base}/#{page.id}")
        panel = body['payload']
        get public_path
        shown = response.parsed_body

        expect(panel.dig('preview', 'timezone')).to eq('America/Sao_Paulo')
        expect(panel.dig('preview', 'timezone')).to eq(shown['timezone'])
        expect(panel.dig('preview', 'closed_dates')).to eq(shown['closed_dates'])
        expect(shown['closed_dates']).to include('2026-10-12')
        expect(panel.dig('people', 0, 'booking_photo_url')).to be_present
        expect(panel.dig('people', 0, 'booking_photo_url')).to eq(shown['agent_photo_url'])
        expect(panel['booking_window_days']).to eq(shown['booking_window_days'])
      end
    end

    it 'sem foto guardada, a pessoa vem sem ela e a página usa a do perfil' do
      call(admin, :get, "#{base}/#{page.id}")

      expect(body.dig('payload', 'people', 0)).to include('booking_photo_url' => nil)
      expect(body.dig('payload', 'preview', 'closed_dates')).to eq([])
    end
  end

  describe 'página pública' do
    let(:public_path) { "/public/api/v2/booking/#{page.slug}" }

    it 'entrega o lado da logo e a cor escolhida' do
      dress(page, color: '#ffe066', align: 'right')

      get public_path

      expect(response).to have_http_status(:ok)
      expect(body['brand']).to include('color' => '#ffe066', 'logo_align' => 'right', 'headline' => 'Vamos conversar')
      expect(body.dig('brand', 'logo_url')).to be_present
    end

    it 'sem lado salvo, a logo fica à esquerda' do
      get public_path

      expect(body.dig('brand', 'logo_align')).to eq('left')
    end

    it 'a foto guardada por quem atende vem antes da foto do perfil' do
      get public_path
      expect(body['agent_photo_url']).to be_nil

      dress(page)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      page.reload.photo.detach

      get public_path

      expect(body['agent_photo_url']).to be_present
      expect(body.dig('brand', 'photo_url')).to be_nil
    end
  end
end
