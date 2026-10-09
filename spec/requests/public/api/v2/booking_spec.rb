require 'rails_helper'

# Página pública v2 (#1189): 404 uniforme, pausa, prévia, payload sem dado interno, barreiras de robô (honeypot,
# form_token, captcha), reserva pelo link público e pelo convite, idempotência só pela chave do pedido (`request_id`),
# erros públicos fechados (J2, RA-05) e falha nossa como 500 registrado.
RSpec.describe 'Public::Api::V2::Booking', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:slot) { '2026-10-20T10:00:00-03:00' }
  let(:frontend) { 'https://app.example.com' }
  let(:consent) { { accepted: true, text_key: 'booking_v2.consent.whatsapp_notices' } }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => frontend) do
      example.run
    end
  end

  # Segunda-feira, 08:00 em São Paulo.
  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    world.host.update!(email: 'camila.host@example.com', display_name: 'Camila')
  end

  def base(slug = profile.slug)
    "/public/api/v2/booking/#{slug}"
  end

  def form_token(slug = profile.slug, age: 10.seconds)
    Crm::BookingV2::Tokens.generate('form', { 's' => slug, 't' => (Time.current - age).to_i }, expires_in: 2.hours)
  end

  # Cada chamada é uma tentativa nova (chave nova), como no navegador; o reenvio passa a mesma `request_id`.
  def book(slug = profile.slug, **overrides)
    params = { name: 'Ana Souza', phone: '(21) 98888-7777', starts_at: slot, company: '', form_token: form_token(slug), consent: consent,
               request_id: SecureRandom.uuid }
    post base(slug), params: params.merge(overrides), as: :json
  end

  def ask_contact(slug = profile.slug, **overrides)
    params = { name: 'Bruno Reis', phone: '(31) 97777-6666', company: '', form_token: form_token(slug), consent: consent }
    post "#{base(slug)}/contact_request", params: params.merge(overrides), as: :json
  end

  def body
    response.parsed_body
  end

  def expect_not_found
    expect(response).to have_http_status(:not_found)
    expect(body).to eq({ 'error' => 'not_found' })
  end

  def expect_error(code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body).to eq({ 'error' => code })
  end

  # O token do ICS é cifrado com IV aleatório: muda a cada resposta, mas aponta o mesmo convite.
  def expect_same_booking(first)
    expect(body.except('ics_url')).to eq(first.except('ics_url'))
    [first, body].each do |answer|
      token = answer['ics_url'].delete_prefix("#{frontend}/public/api/v2/ics/")
      expect(Crm::BookingV2::Tokens.verify('ics', token)).to eq('c' => answer['manage_url'].delete_prefix("#{frontend}/b/"))
    end
  end

  def expect_unavailable
    expect(response).to have_http_status(:internal_server_error)
    expect(body).to eq({ 'error' => 'unavailable' })
  end

  def expect_every_route_not_found(slug)
    get base(slug)
    expect_not_found
    get "#{base(slug)}/slots", params: { date: '2026-10-20' }
    expect_not_found
    get "#{base(slug)}/next_slot"
    expect_not_found
    book(slug)
    expect_not_found
    ask_contact(slug)
    expect_not_found
  end

  # Caixa de e-mail com agenda Google: exigida por Meet e pela página antiga.
  def google_inbox
    create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
  end

  def per_agent_link(agent)
    profile.update!(assignment_mode: :per_agent)
    profile.agent_booking_links.create!(account: account, agent: agent)
  end

  describe 'GET show' do
    before do
      profile.update!(contact_phone: '+5511933334444', brand: { 'color' => '#1F6FEB', 'headline' => 'Fale com a gente' })
    end

    it 'devolve só o que o cliente precisa, sem e-mail nem id interno' do
      get base

      expect(response).to have_http_status(:ok)
      expect(body.except('form_token')).to eq(
        'slug' => profile.slug, 'paused' => false, 'preview' => false, 'title' => 'Conversa de 30 min', 'description' => nil,
        'agent_name' => 'Camila', 'agent_photo_url' => nil, 'duration_minutes' => 30, 'durations' => [30],
        'timezone' => 'America/Sao_Paulo', 'booking_window_days' => 14, 'weekdays' => [1, 2, 3, 4, 5],
        'brand' => { 'color' => '#1F6FEB', 'headline' => 'Fale com a gente', 'logo_url' => nil, 'photo_url' => nil },
        'locations' => [{ 'type' => 'whatsapp_video', 'label' => 'Vídeo no WhatsApp', 'requires_email' => false }],
        'contact_whatsapp_url' => 'https://wa.me/5511933334444', 'captcha_site_key' => nil, 'notices_enabled' => false
      )
      expect(Crm::BookingV2::Tokens.verify('form', body['form_token'])).to eq('s' => profile.slug, 't' => Time.current.to_i)
      expect(response.body).not_to include('camila.host@example.com')
      [account.id, profile.id, world.host.id, world.pipeline.id].each { |id| expect(body.values).not_to include(id) }
    end

    it 'usa o rótulo escrito pelo dono e marca Meet/Teams como exigindo e-mail' do
      profile.update!(inbox: google_inbox, locations: [{ 'type' => 'in_person', 'label' => 'Escritório Paulista' }, { 'type' => 'google_meet' }])

      get base

      expect(body['locations']).to eq([{ 'type' => 'in_person', 'label' => 'Escritório Paulista', 'requires_email' => false },
                                       { 'type' => 'google_meet', 'label' => 'Google Meet', 'requires_email' => true }])
    end

    it 'manda o endereço só do local presencial, os dias que atende e o fuso com nome IANA' do
      profile.update!(locations: [{ 'type' => 'in_person', 'address' => 'Av. Paulista, 1000' },
                                  { 'type' => 'whatsapp_video', 'address' => 'não sai' }],
                      working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [6, 1, 3] }, timezone: 'Brasilia')

      get base

      expect(body['locations']).to eq([{ 'type' => 'in_person', 'label' => 'Presencial', 'requires_email' => false,
                                         'address' => 'Av. Paulista, 1000' },
                                       { 'type' => 'whatsapp_video', 'label' => 'Vídeo no WhatsApp', 'requires_email' => false }])
      expect(body['weekdays']).to eq([1, 3, 6])
      expect(body['timezone']).to eq('America/Sao_Paulo')
    end

    it 'mostra a chave do captcha só quando a instalação tem a chave do servidor' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('HCAPTCHA_SITE_KEY', '').and_return('site-key-123')

      get base
      expect(body['captcha_site_key']).to be_nil

      allow(GlobalConfigService).to receive(:load).with('HCAPTCHA_SERVER_KEY', '').and_return('server-secret')
      get base
      expect(body['captcha_site_key']).to eq('site-key-123')
      expect(response.body).not_to include('server-secret')
    end

    it 'página pausada devolve só o aviso de pausa e o resto responde 404' do
      profile.update!(enabled: false)

      get base

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        'slug' => profile.slug, 'paused' => true, 'title' => 'Conversa de 30 min',
        'brand' => { 'color' => '#1F6FEB', 'headline' => 'Fale com a gente', 'logo_url' => nil, 'photo_url' => nil },
        'contact_whatsapp_url' => 'https://wa.me/5511933334444'
      )
      get "#{base}/slots", params: { date: '2026-10-20' }
      expect_not_found
      get "#{base}/next_slot"
      expect_not_found
      expect { book }.not_to change(Crm::Meeting, :count)
      expect_not_found
      expect { ask_contact }.not_to change(Crm::Card, :count)
      expect_not_found
    end
  end

  describe '404 uniforme' do
    it 'para slug desconhecido' do
      expect_every_route_not_found(SecureRandom.uuid)
    end

    it 'para página antiga (page_version 1)' do
      profile.update!(page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: google_inbox)
      expect_every_route_not_found(profile.slug)
    end

    it 'com a flag da conta desligada' do
      account.disable_features('crm_booking_v2')
      account.save!
      expect_every_route_not_found(profile.slug)
    end

    it 'com o calendário da instalação desligado' do
      with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'false') { expect_every_route_not_found(profile.slug) }
    end

    it 'com responsável que não pode mais atender' do
      role = create(:custom_role, account: account, permissions: ['agendamento_view'])
      world.host.account_users.find_by(account: account).update!(custom_role: role)
      expect_every_route_not_found(profile.slug)
    end

    it 'para o slug-base de página per_agent e para link de página antiga' do
      link = per_agent_link(world.host)
      expect_every_route_not_found(profile.slug)

      profile.update!(page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: google_inbox)
      expect_every_route_not_found(link.slug)
    end
  end

  describe 'link individual (per_agent)' do
    let(:seller) { create(:user, account: account, role: :agent, name: 'Rita Lopes', display_name: 'Rita') }
    let!(:link) { per_agent_link(seller) }

    it 'mostra a pessoa do link e reserva no nome dela' do
      get base(link.slug)
      expect(body).to include('slug' => link.slug, 'agent_name' => 'Rita')

      book(link.slug)

      expect(response).to have_http_status(:created)
      meeting = Crm::Meeting.last
      expect(meeting).to have_attributes(created_by_id: seller.id)
      expect(meeting.metadata).to include('booking_profile_id' => profile.id, 'booking_link_id' => link.id)
      expect(Crm::BookingInvite.last).to have_attributes(booking_link_id: link.id, channel: 'public')
    end

    it 'link pausado mostra o aviso de pausa' do
      link.update!(enabled: false)

      get base(link.slug)

      expect(body).to include('paused' => true, 'slug' => link.slug)
    end
  end

  describe 'prévia' do
    before { profile.update!(enabled: false) }

    let!(:preview) { Crm::BookingV2::Tokens.generate('preview', { 'p' => profile.id }, expires_in: 1.hour) }

    it 'lê a página despublicada e os horários, mas nunca reserva' do
      get base, params: { preview: preview }
      expect(body).to include('paused' => false, 'preview' => true, 'title' => 'Conversa de 30 min')

      get "#{base}/slots", params: { date: '2026-10-20', preview: preview }
      expect(body['slots']).to include(slot)

      expect { post "#{base}?preview=#{preview}", params: { name: 'Ana', phone: '21988887777', starts_at: slot, form_token: form_token }, as: :json }
        .not_to change(Crm::Meeting, :count)
      expect_not_found
    end

    it 'ignora token de outra página, de outro propósito ou vencido' do
      other = create_booking_profile(account: account, host: world.host)
      tokens = [Crm::BookingV2::Tokens.generate('preview', { 'p' => other.id }, expires_in: 1.hour),
                Crm::BookingV2::Tokens.generate('form', { 'p' => profile.id }, expires_in: 1.hour), 'lixo']
      tokens.each do |token|
        get base, params: { preview: token }
        expect(body['paused']).to be(true)
      end

      travel 61.minutes
      get base, params: { preview: preview }
      expect(body['paused']).to be(true)
    end
  end

  describe 'GET slots e next_slot' do
    it 'devolve os horários livres do dia em ISO8601 com o fuso da página' do
      get "#{base}/slots", params: { date: '2026-10-20' }

      expect(response).to have_http_status(:ok)
      expect(body['date']).to eq('2026-10-20')
      expect(body['slots'].first).to eq('2026-10-20T09:00:00-03:00')
      expect(body['slots']).to include(slot)
    end

    it 'devolve lista vazia para data inválida e booking_failed para duração que a página não oferece' do
      get "#{base}/slots", params: { date: 'amanhã' }
      expect(body).to eq('date' => nil, 'slots' => [])

      get "#{base}/slots", params: { date: '2026-10-20', duration: 45 }
      expect_error('booking_failed')
    end

    it 'aponta o próximo horário livre' do
      get "#{base}/next_slot"

      expect(body).to eq('starts_at' => '2026-10-12T09:00:00-03:00')
    end
  end

  describe 'POST reserva pelo link público' do
    describe 'reserva que dá certo' do
      before { book }

      let(:meeting) { Crm::Meeting.sole }
      let(:invite) { Crm::BookingInvite.sole }

      it 'confirma na hora, com link de gestão e de calendário, sem dado pessoal' do
        expect(response).to have_http_status(:created)
        expect(body.except('ics_url')).to eq(
          'confirmed' => true, 'starts_at' => '2026-10-20T10:00:00-03:00', 'ends_at' => '2026-10-20T10:30:00-03:00',
          'timezone' => 'America/Sao_Paulo', 'location' => { 'type' => 'whatsapp_video' },
          'manage_url' => "#{frontend}/b/#{invite.code}", 'contact_whatsapp_url' => nil, 'notice_will_send' => false
        )
        expect(body['ics_url']).to start_with("#{frontend}/public/api/v2/ics/")
        %w[+5521988887777 5521988887777 camila.host@example.com].each { |secret| expect(response.body).not_to include(secret) }
        [meeting.id, meeting.card_id, invite.id, account.id].each { |id| expect(body.values).not_to include(id) }
      end

      it 'cria contato sem e-mail, card no funil da página e reunião interna com consentimento' do
        expect(meeting).to have_attributes(provider: 'internal', source: 'public_link', status: 'scheduled', created_by_id: world.host.id)
        expect(meeting.metadata['consent']).to eq('accepted_at' => Time.current.iso8601, 'text_key' => 'booking_v2.consent.whatsapp_notices')
        expect(meeting.card).to have_attributes(source: 'public_link', pipeline_id: world.pipeline.id, stage_id: world.stage.id,
                                                owner_id: world.host.id)
        expect(meeting.card.contact).to have_attributes(name: 'Ana Souza', phone_number: '+5521988887777', email: nil)
      end

      it 'cria o convite público que vira o link de gestão' do
        expect(invite).to have_attributes(channel: 'public', meeting_id: meeting.id, contact_id: meeting.card.contact_id,
                                          card_id: meeting.card_id, scheduled_at: Time.current, state: 'scheduled')
      end
    end

    it 'não grava consentimento sem o aceite' do
      book(consent: { accepted: false, text_key: 'booking_v2.consent.whatsapp_notices' })

      expect(Crm::Meeting.last.metadata).not_to have_key('consent')
    end

    it 'o reenvio com a mesma request_id devolve 200 com a mesma reserva, sem duplicar' do
      book(request_id: 'tentativa-0001-abcdef')
      first = body
      expect(response).to have_http_status(:created)
      travel 1.minute

      expect { book(request_id: 'tentativa-0001-abcdef', phone: '+55 21 98888-7777') }.not_to change(Crm::Meeting, :count)

      expect(response).to have_http_status(:ok)
      expect_same_booking(first)
      expect(Crm::BookingInvite.sole.metadata).to eq('request_id' => 'tentativa-0001-abcdef')
      expect(Crm::Meeting.sole.metadata['booking_request_id']).to eq('tentativa-0001-abcdef')
    end

    # B1: quem sabe o telefone e o horário de outra pessoa não recebe a reunião dela (link de gestão, ICS, endereço).
    describe 'reunião de outra pessoa no mesmo horário' do
      before do
        profile.update!(locations: [{ 'type' => 'in_person', 'address' => 'Av. Paulista, 1000' }])
        book(request_id: 'chave-da-vitima-0001', location_type: 'in_person')
        travel 1.minute
      end

      let!(:victim_invite) { Crm::BookingInvite.sole }

      def expect_nothing_leaked
        expect_error('slot_unavailable')
        expect(response.body).not_to include(victim_invite.code)
        expect(response.body).not_to include('Paulista')
        expect(Crm::BookingInvite.sole).to eq(victim_invite)
        expect(Crm::Meeting.count).to eq(1)
      end

      it 'recusa o estranho com o telefone em outro formato, outro nome e sem chave' do
        book(name: 'Atacante', phone: '21988887777', location_type: 'in_person', request_id: nil)
        expect_nothing_leaked
      end

      it 'recusa o estranho com outra chave' do
        book(name: 'Atacante', phone: '+55 (21) 98888-7777', location_type: 'in_person', request_id: 'chave-do-atacante-01')
        expect_nothing_leaked
      end

      it 'recusa chave fora do formato sem criar nada' do
        ['curta', 'a' * 65, 'chave com espaço 0001', 'chave-com-acento-é-01'].each do |bad|
          expect { book(request_id: bad, starts_at: '2026-10-20T11:00:00-03:00', location_type: 'in_person') }
            .not_to change(Crm::Meeting, :count)
          expect_error('booking_failed')
        end
      end
    end

    it 'nunca cria convite público para reunião que nasceu por outro caminho (IA, painel)' do
      meeting = create_internal_meeting(world: world, starts_at: Time.iso8601(slot), metadata: { 'booking_profile_id' => profile.id })

      expect { book(phone: world.contact.phone_number, request_id: 'qualquer-chave-0001') }.not_to change(Crm::BookingInvite, :count)

      expect_error('slot_unavailable')
      expect(Crm::Meeting.sole).to eq(meeting)
    end

    it 'devolve o link da reunião e o endereço quando o local tem' do
      profile.update!(locations: [{ 'type' => 'custom_link', 'url' => 'https://meet.example.com/sala' },
                                  { 'type' => 'in_person', 'address' => 'Av. Paulista, 1000' }])

      book(location_type: 'custom_link')
      expect(body['location']).to eq('type' => 'custom_link', 'join_url' => 'https://meet.example.com/sala')

      book(location_type: 'in_person', starts_at: '2026-10-20T11:00:00-03:00')
      expect(body['location']).to eq('type' => 'in_person', 'address' => 'Av. Paulista, 1000')
    end

    describe 'barreiras de robô' do
      it 'recusa sem form_token, de outro slug, novo demais e velho demais' do
        other = create_booking_profile(account: account, host: world.host)
        [nil, form_token(other.slug), form_token(age: 1.second), form_token(age: 2.hours + 1.second), 'lixo'].each do |token|
          expect { book(form_token: token) }.not_to change(Crm::Meeting, :count)
          expect_error('booking_failed')
        end
      end

      it 'recusa o honeypot preenchido' do
        expect { book(company: 'Acme') }.not_to change(Crm::Meeting, :count)
        expect_error('booking_failed')
      end

      it 'confere o captcha quando a instalação tem a chave do servidor' do
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('HCAPTCHA_SERVER_KEY', '').and_return('server-secret')
        verdict = instance_double(HTTParty::Response, success?: true, parsed_response: { 'success' => false })
        allow(HTTParty).to receive(:post).with('https://hcaptcha.com/siteverify', anything).and_return(verdict)

        expect { book }.not_to change(Crm::Meeting, :count)
        expect_error('booking_failed')
        expect { book(captcha_token: 'wrong') }.not_to change(Crm::Meeting, :count)
        expect_error('booking_failed')

        allow(verdict).to receive(:parsed_response).and_return({ 'success' => true })
        book(captcha_token: 'right')
        expect(response).to have_http_status(:created)
        expect(HTTParty).to have_received(:post).with('https://hcaptcha.com/siteverify', body: { response: 'right', secret: 'server-secret' })
      end
    end

    describe 'erros públicos' do
      it 'traduz os erros do formulário para o conjunto público' do
        book(phone: '123')
        expect_error('invalid_phone')
        book(name: '<b></b>')
        expect_error('invalid_name')
        book(email: 'não é e-mail')
        expect_error('invalid_email')
        book(starts_at: '2026-10-20T03:00:00-03:00')
        expect_error('slot_unavailable')
      end

      it 'pede e-mail para Google Meet' do
        profile.update!(inbox: google_inbox, locations: [{ 'type' => 'google_meet' }])

        book(location_type: 'google_meet')

        expect_error('email_required')
      end

      it 'recusa a terceira reunião aberta do mesmo número' do
        create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
        create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-22T13:00:00Z'))

        expect { book(phone: '+5511912345678') }.not_to change(Crm::Meeting, :count)
        expect_error('too_many_open')
      end

      it 'reduz os outros códigos conhecidos a booking_failed, sem detalhe interno' do
        book(location_type: 'teams')
        expect_error('booking_failed')
      end

      it 'falha nossa vira 500 genérico registrado no rastreador, sem a mensagem no log' do
        tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:info)
        errors = [RuntimeError.new('PG::Error at +5521988887777'), ArgumentError.new('invalid value for Integer(): "Ana Souza"')]

        errors.each do |error|
          allow(Crm::BookingV2::PublicBooking).to receive(:new).and_raise(error)
          book
          expect_unavailable
          expect(response.body).not_to include('5521988887777')
          expect(ChatwootExceptionTracker).to have_received(:new).with(error)
        end
        expect(tracker).to have_received(:capture_exception).twice
        expect(Rails.logger).to have_received(:error).with('Public booking v2 error: RuntimeError')
        expect(Rails.logger).to have_received(:error).with('Public booking v2 error: ArgumentError')
        %w[error info].each do |level|
          expect(Rails.logger).not_to have_received(level).with(include('invalid value for Integer'))
          expect(Rails.logger).not_to have_received(level).with(include('PG::Error'))
        end
      end
    end
  end

  describe 'POST reserva pelo convite' do
    let(:invite) { create_booking_invite(world: world) }

    it 'usa o contato, o telefone e o card do convite e marca o convite como agendado' do
      expect { book(invite_code: invite.code, phone: nil) }.not_to change(Crm::Card, :count)

      expect(response).to have_http_status(:created)
      meeting = Crm::Meeting.last
      expect(meeting).to have_attributes(card_id: world.card.id, source: 'invite')
      expect(meeting.meeting_guests.pluck(:phone_number, :contact_id)).to eq([['+5511912345678', world.contact.id]])
      expect(invite.reload).to have_attributes(meeting_id: meeting.id, scheduled_at: Time.current, state: 'scheduled')
      expect(body['manage_url']).to eq("#{frontend}/b/#{invite.code}")
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'usa o telefone digitado quando o contato do convite não tem telefone, sem trocar o contato' do
      world.contact.update!(phone_number: nil, email: 'marcos@example.com')

      expect { book(invite_code: invite.code) }.not_to change(Contact, :count)

      expect(response).to have_http_status(:created)
      guest = Crm::Meeting.last.meeting_guests.find_by(guest_type: :contact_guest)
      expect(guest).to have_attributes(contact_id: world.contact.id, phone_number: '+5521988887777')
      expect(world.contact.reload.phone_number).to be_nil
    end

    it 'usa o número trocado pelo cliente só nesta reunião, sem mudar o contato' do
      book(invite_code: invite.code, phone: '(21) 98888-7777')

      expect(response).to have_http_status(:created)
      guest = Crm::Meeting.last.meeting_guests.find_by(guest_type: :contact_guest)
      expect(guest).to have_attributes(contact_id: world.contact.id, phone_number: '+5521988887777')
      expect(world.contact.reload.phone_number).to eq('+5511912345678')
    end

    it 'reunião marcada por convite de "Testar no meu WhatsApp" leva a marca de teste e fica fora de Crm::Meeting.real (#1192)' do
      invite.update!(metadata: { 'test' => true })

      book(invite_code: invite.code)

      expect(response).to have_http_status(:created)
      meeting = Crm::Meeting.sole
      expect(meeting.metadata).to include('test' => true, 'booking_profile_id' => profile.id)
      expect(Crm::Meeting.real).to be_empty
    end

    it 'reunião de convite comum fica em Crm::Meeting.real, sem marca de teste' do
      book(invite_code: invite.code)

      expect(response).to have_http_status(:created)
      expect(Crm::Meeting.sole.metadata).not_to have_key('test')
      expect(Crm::Meeting.real.pluck(:id)).to eq([Crm::Meeting.sole.id])
    end

    it 'o reenvio com a mesma request_id devolve 200 com a mesma reserva; sem ela, recusa' do
      book(invite_code: invite.code, request_id: 'tentativa-convite-0001')
      first = body

      expect { book(invite_code: invite.code, request_id: 'tentativa-convite-0001') }.not_to change(Crm::Meeting, :count)
      expect(response).to have_http_status(:ok)
      expect_same_booking(first)
      expect(invite.reload.metadata).to include('request_id' => 'tentativa-convite-0001')

      [nil, 'outra-tentativa-00001'].each do |other|
        book(invite_code: invite.code, request_id: other)
        expect_error('booking_failed')
      end
    end

    # A reunião que o convite recebe é sempre do contato do convite, mesmo quando o número digitado é de outra pessoa
    # que já tem reunião naquele horário com a mesma chave.
    it 'recusa quando a reunião encontrada é de outro contato e não marca o convite' do
      book(name: 'Bruna', phone: '(21) 97777-1111', request_id: 'chave-repetida-00001')
      other_meeting = Crm::Meeting.sole

      expect { book(invite_code: invite.code, phone: '(21) 97777-1111', request_id: 'chave-repetida-00001') }
        .not_to change(Crm::Meeting, :count)

      expect_error('booking_failed')
      expect(response.body).not_to include(Crm::BookingInvite.find_by!(meeting_id: other_meeting.id).code)
      expect(invite.reload).to have_attributes(scheduled_at: nil, meeting_id: nil)
    end

    it 'com o número de outro contato, a reunião fica no contato do convite e o outro não muda' do
      other = account.contacts.create!(name: 'Bruna', phone_number: '+5521977771111')

      book(invite_code: invite.code, phone: '(21) 97777-1111')

      expect(response).to have_http_status(:created)
      meeting = Crm::Meeting.sole
      expect(meeting.card.contact_id).to eq(world.contact.id)
      guest = meeting.meeting_guests.find_by(guest_type: :contact_guest)
      expect(guest).to have_attributes(contact_id: world.contact.id, phone_number: '+5521977771111')
      expect(Crm::Card.where(contact_id: other.id)).to be_empty
    end

    it 'recusa convite de outra página, já agendado em outra hora, cancelado, vencido ou de outra conta' do
      other_page = create_booking_profile(account: account, host: world.host)
      foreign_world = build_booking_world(account: create(:account))
      scheduled = create_booking_invite(world: world, scheduled_at: 10.minutes.ago,
                                        meeting: create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z')))
      codes = [create_booking_invite(world: world, booking_profile: other_page).code, scheduled.code,
               create_booking_invite(world: world, canceled_at: 1.minute.ago).code,
               create_booking_invite(world: world, expires_at: 1.minute.ago).code,
               create_booking_invite(world: foreign_world).code, 'NAOEXISTE']

      codes.each do |code|
        expect { book(invite_code: code) }.not_to change(Crm::Meeting, :count)
        expect_error('booking_failed')
      end
    end
  end

  # RA-08: fuso inválido gravado antes da validação nunca vira outro fuso em silêncio.
  describe 'fuso da página gravado inválido' do
    # Dado gravado antes da validação de fuso: só dá para reproduzir pulando a validação.
    before { profile.update_column(:timezone, 'Marte/Olympus') } # rubocop:disable Rails/SkipsModelValidations

    it 'responde 500 registrado em página, horários e reserva, sem criar nada' do
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      get base
      expect_unavailable
      get "#{base}/slots", params: { date: '2026-10-20' }
      expect_unavailable
      get "#{base}/next_slot"
      expect_unavailable
      expect { book }.not_to change(Crm::Meeting, :count)
      expect_unavailable

      expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(Crm::BookingV2::PublicPage::InvalidTimeZone)).exactly(4).times
    end
  end

  it 'confirma no fuso da página, sem cair no fuso do servidor' do
    profile.update!(timezone: 'America/Manaus')

    book(starts_at: '2026-10-20T10:00:00-04:00')

    expect(response).to have_http_status(:created)
    expect(body).to include('starts_at' => '2026-10-20T10:00:00-04:00', 'ends_at' => '2026-10-20T10:30:00-04:00',
                            'timezone' => 'America/Manaus')
  end

  describe 'POST contact_request' do
    describe 'pedido que dá certo' do
      before { ask_contact }

      let(:card) { Crm::Card.find_by!(source: 'contact_request') }

      it 'cria contato e card de pedido de contato no funil da página, com o responsável' do
        expect(response).to have_http_status(:created)
        expect(body).to eq('requested' => true)
        expect(card).to have_attributes(pipeline_id: world.pipeline.id, stage_id: world.stage.id, owner_id: world.host.id)
        expect(card.contact).to have_attributes(name: 'Bruno Reis', phone_number: '+5531977776666')
        expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_CREATED)
      end

      it 'avisa o responsável com uma ligação vencendo agora e registra a atividade' do
        follow_up = Crm::FollowUp.sole
        expect(follow_up).to have_attributes(card_id: card.id, follow_up_type: 'call', status: 'pending', assignee_id: world.host.id,
                                             due_at: Time.current, title: 'Ligar para Bruno Reis: pediu contato pela página de agendamento')
        expect(follow_up.metadata).to include('source' => 'booking_contact_request', 'booking_profile_id' => profile.id)
        expect(card.activities.pluck(:event_type)).to include('booking_contact_requested')
      end
    end

    it 'acha o contato existente pelo telefone sem renomear' do
      ask_contact(phone: '+5511912345678', name: 'Outro Nome')

      expect(Crm::Card.last.contact).to eq(world.contact)
      expect(world.contact.reload.name).to eq('Marcos Lima')
    end

    it 'aceita no máximo 2 pedidos abertos por telefone por dia' do
      2.times { ask_contact }
      expect { ask_contact }.not_to change(Crm::Card, :count)
      expect_error('too_many_open')

      travel 25.hours
      ask_contact
      expect(response).to have_http_status(:created)
    end

    describe 'pelo link do cliente (invite_code)' do
      let(:invite) { create_booking_invite(world: world) }

      it 'usa o contato e o card aberto do convite, sem pedir nome nem telefone de novo' do
        expect { ask_contact(invite_code: invite.code, name: nil, phone: nil) }
          .not_to(change { [Contact.count, Crm::Card.count] })

        expect(response).to have_http_status(:created)
        follow_up = Crm::FollowUp.sole
        expect(follow_up).to have_attributes(card_id: world.card.id, contact_id: world.contact.id)
        expect(world.card.activities.pluck(:event_type)).to include('booking_contact_requested')
        expect(Crm::Cards::Broadcaster).not_to have_received(:broadcast)
      end

      it 'abre card novo no contato do convite quando o card do convite já fechou' do
        world.card.update!(status: :won)

        expect { ask_contact(invite_code: invite.code, name: nil, phone: nil) }.not_to change(Contact, :count)

        expect(response).to have_http_status(:created)
        expect(Crm::Card.find_by!(source: 'contact_request').contact_id).to eq(world.contact.id)
      end

      it 'recusa convite cancelado, de outra página ou inexistente sem criar nada' do
        other_page = create_booking_profile(account: account, host: world.host)
        codes = [create_booking_invite(world: world, canceled_at: 1.minute.ago).code,
                 create_booking_invite(world: world, booking_profile: other_page).code, 'NAOEXISTE']

        codes.each do |code|
          expect { ask_contact(invite_code: code, name: nil, phone: nil) }.not_to change(Crm::FollowUp, :count)
          expect_error('booking_failed')
        end
      end
    end

    it 'recusa robô e telefone inválido sem criar nada' do
      expect { ask_contact(company: 'Acme') }.not_to change(Crm::Card, :count)
      expect_error('booking_failed')
      expect { ask_contact(form_token: form_token(age: 3.hours)) }.not_to change(Crm::Card, :count)
      expect_error('booking_failed')
      ask_contact(phone: 'abc')
      expect_error('invalid_phone')
    end
  end
end
