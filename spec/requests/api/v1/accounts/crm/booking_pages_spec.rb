require 'rails_helper'

# API de páginas de agendamento novas (#1187 F1-A). Matriz J8-A14 por HTTP, criação por modelo, edição, publicação,
# upload, quem atende, isolamento entre contas e regressão da gaveta antiga.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  # Upload vai como multipart; o resto, JSON.
  def call(user, verb, path, params = {})
    return public_send(verb, path, params: params, headers: user.create_new_auth_token) if params.key?(:file)

    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def png_upload
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
  end

  def body
    response.parsed_body
  end

  describe 'permission matrix' do
    let(:people) do
      {
        admin: admin, manage: role_user('agendamento_manage'), view: role_user('agendamento_view'),
        agent: create(:user, account: account, role: :agent), other_role: role_user('crm_view', 'crm_admin')
      }
    end
    let(:route_names) { %i[index show people create update publish pause preview_token logo photo update_people destroy] }
    let(:reads) { %i[index show people] }
    let(:expected) do
      { admin: route_names, manage: route_names, view: reads, agent: [], other_role: [] }
    end

    # Página nova a cada chamada: o destroy de uma pessoa não pode esconder a rota da seguinte.
    def route(name, target)
      member = "#{base}/#{target.id}"
      {
        index: [:get, base, {}], show: [:get, member, {}], people: [:get, "#{member}/people", {}],
        create: [:post, base, { template_key: 'sales_30' }], update: [:patch, member, { title: 'Novo' }],
        publish: [:post, "#{member}/publish", {}], pause: [:post, "#{member}/pause", {}],
        preview_token: [:post, "#{member}/preview_token", {}],
        logo: [:post, "#{member}/logo", { file: png_upload }], photo: [:post, "#{member}/photo", { file: png_upload }],
        update_people: [:put, "#{member}/people", { user_ids: [world.host.id] }], destroy: [:delete, member, {}]
      }.fetch(name)
    end

    # Negado = 401: é o que o RequestExceptionHandler do upstream devolve para Pundit::NotAuthorizedError,
    # igual a todo módulo com check_module_permission!.
    it 'allows exactly the expected routes per person and denies the rest' do
      people.each do |who, user|
        route_names.each do |name|
          verb, path, params = route(name, create_booking_profile(account: account, host: world.host))
          call(user, verb, path, params)
          allowed = expected[who].include?(name)
          ok = allowed ? response.status.between?(200, 299) : response.status == 401
          expect(ok).to be(true), "#{who} #{name}: got #{response.status}"
        end
      end
    end

    it 'answers 404 on every route when the account flag is off' do
      account.disable_features('crm_booking_v2')
      account.save!

      route_names.each do |name|
        call(admin, *route(name, page))
        expect(response).to have_http_status(:not_found)
        expect(body['error']).to eq('crm.booking_v2.disabled')
      end
    end

    it 'answers 404 when the installation calendar is off' do
      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'false') { call(admin, :get, base) }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST create' do
    it 'creates a DISABLED page from the template with the current user, first funnel and stage' do
      world
      call(admin, :post, base, { template_key: 'sales_30', title: 'Demo' })

      expect(response).to have_http_status(:created)
      created = Crm::AgentBookingProfile.find(body.dig('payload', 'id'))
      expect(created).to have_attributes(
        page_version: 2, enabled: false, template_key: 'sales_30', title: 'Demo', duration_minutes: 30, buffer_minutes: 10,
        min_notice_minutes: 120, booking_window_days: 14, default_assignee_id: admin.id,
        default_pipeline_id: world.pipeline.id, default_stage_id: world.stage.id, inbox_id: nil
      )
      expect(created.locations).to eq([{ 'type' => 'whatsapp_video' }])
    end

    it 'does not make a manager role without CRM access the host (agendamento keys alone are not eligible)' do
      manager = role_user('agendamento_manage')
      call(manager, :post, base, { template_key: 'blank' })

      expect(response).to have_http_status(:created)
      expect(body.dig('payload', 'host')).to be_nil
      expect(body.dig('payload', 'locations')).to eq([])
    end

    it 'makes a manager role that also sees cards the host and starts blank without location' do
      manager = role_user('agendamento_manage', 'crm_view')
      call(manager, :post, base, { template_key: 'blank' })

      expect(response).to have_http_status(:created)
      expect(body.dig('payload', 'host', 'id')).to eq(manager.id)
      expect(body.dig('payload', 'host').keys).to match_array(%w[id name avatar_url])
      expect(body.dig('payload', 'locations')).to eq([])
    end

    it 'refuses an unknown template' do
      call(admin, :post, base, { template_key: 'vip' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.unknown_template')
    end
  end

  describe 'PATCH update' do
    it 'updates the allowed fields' do
      call(admin, :patch, "#{base}/#{page.id}", {
             title: 'Visita', duration_minutes: 45, slot_durations: [60], min_notice_minutes: 60,
             locations: [{ type: 'custom_link', url: 'https://meet.example.com/x' }], brand: { color: '#112233' },
             working_hours: { start_hour: 8, end_hour: 12, weekdays: [1, 3] }
           })

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(title: 'Visita', duration_minutes: 45, slot_durations: [60], min_notice_minutes: 60)
      expect(page.locations).to eq([{ 'type' => 'custom_link', 'url' => 'https://meet.example.com/x' }])
      expect(page.brand).to eq({ 'color' => '#112233' })
      expect(page.weekdays).to eq([1, 3])
    end

    it 'updates the invite text and validity (#1190) and refuses a validity out of 1..30' do
      call(admin, :patch, "#{base}/#{page.id}", { invite_text: 'Oi {nome}: {link}', invite_ttl_days: 3 })

      expect(response).to have_http_status(:ok)
      expect(body['payload']).to include('invite_text' => 'Oi {nome}: {link}', 'invite_ttl_days' => 3)
      expect(page.reload).to have_attributes(invite_text: 'Oi {nome}: {link}', invite_ttl_days: 3)

      call(admin, :patch, "#{base}/#{page.id}", { invite_ttl_days: 31 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.reload.invite_ttl_days).to eq(3)
    end

    it 'refuses a funnel or stage from another account' do
      other = build_booking_world(account: create(:account), host_name: 'Outra')

      call(admin, :patch, "#{base}/#{page.id}", { default_pipeline_id: other.pipeline.id })
      expect(response).to have_http_status(:unprocessable_entity)

      call(admin, :patch, "#{base}/#{page.id}", { default_stage_id: other.stage.id })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.reload.default_pipeline_id).to eq(world.pipeline.id)
    end

    it 'refuses a javascript: link and an invalid color' do
      call(admin, :patch, "#{base}/#{page.id}", { locations: [{ type: 'custom_link', url: 'javascript:alert(1)' }] })
      expect(response).to have_http_status(:unprocessable_entity)

      call(admin, :patch, "#{base}/#{page.id}", { brand: { color: 'red;x' } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.reload.brand).to eq({})
    end

    it 'does not let update change the host, version or inbox' do
      call(admin, :patch, "#{base}/#{page.id}", { default_assignee_id: admin.id, page_version: 1, inbox_id: 999, enabled: false })

      expect(page.reload).to have_attributes(default_assignee_id: world.host.id, page_version: 2, inbox_id: nil, enabled: true)
    end
  end

  describe 'caixa de agenda para Meet/Teams' do
    let(:google) { create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox }

    it 'lista só caixas Google/Microsoft com agenda que a pessoa já enxerga' do
      google
      create(:channel_email, account: account, provider: 'google', calendar_enabled: false)
      call(admin, :get, "#{base}/#{page.id}")

      expect(body['payload']['calendar_options']).to eq([{ 'id' => google.id, 'name' => google.name, 'provider' => 'google' }])
    end

    it 'aceita Meet com a caixa Google escolhida e recusa sem caixa' do
      call(admin, :patch, "#{base}/#{page.id}", { booking_page: { locations: [{ type: 'google_meet' }] } })
      expect(response).to have_http_status(:unprocessable_entity)

      call(admin, :patch, "#{base}/#{page.id}", { booking_page: { calendar_inbox_id: google.id, locations: [{ type: 'google_meet' }] } })
      expect(response).to have_http_status(:ok)
      expect(page.reload.inbox_id).to eq(google.id)
    end

    it 'recusa caixa sem agenda e caixa de outra conta' do
      plain = create(:channel_email, account: account, provider: 'google', calendar_enabled: false).inbox
      foreign = create(:channel_email, account: create(:account), provider: 'google', calendar_enabled: true).inbox

      [plain, foreign].each do |inbox|
        call(admin, :patch, "#{base}/#{page.id}", { booking_page: { calendar_inbox_id: inbox.id } })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('crm.booking_v2.calendar_inbox_invalid')
      end
      expect(page.reload.inbox_id).to be_nil
    end

    it 'aceita durações extras como texto' do
      call(admin, :patch, "#{base}/#{page.id}", { booking_page: { slot_durations: %w[60 15] } })

      expect(response).to have_http_status(:ok)
      expect(page.reload.slot_durations).to eq([60, 15])
    end
  end

  describe 'publish and pause' do
    it 'lists what is missing and keeps the page disabled' do
      blank = create_booking_profile(account: account, host: world.host, enabled: false, locations: [],
                                     default_assignee: nil, working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [] })

      call(admin, :post, "#{base}/#{blank.id}/publish")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include('error' => 'crm.booking_v2.publish_incomplete')
      expect(body['missing']).to match_array(%w[host location working_hours])
      expect(blank.reload.enabled).to be(false)
    end

    it 'refuses to publish when the host lost CRM access' do
      page.update!(enabled: false)
      role = create(:custom_role, account: account, permissions: ['campaign_view'])
      world.host.account_users.find_by(account: account).update!(custom_role: role)

      call(admin, :post, "#{base}/#{page.id}/publish")

      expect(body['missing']).to eq(['host'])
    end

    it 'publishes a complete page and pauses it again' do
      page.update!(enabled: false)

      call(admin, :post, "#{base}/#{page.id}/publish")
      expect(response).to have_http_status(:ok)
      expect(page.reload.enabled).to be(true)

      call(admin, :post, "#{base}/#{page.id}/pause")
      expect(response).to have_http_status(:ok)
      expect(page.reload.enabled).to be(false)
    end

    it 'refuses to publish without a funnel and stage the booking can land on' do
      empty_funnel = account.crm_pipelines.create!(name: 'Sem etapas', created_by: admin, status: :active)
      page.update!(enabled: false, default_pipeline_id: empty_funnel.id, default_stage_id: nil)

      call(admin, :post, "#{base}/#{page.id}/publish")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['missing']).to eq(['pipeline'])
      expect(page.reload.enabled).to be(false)
    end

    it 'pauses a Meet page whose mailbox lost the calendar, but does not publish it again' do
      channel = create(:channel_email, account: account, provider: 'google', calendar_enabled: true)
      page.update!(inbox: channel.inbox, locations: [{ 'type' => 'google_meet' }])
      channel.update!(calendar_enabled: false)

      call(admin, :post, "#{base}/#{page.id}/pause")
      expect(response).to have_http_status(:ok)
      expect(page.reload.enabled).to be(false)

      call(admin, :post, "#{base}/#{page.id}/publish")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.reload.enabled).to be(false)
    end

    it 'refuses a location label over the limit, a long description and an unknown time zone' do
      long_label = 'r' * (Crm::AgentBookingProfile::MAX_TEXT + 1)
      [{ locations: [{ type: 'in_person', label: long_label, address: 'Rua A' }] }, { description: 'd' * 2001 },
       { timezone: 'Marte/Olympus' }].each do |change|
        call(admin, :patch, "#{base}/#{page.id}", change)
        expect(response).to have_http_status(:unprocessable_entity), "#{change.keys.first}: got #{response.status}"
      end
      expect(page.reload.timezone).to eq('America/Sao_Paulo')
    end
  end

  describe 'DELETE destroy' do
    it 'refuses with 409 while there is an upcoming scheduled meeting from the page' do
      create_internal_meeting(world: world, starts_at: 2.days.from_now, metadata: { 'booking_profile_id' => page.id })

      call(admin, :delete, "#{base}/#{page.id}")

      expect(response).to have_http_status(:conflict)
      expect(body).to include('error' => 'crm.booking_v2.has_upcoming_meetings', 'upcoming_meetings_count' => 1)
      expect(Crm::AgentBookingProfile.exists?(page.id)).to be(true)
    end

    it 'deletes a page without upcoming meetings' do
      create_internal_meeting(world: world, starts_at: 2.days.ago, metadata: { 'booking_profile_id' => page.id })

      call(admin, :delete, "#{base}/#{page.id}")

      expect(response).to have_http_status(:no_content)
      expect(Crm::AgentBookingProfile.exists?(page.id)).to be(false)
    end
  end

  describe 'POST preview_token' do
    it 'returns a 1-hour preview token bound to the page and useless for other purposes' do
      call(admin, :post, "#{base}/#{page.id}/preview_token")

      token = body.dig('payload', 'token')
      expect(Crm::BookingV2::Tokens.verify('preview', token)).to eq({ 'p' => page.id })
      expect(Crm::BookingV2::Tokens.verify('form', token)).to be_nil
      expect(Time.zone.parse(body.dig('payload', 'expires_at'))).to be_within(1.minute).of(1.hour.from_now)
    end
  end

  describe 'logo and photo upload' do
    def upload(user, kind, file)
      post "#{base}/#{page.id}/#{kind}", params: { file: file }, headers: user.create_new_auth_token
    end

    def temp_upload(name, content, type)
      file = Tempfile.new([name, File.extname(name)])
      file.binmode
      file.write(content)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, type)
    end

    it 'accepts a PNG logo and returns its URL' do
      upload(admin, :logo, Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo).to be_attached
      expect(body.dig('payload', 'logo_url')).to be_present
    end

    it 'refuses an SVG photo' do
      upload(admin, :photo, temp_upload('x.svg', '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', 'image/svg+xml'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to include('PNG, JPEG or WebP')
      expect(page.reload.photo).not_to be_attached
    end

    # O tipo vem dos bytes, não do nome nem do Content-Type que o navegador manda.
    it 'refuses SVG bytes disguised as logo.png with image/png' do
      svg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
      file = Tempfile.new(['logo', '.png'])
      file.write(svg)
      file.rewind
      upload(admin, :logo, Rack::Test::UploadedFile.new(file.path, 'image/png', original_filename: 'logo.png'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to include('PNG, JPEG or WebP')
      expect(page.reload.logo).not_to be_attached
    end

    it 'refuses an image over 2 MB' do
      png = "\x89PNG\r\n\x1a\n".b + ("\0".b * 3.megabytes)
      upload(admin, :logo, temp_upload('big.png', png, 'image/png'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to include('too large')
      expect(page.reload.logo).not_to be_attached
    end

    it 'refuses a request without a file' do
      upload(admin, :logo, nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.file_missing')
    end
  end

  describe 'people' do
    it 'lists eligible people of the account with id, name and avatar only (no e-mail)' do
      no_access = role_user('campaign_view')
      call(admin, :get, "#{base}/#{page.id}/people")

      expect(response).to have_http_status(:ok)
      expect(body['payload'].map(&:keys).uniq).to eq([%w[id name avatar_url]])
      ids = body['payload'].pluck('id')
      expect(ids).to include(admin.id, world.host.id)
      expect(ids).not_to include(no_access.id)
      expect(response.body).not_to include(admin.email)
    end

    it 'sets one person as fixed host and disables existing links' do
      seller = create(:user, account: account, role: :agent)
      page.agent_booking_links.create!(account: account, agent: seller)

      call(admin, :put, "#{base}/#{page.id}/people", { user_ids: [admin.id] })

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(assignment_mode: 'fixed', default_assignee_id: admin.id)
      expect(page.agent_booking_links.enabled).to be_empty
    end

    it 'sets two or more people as per_agent links without any inbox, disabling who left the list' do
      seller = create(:user, account: account, role: :agent)
      leaver = create(:user, account: account, role: :agent)
      page.agent_booking_links.create!(account: account, agent: leaver)

      call(admin, :put, "#{base}/#{page.id}/people", { user_ids: [seller.id, world.host.id] })

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(assignment_mode: 'per_agent', default_assignee_id: seller.id)
      expect(page.agent_booking_links.enabled.pluck(:agent_id, :inbox_id)).to contain_exactly([seller.id, nil], [world.host.id, nil])
      expect(page.agent_booking_links.find_by(agent: leaver).enabled).to be(false)
      expect(body.dig('payload', 'people').pluck('id')).to contain_exactly(seller.id, world.host.id)
      expect(response.body).not_to include(seller.email)
    end

    it 'refuses people from another account, ineligible people and an empty list' do
      outsider = create(:user, account: create(:account), role: :agent)
      no_access = role_user('campaign_view')

      [[outsider.id], [no_access.id], []].each do |ids|
        call(admin, :put, "#{base}/#{page.id}/people", { user_ids: ids })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('crm.booking_v2.people_invalid')
      end
      expect(page.reload.default_assignee_id).to eq(world.host.id)
    end
  end

  describe 'isolation' do
    it 'answers 404 for a page of another account and for a legacy page' do
      other = build_booking_world(account: create(:account), host_name: 'Outra')
      legacy = account.crm_agent_booking_profiles.new(page_version: 1, title: 'Antiga', enabled: false, slug: SecureRandom.uuid)
      legacy.save!(validate: false)

      [other.profile.id, legacy.id].each do |id|
        call(admin, :get, "#{base}/#{id}")
        expect(response).to have_http_status(:not_found)
        call(admin, :patch, "#{base}/#{id}", { title: 'x' })
        expect(response).to have_http_status(:not_found)
      end
      expect(other.profile.reload.title).not_to eq('x')
    end

    it 'index lists only new pages of the account, with counts and the attention flag' do
      create_internal_meeting(world: world, starts_at: 1.day.from_now, metadata: { 'booking_profile_id' => page.id })
      build_booking_world(account: create(:account), host_name: 'Outra')

      call(admin, :get, base)

      expect(body['payload'].pluck('id')).to eq([page.id])
      expect(body['payload'].first).to include('upcoming_meetings_count' => 1, 'attention' => false, 'enabled' => true,
                                               'missing' => [])
    end

    it 'index tells what a disabled page still needs, so the screen can show Draft or Paused' do
      blank = create_booking_profile(account: account, host: world.host, enabled: false, locations: [],
                                     default_assignee: nil, working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [] })
      page.update!(enabled: false)

      call(admin, :get, base)

      by_id = body['payload'].index_by { |item| item['id'] }
      expect(by_id[blank.id]['missing']).to match_array(%w[host location working_hours])
      expect(by_id[page.id]['missing']).to eq([])
    end
  end

  describe 'legacy booking_profiles controller (regression)' do
    let(:legacy_base) { "/api/v1/accounts/#{account.id}/crm/booking_profiles" }

    it 'stays administrator-only: agendamento_manage is denied' do
      call(role_user('agendamento_manage'), :get, legacy_base)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not list nor edit new pages' do
      page
      call(admin, :get, legacy_base)
      expect(response).to have_http_status(:ok)
      expect(body['payload']).to eq([])

      call(admin, :patch, "#{legacy_base}/#{page.id}", { title: 'x' })
      expect(response).to have_http_status(:not_found)
    end
  end
end
