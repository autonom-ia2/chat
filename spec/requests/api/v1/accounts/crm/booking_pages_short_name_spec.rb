require 'rails_helper'

# Link curto no painel (#1282): gravar o nome curto da página, conferir se está livre, sugerir a partir do título e
# devolver os links já no formato curto. Só quem gerencia páginas (`agendamento_manage`) mexe; tudo atrás da flag.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages short name', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account, host_name: 'Camila Torres') }
  let(:page) { world.profile }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }
  let(:other_account) { create(:account) }
  let(:other_page) { build_booking_world(account: other_account).profile }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    [account, other_account].each do |item|
      item.enable_features('crm_booking_v2')
      item.save!
    end
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: verb == :get ? nil : :json)
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'GET short_name' do
    it 'diz que o nome está livre, ou o que impede' do
      other_page.update!(short_name: 'clinica-viva')

      cases = { 'clinica-nova' => nil, 'clinica-viva' => 'taken', 'admin' => 'reserved', 'ab' => 'too_short', 'clínica' => 'invalid_chars' }
      cases.each do |name, problem|
        call(admin, :get, "#{base}/short_name", name: name)

        expect(response).to have_http_status(:ok)
        expect(payload).to eq('name' => name, 'available' => problem.nil?, 'problem' => problem)
      end
    end

    it 'libera para a página o nome que já é dela, mas não o de página de outra conta passada como dona' do
      page.update!(short_name: 'minha-agenda')
      other_page.update!(short_name: 'clinica-viva')

      call(admin, :get, "#{base}/short_name", name: 'minha-agenda', page_id: page.id)
      expect(payload['available']).to be(true)

      call(admin, :get, "#{base}/short_name", name: 'clinica-viva', page_id: other_page.id)
      expect(payload).to include('available' => false, 'problem' => 'taken')
    end

    it 'sugere um nome a partir do título, com número se já tem dono' do
      other_page.update!(short_name: 'avaliacao-gratuita')

      call(admin, :get, "#{base}/short_name", title: 'Avaliação Gratuita')

      expect(payload).to eq('suggestion' => 'avaliacao-gratuita-2')
    end

    it 'só responde a quem gerencia páginas' do
      call(role_user('agendamento_manage'), :get, "#{base}/short_name", name: 'clinica-nova')
      expect(response).to have_http_status(:ok)

      [role_user('agendamento_view'), create(:user, account: account, role: :agent)].each do |user|
        call(user, :get, "#{base}/short_name", name: 'clinica-nova')
        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      end
    end

    it 'responde 404 com a flag da conta desligada' do
      account.disable_features('crm_booking_v2')
      account.save!

      call(admin, :get, "#{base}/short_name", name: 'clinica-nova')

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH com short_name' do
    it 'grava o nome em minúsculas e passa a devolver o link curto' do
      call(admin, :patch, "#{base}/#{page.id}", booking_page: { short_name: ' Clinica-Viva ' })

      expect(response).to have_http_status(:ok)
      expect(payload).to include('short_name' => 'clinica-viva', 'public_url' => 'https://chat.exemplo.com/a/clinica-viva')
      expect(page.reload.short_name).to eq('clinica-viva')
    end

    it 'tira o link curto quando o nome vem vazio' do
      page.update!(short_name: 'clinica-viva')

      call(admin, :patch, "#{base}/#{page.id}", booking_page: { short_name: '' })

      expect(payload).to include('short_name' => nil, 'public_url' => "https://chat.exemplo.com/book/#{page.slug}")
    end

    it 'recusa nome que já é de outra conta, do sistema ou mal formado, dizendo o motivo' do
      other_page.update!(short_name: 'clinica-viva')

      { 'clinica-viva' => 'taken', 'admin' => 'reserved', 'a b' => 'invalid_chars' }.each do |name, problem|
        call(admin, :patch, "#{base}/#{page.id}", booking_page: { short_name: name })

        expect(response).to have_http_status(:unprocessable_entity), name
        expect(response.parsed_body['errors']).to eq('short_name' => [problem])
      end
      expect(page.reload.short_name).to be_nil
    end

    it 'responde 422, e não 500, quando o índice único barra uma gravação simultânea' do
      allow(Crm::BookingV2::ShortName).to receive(:problem).and_return(nil)
      other_page.update!(short_name: 'clinica-viva')

      call(admin, :patch, "#{base}/#{page.id}", booking_page: { short_name: 'clinica-viva' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq('short_name' => ['taken'])
      expect(page.reload.short_name).to be_nil
    end

    it 'não deixa quem só vê mudar o nome' do
      call(role_user('agendamento_view'), :patch, "#{base}/#{page.id}", booking_page: { short_name: 'clinica-viva' })

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(page.reload.short_name).to be_nil
    end
  end

  describe 'links na lista e na página' do
    let(:colleague) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }

    it 'lista com o link curto quando existe e com o comprido quando não' do
      page
      call(admin, :get, base)
      expect(payload.first).to include('short_name' => nil, 'public_url' => "https://chat.exemplo.com/book/#{page.slug}")

      page.update!(short_name: 'clinica-viva')
      call(admin, :get, base)
      expect(payload.first).to include('short_name' => 'clinica-viva', 'public_url' => 'https://chat.exemplo.com/a/clinica-viva')
    end

    it 'dá um link curto por pessoa, com apelido, na página com um link por pessoa' do
      page.update!(short_name: 'clinica-viva')

      call(admin, :put, "#{base}/#{page.id}/people", user_ids: [world.host.id, colleague.id])

      expect(response).to have_http_status(:ok)
      expect(payload['public_url']).to be_nil
      expect(payload['links'].pluck('url')).to eq(%w[https://chat.exemplo.com/a/clinica-viva/camila https://chat.exemplo.com/a/clinica-viva/bruno])
      expect(payload['people'].pluck('public_url')).to eq(payload['links'].pluck('url'))
    end

    it 'dá apelido às pessoas que já estavam na página quando ela ganha o nome curto' do
      Crm::BookingV2::PagePeople.new(page).assign!([world.host.id, colleague.id])

      call(admin, :patch, "#{base}/#{page.id}", booking_page: { short_name: 'clinica-viva' })

      expect(payload['links'].pluck('url')).to eq(%w[https://chat.exemplo.com/a/clinica-viva/camila https://chat.exemplo.com/a/clinica-viva/bruno])
    end
  end
end
