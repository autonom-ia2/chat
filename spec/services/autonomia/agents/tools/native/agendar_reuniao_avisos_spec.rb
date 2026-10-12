require 'rails_helper'

# A agenda da IA completa (#1305): a reunião marcada pela IA agenda os avisos pelo mesmo ponto da página e do painel
# (`BookingNotices`), sem repetir a confirmação na mesma conversa; o retorno ao modelo traz o link de gestão e o local;
# página que não marca tira a agenda do turno; a confirmação do cliente é um parâmetro decidido pelo modelo; e nada
# atravessa conta ou contato.
RSpec.describe Autonomia::Agents::Tools::Native::AgendarReuniao do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:inbox) { create(:inbox, account: account) }
  let(:notice_inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 77) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agenda', agent_type: 'scheduler', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'booking_page_id' => profile.id })
  end
  let(:agenda) { Autonomia::Agents::Tools::Native::Agenda }
  let(:horarios_tool) { Autonomia::Agents::Tools::Native::HorariosDisponiveis }
  let(:slot) { '2026-10-20T10:00:00-03:00' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') { example.run }
  end

  # Segunda-feira, 08:00 em São Paulo.
  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features!('crm_booking_v2')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    world.card.update!(conversation_id: conversation.id)
  end

  def agendar(entrega: delivery, **extra)
    params = { 'inicio' => slot, 'cliente_confirmou' => true }.merge(extra.stringify_keys)
    described_class.new(agent: agent, params: params, delivery: entrega).call
  end

  def horarios
    horarios_tool.new(agent: agent, params: {}, delivery: delivery).call
  end

  def entrega_em(conversa, mensagem)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil, origin_message_id: mensagem)
  end

  def kinds_e_status(meeting)
    meeting.notices.order(:due_at).pluck(:kind, :status, :skip_reason)
  end

  describe 'avisos e link de gestão' do
    it 'agenda o aviso e os lembretes pela caixa de avisos e registra a base e quem marcou' do
      profile.update!(notice_inbox: notice_inbox)

      resposta = JSON.parse(agendar)

      meeting = Crm::Meeting.sole
      invite = Crm::BookingInvite.sole
      expect(meeting.metadata).to include('notify_client' => true, 'notice_basis' => described_class::NOTICE_BASIS,
                                          'booked_by_agent_id' => agent.id, 'booked_in_conversation_id' => conversation.id)
      expect(kinds_e_status(meeting)).to eq([['booked', 'pending', nil], ['day_before', 'pending', nil], ['hour_before', 'pending', nil]])
      expect(resposta).to include('marcada' => true, 'inicio' => slot, 'duracao_minutos' => 30,
                                  'link_de_gestao' => "https://app.example.com/b/#{invite.code}")
      expect(resposta['resumo']).to include('Reunião marcada', 'terça-feira, 20/10, 10:00')
      expect(resposta['instrucao']).to include('link_de_gestao')
    end

    describe 'na mesma caixa da conversa' do
      let(:conversa) { create(:conversation, account: account, inbox: notice_inbox, contact: world.contact) }

      before do
        create(:message, account: account, inbox: notice_inbox, conversation: conversa, message_type: :incoming, created_at: 1.hour.ago)
        world.card.update!(conversation_id: conversa.id)
        profile.update!(notice_inbox: notice_inbox)
        agendar(entrega: entrega_em(conversa, 80))
      end

      def despachar_depois_da_folga
        travel Crm::BookingV2::BookingNotices::CONFIRMATION_GRACE + 1.minute
        Crm::BookingV2::NoticeDispatchJob.perform_now
      end

      def link_de_gestao
        "https://app.example.com/b/#{Crm::BookingInvite.sole.code}"
      end

      def saida(conteudo)
        create(:message, account: account, inbox: notice_inbox, conversation: conversa, message_type: :outgoing, content: conteudo)
      end

      def ouvir(mensagem)
        Crm::BookingNoticeToldListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem))
      end

      def status_do_marcado
        Crm::Meeting.sole.notices.find_by(kind: 'booked').slice(:status, :skip_reason).values
      end

      it 'o "ao marcar" espera a resposta; a resposta da IA com o link o pula na hora e os lembretes seguem' do
        meeting = Crm::Meeting.sole
        expect(meeting.notices.find_by(kind: 'booked').due_at).to eq(Time.current + Crm::BookingV2::BookingNotices::CONFIRMATION_GRACE)
        expect { Crm::BookingV2::NoticeDispatchJob.perform_now }.not_to change(Message, :count)

        ouvir(saida("Marcado! Para mudar ou cancelar: #{link_de_gestao}"))

        expect(kinds_e_status(meeting)).to eq(
          [['booked', 'skipped', Crm::BookingV2::BookingNotices::TOLD_IN_CONVERSATION], ['day_before', 'pending', nil],
           ['hour_before', 'pending', nil]]
        )
        expect { despachar_depois_da_folga }.not_to change(Message, :count)
        # Pulo esperado: o responsável não é chamado (só fica a tarefa de lembrete da própria reunião).
        expect(Crm::FollowUp.pluck(:metadata).pluck('source')).not_to include(Crm::BookingV2::Notices::AgentAlert::SOURCE)
      end

      it 'resposta gravada antes do cron mas ouvida depois dele: o envio confere e não duplica' do
        resposta = saida("Pronto: #{link_de_gestao}")

        expect { despachar_depois_da_folga }.not_to change(Message, :count)
        expect(status_do_marcado).to eq(['skipped', Crm::BookingV2::BookingNotices::TOLD_IN_CONVERSATION])

        expect { ouvir(resposta) }.not_to(change { Crm::MeetingNotice.order(:id).pluck(:status, :skip_reason) })
      end

      it 'resposta com o link gravada com o aviso já em envio (depois da primeira conferência): não duplica' do
        travel Crm::BookingV2::BookingNotices::CONFIRMATION_GRACE + 1.minute
        allow_any_instance_of(Crm::BookingV2::Notices::Route).to receive(:decide).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          saida("Marcado: #{link_de_gestao}") if conversa.messages.outgoing.none?
          original.call(*args)
        end

        expect { Crm::BookingV2::NoticeDispatchJob.perform_now }.to change { conversa.messages.outgoing.count }.by(1)
        expect(conversa.messages.outgoing.last.content).to eq("Marcado: #{link_de_gestao}")
        expect(status_do_marcado).to eq(['skipped', Crm::BookingV2::BookingNotices::TOLD_IN_CONVERSATION])
      end

      it 'pessoa da equipe respondeu sem o link e a IA não: o aviso sai com o link' do
        ouvir(saida('Oi! Já vejo seu horário.'))
        ouvir(saida('Segue o link da outra reunião: https://app.example.com/b/OUTRO123'))

        expect(status_do_marcado).to eq(['pending', nil])
        expect { despachar_depois_da_folga }.to change { conversa.messages.outgoing.count }.by(1)
        expect(conversa.messages.outgoing.last.content).to include(link_de_gestao)
      end

      it 'nota privada com o link não conta como confirmação ao cliente' do
        nota = create(:message, account: account, inbox: notice_inbox, conversation: conversa, message_type: :outgoing,
                                private: true, content: link_de_gestao)
        ouvir(nota)

        expect(status_do_marcado).to eq(['pending', nil])
      end

      it 'se a IA não chegou a responder (o turno morreu), o cliente recebe o "ao marcar" com o link' do
        expect { despachar_depois_da_folga }.to change { conversa.messages.outgoing.count }.by(1)
        expect(conversa.messages.outgoing.last.content).to include("/b/#{Crm::BookingInvite.sole.code}")
      end
    end

    it 'em outra caixa: o "ao marcar" sai na conversa de avisos, e não na conversa da IA' do
      conversa_de_avisos = create(:conversation, account: account, inbox: notice_inbox, contact: world.contact)
      create(:message, account: account, inbox: notice_inbox, conversation: conversa_de_avisos, message_type: :incoming,
                       created_at: 1.hour.ago)
      profile.update!(notice_inbox: notice_inbox)
      agendar

      expect { Crm::BookingV2::NoticeDispatchJob.perform_now }.to change { conversa_de_avisos.messages.outgoing.count }.by(1)
      expect(conversation.messages.count).to eq(0)
      expect(conversa_de_avisos.messages.outgoing.last.content).to include("/b/#{Crm::BookingInvite.sole.code}")
    end

    it 'sem caixa de avisos: nenhum aviso, e o link de gestão volta ao modelo mesmo assim' do
      resposta = JSON.parse(agendar)

      expect(Crm::MeetingNotice.count).to eq(0)
      expect(resposta['link_de_gestao']).to eq("https://app.example.com/b/#{Crm::BookingInvite.sole.code}")
    end

    it 'o reenvio do mesmo turno não duplica reunião, convite nem avisos' do
      profile.update!(notice_inbox: notice_inbox)

      2.times { agendar }

      expect([Crm::Meeting.count, Crm::BookingInvite.count, Crm::MeetingNotice.count]).to eq([1, 1, 3])
    end

    it 'falha ao agendar os avisos não desfaz a reunião nem a confirmação' do
      profile.update!(notice_inbox: notice_inbox)
      allow_any_instance_of(Crm::BookingV2::Notices::Scheduler).to receive(:schedule!).and_raise(StandardError, 'falhou') # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      expect(JSON.parse(agendar)).to include('marcada' => true)
      expect(Crm::Meeting.count).to eq(1)
      expect(ChatwootExceptionTracker).to have_received(:new)
    end

    it 'devolve o link da reunião quando o local é um link' do
      profile.update!(locations: [{ 'type' => 'custom_link', 'url' => 'https://reuniao.exemplo.com/sala' }])

      expect(JSON.parse(agendar)).to include('link_da_reuniao' => 'https://reuniao.exemplo.com/sala')
    end

    it 'devolve o endereço quando o local é presencial' do
      profile.update!(locations: [{ 'type' => 'in_person', 'address' => 'Rua das Flores, 10' }])

      resposta = JSON.parse(agendar)
      expect(resposta).to include('endereco' => 'Rua das Flores, 10')
      expect(resposta).not_to have_key('link_da_reuniao')
    end
  end

  describe 'página que não marca' do
    def sem_agenda_no_turno(motivo)
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent.reload)).to be_empty
      expect(agenda.instrucao(agent)).to include('# Agenda', "indisponível agora (motivo: #{motivo})", 'should_handoff=true')
      expect(agenda.instrucao(agent)).not_to include('chame `horarios_disponiveis`')
      expect(agent.reload.config['booking_page_id']).to be_present
    end

    it 'com a página marcando, as ferramentas e a instrução de marcar entram no turno' do
      expect(agenda.estado(agent)).to eq('ativa')
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent).map(&:slug)).to eq(agenda::SLUGS)
      expect(agenda.instrucao(agent)).to include('chame `horarios_disponiveis`', 'cliente_confirmou: true', 'link_de_gestao')
    end

    it 'pausada: tira a agenda do turno e, se a ferramenta rodar mesmo assim, devolve o motivo' do
      profile.update!(enabled: false)

      sem_agenda_no_turno('pausada')
      expect(JSON.parse(horarios)).to include('agenda_disponivel' => false, 'motivo' => 'pausada')
      expect(JSON.parse(agendar)).to include('motivo' => 'pausada')
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'sem ninguém que possa atender' do
      AccountUser.find_by(account: account, user: world.host).destroy!

      sem_agenda_no_turno('sem_responsavel')
      expect(JSON.parse(horarios)).to include('motivo' => 'sem_responsavel')
    end

    it 'quem atende pausou Meus horários: diz isso em vez de "sem horários"' do
      Crm::AgentAvailability.create!(account: account, user: world.host, paused: true)

      sem_agenda_no_turno('agenda_pausada')
      expect(JSON.parse(horarios)).to include('agenda_disponivel' => false, 'motivo' => 'agenda_pausada')
      expect(horarios).to include('should_handoff=true')
    end

    it 'apagada, com o id ainda gravado no agente' do
      agent
      profile.destroy!

      sem_agenda_no_turno('pagina_inexistente')
      expect(JSON.parse(horarios)).to include('motivo' => 'pagina_inexistente')
      expect(Autonomia::Agents::PromptBuilder.new(agent: agent, query: 'oi').instructions).to include('motivo: pagina_inexistente')
    end

    it 'id de página de outra conta gravado no agente é tratado como inexistente, sem ler nada dela' do
      alheia = build_booking_world(account: create(:account)).profile
      agent.update_columns(config: agent.config.merge('booking_page_id' => alheia.id)) # rubocop:disable Rails/SkipsModelValidations

      sem_agenda_no_turno('pagina_inexistente')
      expect(JSON.parse(agendar)).to include('motivo' => 'pagina_inexistente')
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'atribuído com a agenda pausada numa página por pessoa: a IA usa o primeiro link de quem não pausou' do
      colega = create(:user, account: account, role: :agent, name: 'Rui Prado')
      profile.update!(assignment_mode: :per_agent, default_assignee: nil)
      profile.agent_booking_links.create!(account: account, agent: world.host)
      profile.agent_booking_links.create!(account: account, agent: colega)
      Crm::AgentAvailability.create!(account: account, user: world.host, paused: true)
      conversation.update!(assignee: world.host)

      expect(agenda.estado(agent.reload)).to eq('ativa')
      expect(JSON.parse(agendar)).to include('marcada' => true)
      expect(Crm::Meeting.sole.created_by).to eq(colega)
    end

    it 'sem horário livre na janela: motivo estruturado' do
      profile.update_columns(working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [] }) # rubocop:disable Rails/SkipsModelValidations

      expect(JSON.parse(horarios)).to include('agenda_disponivel' => false, 'motivo' => 'sem_horario')
    end
  end

  describe 'confirmação do cliente decidida pelo modelo' do
    it 'é um booleano obrigatório e não anulável no schema' do
      parametros = described_class.openai_schema(agent)[:parameters]

      expect(parametros[:properties]['cliente_confirmou']).to include('type' => 'boolean')
      expect(parametros[:required]).to include('cliente_confirmou')
    end

    it 'sem true não marca: manda confirmar antes' do
      [false, nil, 'true', 'sim'].each do |valor|
        expect(agendar(cliente_confirmou: valor)).to include('NADA foi marcado', 'cliente_confirmou=true'), valor.inspect
      end
      expect(Crm::Meeting.count).to eq(0)
    end
  end

  describe 'isolamento entre contatos e contas' do
    it 'outro contato no mesmo horário não recebe a reunião nem o link de quem marcou' do
      agendar
      codigo = Crm::BookingInvite.sole.code
      outro = account.contacts.create!(name: 'Bruno', phone_number: '+5521977776666')
      outra_conversa = create(:conversation, account: account, inbox: inbox, contact: outro)

      texto = agendar(entrega: entrega_em(outra_conversa, 90))

      expect(texto).to include('NÃO foi marcado')
      expect(texto).not_to include(codigo)
      expect(Crm::Meeting.count).to eq(1)
    end

    it 'o mesmo contato em outro turno recebe o próprio link de gestão' do
      primeira = JSON.parse(agendar)

      segunda = JSON.parse(agendar(entrega: entrega_em(conversation, 78)))

      expect(segunda['link_de_gestao']).to eq(primeira['link_de_gestao'])
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'o link de gestão nunca é o convite de outro contato da mesma reunião' do
      agendar
      meeting = Crm::Meeting.sole
      outro = account.contacts.create!(name: 'Bruno', phone_number: '+5521977776666')
      alheio = Crm::BookingInvite.new(account: account, booking_profile: profile, contact: outro, meeting: meeting, channel: 'ai',
                                      expires_at: 1.day.from_now)
      tool = described_class.new(agent: agent, params: {}, delivery: delivery)

      expect(alheio).not_to be_valid
      expect(tool.send(:convite_do_cliente, meeting).contact_id).to eq(world.contact.id)
    end
  end

  describe 'resultados (Pela IA)' do
    it 'conta a reunião como marcada pela IA, e abrir o link de gestão não conta como enviado nem aberto' do
      agendar
      Crm::BookingInvite.sole.update!(first_opened_at: 1.minute.from_now)
      travel 2.minutes

      results = Crm::BookingV2::Results.new(account: account, period: Crm::BookingV2::ResultsPeriod.new(account: account, days: 7))
      expect(results.totals).to include(booked: 1, sent: 0, opened: 0)
      expect(results.origins).to include({ key: 'ai', count: 1 })
    end
  end

  describe 'um ponto só para os avisos' do
    it 'a IA e o painel agendam os avisos pelo mesmo serviço' do
      profile.update!(notice_inbox: notice_inbox)
      allow(Crm::BookingV2::BookingNotices).to receive(:new).and_call_original
      user = create(:user, account: account, role: :administrator)

      agendar
      Crm::BookingV2::PanelBooking.new(page: profile, user: user, client: { card: world.card },
                                       params: { starts_at: '2026-10-21T10:00:00-03:00', notify: true }).perform

      expect(Crm::BookingV2::BookingNotices).to have_received(:new).with(hash_including(told_in: conversation)).once
      expect(Crm::BookingV2::BookingNotices).to have_received(:new).with(hash_excluding(:told_in)).once
    end
  end
end
