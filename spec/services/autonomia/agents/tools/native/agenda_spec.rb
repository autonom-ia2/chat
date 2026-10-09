require 'rails_helper'

# A agenda da IA (#1196, F3): `horarios_disponiveis` e `agendar_reuniao`. J6-A1 (mesmos horários da página),
# J6-A4 (reunião da IA identificável no card), J6-A5 (página pausada ou sem horário passa para uma pessoa) e a página
# que só vem da configuração do agente (de outra conta é recusada). J6-A3 (concorrência) fica no spec ao lado.
RSpec.describe Autonomia::Agents::Tools::Native::Agenda do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 77) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agenda', agent_type: 'scheduler', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'booking_page_id' => profile.id })
  end
  let(:horarios_tool) { Autonomia::Agents::Tools::Native::HorariosDisponiveis }
  let(:agendar_tool) { Autonomia::Agents::Tools::Native::AgendarReuniao }
  let(:slot) { '2026-10-20T10:00:00-03:00' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  # Segunda-feira, 08:00 em São Paulo.
  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features!('crm_booking_v2')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def horarios(data: nil, duracao: nil, entrega: delivery)
    horarios_tool.new(agent: agent, params: { 'data' => data, 'duracao_minutos' => duracao }, delivery: entrega).call
  end

  def agendar(inicio: slot, entrega: delivery, **extra)
    agendar_tool.new(agent: agent, params: { 'inicio' => inicio }.merge(extra.stringify_keys), delivery: entrega).call
  end

  # As opções que a ferramenta escreveu: a linha "- <iso> (<rótulo>)". Lê a NOSSA saída, não texto de pessoa.
  def opcoes(texto)
    texto.lines.select { |linha| linha.start_with?('- ') }.map { |linha| linha.split[1] }
  end

  def slots_da_pagina(slug, date)
    page = Crm::BookingV2::PublicPage.find(slug)
    Crm::BookingV2::Slots.new(profile: page.profile, host: page.host, date: date).perform
  end

  describe 'catálogo' do
    it 'liga as duas ferramentas quando a página é escolhida e a agenda está ligada na conta' do
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent)).to eq([horarios_tool, agendar_tool])
    end

    it 'não oferece nada sem a flag da conta, sem o CRM ou sem página escolhida' do
      account.disable_features!('crm_booking_v2')
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent.reload)).to be_empty

      account.enable_features!('crm_booking_v2')
      with_modified_env('CRM_KANBAN_ENABLED' => 'false') { expect(Autonomia::Agents::Tools::Registry.for_agent(agent)).to be_empty }

      agent.update!(config: agent.config.merge('booking_page_id' => nil))
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent)).to be_empty
    end

    it 'não aceita gravar página de outra conta nem página antiga' do
      foreign = build_booking_world(account: create(:account)).profile
      expect { agent.update!(config: agent.config.merge('booking_page_id' => foreign.id)) }
        .to raise_error(ActiveRecord::RecordInvalid)

      legacy = create_booking_profile(account: account, host: world.host)
      legacy.update_columns(page_version: Crm::AgentBookingProfile::LEGACY_PAGE) # rubocop:disable Rails/SkipsModelValidations
      expect { agent.update!(config: agent.config.merge('booking_page_id' => legacy.id)) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'página apagada depois não trava salvar as outras configurações do agente' do
      agent
      profile.update_columns(page_version: Crm::AgentBookingProfile::LEGACY_PAGE) # rubocop:disable Rails/SkipsModelValidations

      expect { agent.update!(config: agent.config.merge('response_window' => 'always')) }.not_to raise_error
    end

    it 'leva a instrução da agenda ao prompt só quando a agenda está ligada' do
      expect(Autonomia::Agents::PromptBuilder.new(agent: agent, query: 'oi').instructions).to include('# Agenda', 'horarios_disponiveis')

      account.disable_features!('crm_booking_v2')
      expect(Autonomia::Agents::PromptBuilder.new(agent: agent.reload, query: 'oi').instructions).not_to include('# Agenda')
    end
  end

  describe 'horarios_disponiveis (J6-A1)' do
    it 'oferece para a data os mesmos horários da página pública, sem o que já está ocupado' do
      create_internal_meeting(world: world, starts_at: Time.iso8601(slot))

      texto = horarios(data: '2026-10-20')

      expect(opcoes(texto)).to eq(slots_da_pagina(profile.slug, '2026-10-20').first(described_class::MAX_OPCOES))
      expect(opcoes(texto)).not_to include(slot)
      expect(texto).to include('terça-feira, 20/10', 'whatsapp_video', 'America/Sao_Paulo')
    end

    it 'sem data, espalha até seis horários pelos próximos dias, cada um livre na página naquele dia' do
      escolhidos = opcoes(horarios)

      expect(escolhidos.size).to eq(described_class::MAX_OPCOES)
      expect(escolhidos).to eq(escolhidos.sort_by { |iso| Time.iso8601(iso) })
      por_dia = escolhidos.group_by { |iso| iso.first(10) }
      expect(por_dia.values.map(&:size)).to all(be <= described_class::POR_DIA_SEM_DATA)
      por_dia.each { |dia, isos| expect(slots_da_pagina(profile.slug, dia)).to include(*isos) }
    end

    it 'usa o link de quem está atribuído à conversa numa página com um link por pessoa' do
      colega = create(:user, account: account, role: :agent, name: 'Colega')
      profile.update!(assignment_mode: :per_agent, default_assignee: nil)
      profile.agent_booking_links.create!(account: account, agent: world.host)
      link = profile.agent_booking_links.create!(account: account, agent: colega)
      conversation.update!(assignee: colega)
      create_internal_meeting(world: world, starts_at: Time.iso8601(slot), created_by: colega)

      expect(opcoes(horarios(data: '2026-10-20'))).to eq(slots_da_pagina(link.slug, '2026-10-20').first(described_class::MAX_OPCOES))
      expect(opcoes(horarios(data: '2026-10-20'))).not_to include(slot)
    end

    it 'com o dia cheio, avisa e devolve os próximos livres' do
      texto = horarios(data: '2026-10-18')

      expect(texto).to include('Não há horário livre em 18/10')
      expect(opcoes(texto)).not_to be_empty
      expect(opcoes(texto).map { |iso| iso.first(10) }).not_to include('2026-10-18')
    end

    it 'recusa data fora do formato e duração que a página não oferece' do
      expect(horarios(data: 'quinta que vem')).to include('AAAA-MM-DD')
      expect(horarios(duracao: 17)).to include('Durações possíveis, em minutos: 30')
    end

    it 'responde também sem conversa (Testar)' do
      expect(opcoes(horarios(entrega: nil)).size).to eq(described_class::MAX_OPCOES)
    end
  end

  describe 'página que não serve (J6-A5)' do
    it 'página pausada: a IA diz isso e passa para uma pessoa, e nada é marcado' do
      profile.update!(enabled: false)

      expect(horarios).to include('pausada', 'should_handoff=true')
      expect(agendar).to include('pausada', 'should_handoff=true')
      expect(Crm::Meeting.count).to be_zero
    end

    it 'responsável que não pode mais atender conta como pausada' do
      AccountUser.find_by(account: account, user: world.host).destroy!

      expect(horarios).to include('pausada', 'should_handoff=true')
    end

    it 'sem nenhum horário na janela: a IA diz isso e passa para uma pessoa' do
      profile.update_columns(working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [] }) # rubocop:disable Rails/SkipsModelValidations

      expect(horarios).to include('Não há horário livre', 'should_handoff=true')
    end

    it 'página de outra conta na configuração é recusada, sem ler nada dela' do
      foreign = build_booking_world(account: create(:account)).profile
      agent.update_columns(config: agent.config.merge('booking_page_id' => foreign.id)) # rubocop:disable Rails/SkipsModelValidations

      expect(horarios).to include('não está disponível', 'should_handoff=true')
      expect(agendar).to include('não está disponível')
      expect(Crm::Meeting.count).to be_zero
    end

    it 'a página nunca vem do modelo: um id nos argumentos é ignorado' do
      other = create_booking_profile(account: account, host: world.host, enabled: false)
      texto = horarios_tool.new(agent: agent, params: { 'data' => nil, 'booking_page_id' => other.id }, delivery: delivery).call

      expect(opcoes(texto).size).to eq(described_class::MAX_OPCOES)
    end
  end

  describe 'agendar_reuniao' do
    before { world.card.update!(conversation_id: conversation.id) }

    it 'marca pelo Booker com origem da IA, no card da conversa, com convite da IA (J6-A4)' do
      texto = agendar

      meeting = Crm::Meeting.sole
      expect(texto).to include('Reunião marcada', 'terça-feira, 20/10, 10:00', '30 minutos')
      expect(meeting).to have_attributes(source: 'ai', card_id: world.card.id, created_by_id: world.host.id, provider: 'internal',
                                         starts_at: Time.iso8601(slot))
      expect(meeting.meeting_guests.pluck(:phone_number)).to eq([world.contact.phone_number])
      expect(Crm::Activity.find_by(card: world.card, event_type: 'meeting_scheduled').payload).to include('source' => 'ai')
      expect(Crm::BookingInvite.sole).to have_attributes(
        channel: 'ai', meeting_id: meeting.id, conversation_id: conversation.id, contact_id: world.contact.id, created_by_id: nil
      )
    end

    it 'o mesmo turno pedindo de novo não cria outra reunião' do
      agendar
      agendar

      expect(Crm::Meeting.count).to eq(1)
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'horário ocupado: não marca e devolve novas opções da página' do
      create_internal_meeting(world: world, starts_at: Time.iso8601(slot))

      texto = agendar

      expect(texto).to include('NÃO foi marcado')
      expect(opcoes(texto)).to eq(slots_da_pagina(profile.slug, '2026-10-20').first(described_class::MAX_OPCOES))
      expect(Crm::Meeting.where(starts_at: Time.iso8601(slot)).count).to eq(1)
    end

    it 'sem conversa (Testar) recusa com nome e não marca' do
      expect(agendar(entrega: nil)).to include('Só dá para marcar dentro de uma conversa')
      expect(Crm::Meeting.count).to be_zero
    end

    it 'contato sem telefone: pede o número; com o número informado, marca' do
      world.contact.update!(phone_number: nil)

      expect(agendar).to include('Peça ao cliente o número')
      expect(Crm::Meeting.count).to be_zero

      agendar(telefone: '(21) 98888-7777')
      expect(Crm::Meeting.sole.meeting_guests.pluck(:phone_number)).to eq(['+5521988887777'])
    end

    it 'horário que não é ISO, duração e local fora da página são recusados sem marcar' do
      expect(agendar(inicio: 'quarta às 14h')).to include('exatamente como veio')
      expect(agendar(duracao_minutos: 17)).to include('Durações possíveis')
      expect(agendar(local: 'in_person')).to include('Esse local não existe', 'whatsapp_video')
      expect(Crm::Meeting.count).to be_zero
    end

    it 'cliente com reuniões demais passa para uma pessoa' do
      create_internal_meeting(world: world, starts_at: Time.iso8601('2026-10-21T10:00:00-03:00'))
      create_internal_meeting(world: world, starts_at: Time.iso8601('2026-10-22T10:00:00-03:00'))

      expect(agendar).to include('reuniões marcadas demais', 'should_handoff=true')
      expect(Crm::Meeting.count).to eq(2)
    end

    it 'falha do sistema na reserva passa para uma pessoa, sem marcar' do
      booker = instance_double(Crm::BookingV2::Booker)
      allow(Crm::BookingV2::Booker).to receive(:new).and_return(booker)
      allow(booker).to receive(:perform).and_raise(ArgumentError, 'no_stage_configured')

      expect(agendar).to include('Não foi possível marcar agora', 'should_handoff=true')
    end

    it 'passa ao Booker uma chave de idempotência do turno, nunca o telefone' do
      allow(Crm::BookingV2::Booker).to receive(:new).and_call_original

      agendar

      expect(Crm::BookingV2::Booker).to have_received(:new)
        .with(hash_including(idempotency_key: "ai:#{conversation.id}:mensagem:77:2026-10-20T13:00:00Z", source: 'ai'))
    end
  end
end
