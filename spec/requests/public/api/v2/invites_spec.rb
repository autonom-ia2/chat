require 'rails_helper'

# Lado público do link por cliente (#1190, J1-A2/A6, RA-05): 404 uniforme para todo caso sem acesso, payload só
# com primeiro nome e telefone mascarado, `viewed` atômico que ignora robô de pré-visualização.
RSpec.describe 'Public::Api::V2::Invites', type: :request do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:invite) { create_booking_invite(world: world) }
  let(:browser) { 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/129.0 Mobile Safari/537.36' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.contact.update!(email: 'marcos@example.com')
  end

  def show(code)
    get "/public/api/v2/invites/#{code}", headers: { 'User-Agent' => browser }
  end

  def viewed(code, agent: browser)
    post "/public/api/v2/invites/#{code}/viewed", headers: { 'User-Agent' => agent }
  end

  def expect_uniform_not_found
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq({ 'error' => 'not_found' })
  end

  describe 'GET show' do
    it 'returns the code, page slug, first name and masked phone only' do
      show(invite.code)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'code' => invite.code, 'page_slug' => world.profile.slug, 'state' => 'open',
        'contact_first_name' => 'Marcos', 'phone_masked' => '(11) •••••-5678'
      )
      %w[marcos@example.com +5511912345678 5511912345678 912345678].each { |secret| expect(response.body).not_to include(secret) }
      [account.id, world.contact.id, invite.id].each { |id| expect(response.parsed_body.values).not_to include(id) }
    end

    it 'says scheduled once the invite became a meeting, even after the deadline' do
      invite.update!(scheduled_at: Time.current, expires_at: 1.minute.ago)

      show(invite.code)

      expect(response.parsed_body['state']).to eq('scheduled')
    end

    it 'uses the personal link slug when the invite has one' do
      link = world.profile.agent_booking_links.create!(account: account, agent: world.host)
      invite.update!(booking_link: link)

      show(invite.code)

      expect(response.parsed_body['page_slug']).to eq(link.slug)
    end

    it 'returns null phone when the contact has none' do
      world.contact.update!(phone_number: nil)

      show(invite.code)

      expect(response.parsed_body['phone_masked']).to be_nil
    end

    it 'answers the same 404 for unknown, expired, canceled, paused, legacy, host gone, disabled link and flag off' do
      cases = {
        unknown: -> { 'ZZZZ2345' },
        expired: -> { create_booking_invite(world: world, expires_at: 1.minute.ago).code },
        canceled: -> { create_booking_invite(world: world, canceled_at: Time.current).code },
        paused_page: lambda {
          page = create_booking_profile(account: account, host: world.host, enabled: false)
          create_booking_invite(world: world, booking_profile: page).code
        },
        host_left: lambda {
          gone = create(:user, account: account, role: :agent)
          page = create_booking_profile(account: account, host: gone)
          code = create_booking_invite(world: world, booking_profile: page).code
          AccountUser.find_by(account: account, user: gone).delete
          code
        },
        disabled_link: lambda {
          link = world.profile.agent_booking_links.create!(account: account, agent: world.host, enabled: false)
          create_booking_invite(world: world, booking_link: link).code
        }
      }
      cases.each do |name, code|
        show(code.call)
        expect(response).to have_http_status(:not_found), "#{name}: #{response.status}"
        expect(response.parsed_body).to eq({ 'error' => 'not_found' })
      end

      code = invite.code
      account.disable_features('crm_booking_v2')
      account.save!
      show(code)
      expect_uniform_not_found
    end
  end

  describe 'POST viewed' do
    it 'records first and last opening and counts every opening' do
      first = Time.zone.parse('2026-10-09 10:00:00')
      travel_to(first) { viewed(invite.code) }
      expect(response).to have_http_status(:no_content)
      travel_to(first + 1.hour) { viewed(invite.code) }

      invite.reload
      expect(invite.open_count).to eq(2)
      expect(invite.first_opened_at).to eq(first)
      expect(invite.last_opened_at).to eq(first + 1.hour)
      expect(invite.state).to eq('opened')
    end

    it 'ignores link preview robots by user agent' do
      ['WhatsApp/2.24.1 A', 'facebookexternalhit/1.1', 'Mozilla/5.0 (compatible; Googlebot/2.1)', 'TelegramBot (like TwitterBot)',
       'Slackbot-LinkExpanding 1.0', 'Some Link Preview Service', 'MyCrawler', 'Spider 1', 'random-BOT'].each do |agent|
        viewed(invite.code, agent: agent)
        expect(response).to have_http_status(:no_content)
      end

      expect(invite.reload.open_count).to eq(0)
      expect(invite.first_opened_at).to be_nil
    end

    it 'answers the uniform 404 and records nothing for canceled invites or flag off' do
      invite.update!(canceled_at: Time.current)
      viewed(invite.code)
      expect_uniform_not_found

      other = create_booking_invite(world: world)
      account.disable_features('crm_booking_v2')
      account.save!
      viewed(other.code)
      expect_uniform_not_found
      expect([invite.reload.open_count, other.reload.open_count]).to eq([0, 0])
    end
  end
end
