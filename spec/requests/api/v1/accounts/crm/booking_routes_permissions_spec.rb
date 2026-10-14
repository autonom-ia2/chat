require 'rails_helper'

# Matriz de permissões das rotas do agendamento que ainda não tinham a sua (#1401, RA-21), no molde da matriz de
# `booking_pages_spec.rb`. Página, identidade, foto e pessoas já estão lá; convites e resultados, nos specs deles.
#
# Duas réguas, cada uma a da sua policy:
# - configurar páginas (`Crm::BookingPagePolicy`, módulo `agendamento`): endereço curto, passar reuniões, testar o
#   aviso, modelos de aviso e "Escrever com IA". Escrever pede `agendamento_manage`; criar modelo na Meta, só o
#   administrador (escreve na conta do WhatsApp do cliente, #1272).
# - atender (`HostEligibility`): marcar pela agenda, ações do dia da reunião e "Meus horários". Quem atende é quem vê
#   cards (administrador, agente sem função, função com CRM); as chaves `agendamento_*` sozinhas não bastam.
#
# Negado = 401: é o que o RequestExceptionHandler do upstream devolve para Pundit::NotAuthorizedError.
RSpec.describe 'Agendamento: matriz de permissões das rotas novas', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }

  def role_user(*permissions, inbox:)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: verb == :get ? nil : :json)
  end

  def expect_matrix(people, routes, expected)
    people.each do |who, user|
      routes.each do |name, (status, request)|
        verb, path, params = request.call(user)
        call(user, verb, path, params)
        want = expected.fetch(name).include?(who) ? status : 401
        expect(response.status).to eq(want), "#{who} #{name}: esperado #{want}, veio #{response.status} #{response.body.first(200)}"
      end
    end
  end

  describe 'configurar páginas (BookingPagePolicy)' do
    include ActiveJob::TestHelper

    let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
    let(:cloud) { channel.inbox }
    let(:member) { "#{base}/#{world.profile.id}" }
    # Sem o campo do link: desde o #1517 a IA não o recebe, e opção com ele é descartada (o link vai no botão ou na linha fixa).
    let(:good) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Até lá!' }
    let(:template_ai) { instance_double(Crm::Ai::ResponsesClient) }
    let(:writer_ai) { instance_double(Crm::Ai::ResponsesClient) }
    let(:people) do
      {
        admin: admin, manage: role_user('agendamento_manage', inbox: cloud), view: role_user('agendamento_view', inbox: cloud),
        agent: world.host, other_role: role_user('crm_view', 'crm_admin', inbox: cloud)
      }
    end
    # nome => [status de quem passa, ->(user) { [verbo, caminho, parâmetros] }]
    let(:routes) do
      {
        short_name: [200, ->(_) { [:get, "#{base}/short_name", { name: 'clinica-nova' }] }],
        reassign_preview: [200, ->(_) { [:get, "#{base}/reassign_preview", { from_user_id: world.host.id, to_user_id: admin.id }] }],
        reassign: [200, ->(_) { [:post, "#{base}/reassign", { from_user_id: world.host.id, to_user_id: admin.id }] }],
        # Passou da policy e parou na regra do envio: a página não tem caixa de avisos.
        test_invite: [422, ->(_) { [:post, "#{member}/test_invite", { phone: '+5511912345678' }] }],
        notice_template_suggestions: [200, ->(_) { [:post, "#{member}/notice_template_suggestions", { inbox_id: cloud.id, kinds: %w[booked] }] }],
        notice_templates: [200, ->(_) { [:get, "#{member}/notice_templates", { inbox_id: cloud.id }] }],
        create_notice_templates: [202, ->(_) { [:post, "#{member}/notice_templates/create", { inbox_id: cloud.id, kinds: %w[booked] }] }],
        notice_text_suggestions: [200, ->(_) { [:post, "#{member}/notice_text_suggestions", { kind: 'day_before' }] }]
      }
    end
    # Tudo aqui escreve ou prepara uma escrita: administrador e agendamento_manage. Criar na Meta, só o administrador.
    let(:expected) { routes.keys.index_with { %i[admin manage] }.merge(create_notice_templates: %i[admin]) }

    around do |example|
      with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run }
    end

    before do
      travel_to Time.utc(2026, 10, 12, 11, 0, 0)
      account.enable_features('crm_booking_v2')
      account.save!
      template = { 'name' => 'lembrete_horario', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
                   'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie em {{3}} quando quiser.' }] }
      channel.update_columns(message_templates: [template]) # rubocop:disable Rails/SkipsModelValidations
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
      # IA simulada, uma por feature: a sugestão de modelo (#1272) e o redator do "Escrever com IA" (#1354).
      allow(Crm::Ai::ResponsesClient).to receive(:new) do |feature:, **|
        feature == Crm::BookingV2::NoticeTemplates::Suggester::FEATURE ? template_ai : writer_ai
      end
      allow(template_ai).to receive(:create).and_return(text: { choices: [{ kind: 'booked', index: 0, reason: 'Fala do horário.' }] }.to_json)
      option = { texto: good, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: nil, certeza_categoria: nil, motivo_categoria: nil }
      allow(writer_ai).to receive(:create)
        .and_return(text: { status: 'ok', pergunta: nil, sugestoes: [], problemas_encontrados: [], opcoes: [option] }.to_json)
    end

    it 'deixa cada perfil exatamente nas rotas esperadas e nega o resto com 401' do
      expect_matrix(people, routes, expected)
    end

    it 'quem é negado não muda nada: nem reunião passada, nem modelo pedido à Meta' do
      meeting = create_internal_meeting(world: world, starts_at: Time.utc(2026, 10, 20, 13, 0, 0),
                                        metadata: { 'booking_profile_id' => world.profile.id })

      people.except(:admin, :manage).each_value do |user|
        call(user, :post, "#{base}/reassign", { from_user_id: world.host.id, to_user_id: admin.id })
        call(user, :post, "#{member}/notice_templates/create", { inbox_id: cloud.id, kinds: %w[booked] })
      end
      call(people[:manage], :post, "#{member}/notice_templates/create", { inbox_id: cloud.id, kinds: %w[booked] })

      expect(meeting.reload.created_by_id).to eq(world.host.id)
      expect(enqueued_jobs.count { |job| job['job_class'] == 'Crm::BookingV2::NoticeTemplatesJob' }).to eq(0)
    end
  end

  describe 'atender (HostEligibility)' do
    let(:inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
    let(:meetings) { "/api/v1/accounts/#{account.id}/crm/meetings" }
    let(:people) do
      {
        admin: admin, manage: role_user('agendamento_manage', inbox: inbox), view: role_user('agendamento_view', inbox: inbox),
        agent: world.host, other_role: role_user('crm_view', 'crm_admin', 'conversation_manage', inbox: inbox),
        no_crm: role_user('conversation_manage', inbox: inbox)
      }
    end
    let(:hours) { "/api/v1/accounts/#{account.id}/crm/my_booking_hours" }
    let(:routes) do
      {
        bookable: [200, ->(_) { [:get, "#{base}/bookable"] }],
        slots: [200, ->(_) { [:get, "#{base}/#{world.profile.id}/slots", { date: '2026-10-21' }] }],
        meetings: [201, ->(_) { [:post, "#{base}/#{world.profile.id}/meetings", { card_id: fresh_card.id, starts_at: next_free_slot }] }],
        remind: [200, ->(_) { [:post, "#{meetings}/#{upcoming_with_invite.id}/remind"] }],
        rebook_link: [200, ->(_) { [:post, "#{meetings}/#{no_show.id}/rebook_link"] }],
        my_booking_hours: [200, ->(_) { [:get, hours] }],
        # Grava sem pausar: a agenda pausada de quem atende a página tiraria os horários das marcações seguintes.
        update_my_booking_hours: [200, ->(_) { [:put, hours, { paused: false }] }]
      }
    end
    let(:expected) { routes.keys.index_with { %i[admin agent other_role] } }
    let(:counter) { Hash.new(0) }

    around do |example|
      with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                        'FRONTEND_URL' => 'https://app.example.com') do
        travel_to(Time.zone.parse('2026-10-19T14:00:00Z')) { example.run }
      end
    end

    before do
      account.enable_features('crm_booking_v2')
      account.save!
      world.card.update!(inbox: inbox)
      create(:inbox_member, user: world.host, inbox: inbox)
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)
      # Janela de 24 h aberta pelo cliente: o WhatsApp oficial deixa responder.
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
    end

    # Uma reunião por chamada: lembrar e mandar link têm espera entre um toque e outro, e marcar ocupa o horário e
    # conta no limite de reuniões em aberto do cliente; por isso cada marcação vai para um cliente e um card novos.
    def fresh_card
      number = counter[:clients] += 1
      contact = create_booking_contact(account: account, name: "Cliente #{number}", phone: format('+55119123456%02d', number))
      create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: contact, inbox: inbox)
    end

    def next_free_slot
      format('2026-10-21T%02d:00:00-03:00', 9 + counter[:slots]).tap { counter[:slots] += 1 }
    end

    def upcoming_with_invite
      starts_at = Time.zone.parse('2026-10-20T12:00:00Z') + counter[:upcoming].hours
      counter[:upcoming] += 1
      meeting = create_internal_meeting(world: world, starts_at: starts_at, conversation: conversation,
                                        metadata: { 'booking_profile_id' => world.profile.id })
      create_booking_invite(world: world, conversation: conversation, meeting: meeting, scheduled_at: 1.day.ago, channel: 'conversation')
      meeting
    end

    def no_show
      counter[:finished] += 1
      create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-18T10:00:00Z') + counter[:finished].hours, conversation: conversation,
                              metadata: { 'booking_profile_id' => world.profile.id }, outcome: :no_show, outcome_recorded_at: 1.hour.ago)
    end

    it 'deixa cada perfil exatamente nas rotas esperadas e nega o resto com 401' do
      expect_matrix(people, routes, expected)
    end

    it 'quem é negado não marca, não manda mensagem e não grava horário' do
      upcoming = upcoming_with_invite
      finished = no_show

      people.slice(:manage, :view, :no_crm).each_value do |user|
        call(user, :post, "#{base}/#{world.profile.id}/meetings", { card_id: world.card.id, starts_at: '2026-10-21T15:00:00-03:00' })
        call(user, :post, "#{meetings}/#{upcoming.id}/remind")
        call(user, :post, "#{meetings}/#{finished.id}/rebook_link")
        call(user, :put, hours, { paused: true })
      end

      expect(Crm::Meeting.where(starts_at: Time.zone.parse('2026-10-21T15:00:00-03:00'))).to be_empty
      expect(conversation.messages.outgoing.count).to eq(0)
      expect(Crm::AgentAvailability.count).to eq(0)
    end
  end
end
