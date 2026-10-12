require 'rails_helper'

# Pessoas liberadas na agenda da IA (#1307): o dono libera quais pessoas da página a IA pode usar
# (`config['booking_agent_ids']`, vazio = todas) e o MODELO escolhe com quem marcar. O servidor confere o `pessoa_id`
# contra as liberadas, quem atende a página, a agenda dela e o horário livre dela.
RSpec.describe Autonomia::Agents::Tools::Native::AgendaPessoas do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:rui) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
  let(:lia) { create(:user, account: account, role: :agent, name: 'Lia Souza') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 77) }
  let(:liberadas) { [] }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agenda', agent_type: 'scheduler', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'booking_page_id' => profile.id })
  end
  let(:agenda) { Autonomia::Agents::Tools::Native::Agenda }
  let(:slot) { '2026-10-20T10:00:00-03:00' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features!('crm_booking_v2')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  # Página com um link por pessoa: Rui, Lia e o responsável do mundo, nessa ordem (a ordem fixa do #1305).
  def por_pessoa!
    profile.update!(assignment_mode: :per_agent, default_assignee: nil)
    [rui, lia, world.host].each { |user| profile.agent_booking_links.create!(account: account, agent: user) }
  end

  # Grava sem passar pelo controller: o que está no banco pode ser forjado; a ferramenta confere de novo.
  def liberar!(ids)
    agent.update_columns(config: agent.config.merge('booking_agent_ids' => ids)) # rubocop:disable Rails/SkipsModelValidations
    agent.reload
  end

  def horarios(**params)
    Autonomia::Agents::Tools::Native::HorariosDisponiveis.new(agent: agent, params: { 'data' => '2026-10-20' }.merge(params.stringify_keys),
                                                              delivery: delivery).call
  end

  def agendar(**params)
    Autonomia::Agents::Tools::Native::AgendarReuniao.new(
      agent: agent, params: { 'inicio' => slot, 'cliente_confirmou' => true }.merge(params.stringify_keys), delivery: delivery
    ).call
  end

  def pessoas_dos_horarios(texto)
    JSON.parse(texto)['horarios'].pluck('pessoa_id').uniq
  end

  describe 'quem está liberado' do
    before { por_pessoa! }

    it 'liberação vazia (ou ausente) = todas as pessoas da página, na ordem da página' do
      expect(agenda.estado(agent)).to eq('ativa')
      expect(pessoas_dos_horarios(horarios)).to all(be_in([rui.id, lia.id, world.host.id]))
      expect(JSON.parse(horarios(pessoa_id: world.host.id))['horarios']).not_to be_empty

      liberar!([])
      expect(agenda.estado(agent)).to eq('ativa')
    end

    it 'subconjunto: só as liberadas aparecem nos horários e na instrução' do
      liberar!([lia.id])

      expect(pessoas_dos_horarios(horarios)).to eq([lia.id])
      expect(agenda.instrucao(agent)).to include("#{lia.available_name} (pessoa_id #{lia.id})")
      expect(agenda.instrucao(agent)).not_to include("pessoa_id #{rui.id}")
    end

    it 'pessoa de outra conta não é liberada; sozinha na liberação, a agenda fica sem responsável (nunca vira "todas")' do
      de_fora = create(:user, account: create(:account), role: :agent)
      liberar!([de_fora.id])

      expect(agenda.estado(agent)).to eq('sem_responsavel')
      expect(Autonomia::Agents::Tools::Registry.for_agent(agent)).to be_empty
      expect(JSON.parse(horarios)).to include('agenda_disponivel' => false, 'motivo' => 'sem_responsavel')
    end

    it 'valor gravado que não dá para ler é "ninguém", nunca "todas"' do
      ['x', ['x'], { 'a' => 1 }].each do |valor|
        liberar!(valor)
        expect(agenda.estado(agent)).to eq('sem_responsavel')
      end

      liberar!(nil)
      expect(agenda.estado(agent)).to eq('ativa')
    end

    it 'pessoa_id em outra base não vira outra pessoa ("010" não é 8)' do
      expect(described_class.numero('010')).to eq(10)
      expect(described_class.numero('0x8')).to be_nil
    end

    it 'pessoa da conta que não é da página não é liberada' do
      fora_da_pagina = create(:user, account: account, role: :agent)
      liberar!([fora_da_pagina.id, rui.id])

      expect(pessoas_dos_horarios(horarios)).to eq([rui.id])
      expect(JSON.parse(horarios(pessoa_id: fora_da_pagina.id))).to include('motivo' => 'pessoa_nao_liberada')
    end

    it 'agenda pausada: a pessoa sai de quem atende; todas as liberadas pausadas = agenda pausada' do
      liberar!([rui.id, lia.id])
      Crm::AgentAvailability.create!(account: account, user: rui, paused: true)

      expect(pessoas_dos_horarios(horarios)).to eq([lia.id])
      expect(JSON.parse(horarios(pessoa_id: rui.id))).to include('motivo' => 'pessoa_pausada')
      expect(JSON.parse(agendar(pessoa_id: rui.id))).to include('marcada' => false, 'motivo' => 'pessoa_pausada')

      Crm::AgentAvailability.create!(account: account, user: lia, paused: true)
      expect(agenda.estado(agent.reload)).to eq('agenda_pausada')
      expect(Crm::Meeting.count).to be_zero
    end
  end

  describe 'agendar_reuniao' do
    before do
      por_pessoa!
      world.card.update!(conversation_id: conversation.id)
    end

    it 'pessoa_id forjado pelo modelo, fora das liberadas: recusa em campos, com a lista, e não marca' do
      liberar!([rui.id])

      resposta = JSON.parse(agendar(pessoa_id: lia.id))

      expect(resposta).to include('marcada' => false, 'motivo' => 'pessoa_nao_liberada')
      expect(resposta['pessoas_liberadas']).to eq([{ 'pessoa_id' => rui.id, 'pessoa_nome' => rui.available_name }])
      expect(Crm::Meeting.count).to be_zero
    end

    it 'com mais de uma liberada, exige o pessoa_id; com ele, marca com a pessoa escolhida, pelo link dela' do
      liberar!([rui.id, lia.id])

      expect(JSON.parse(agendar)).to include('marcada' => false, 'motivo' => 'pessoa_obrigatoria')
      expect(Crm::Meeting.count).to be_zero

      resposta = JSON.parse(agendar(pessoa_id: lia.id.to_s))

      expect(resposta).to include('marcada' => true, 'pessoa_id' => lia.id, 'pessoa_nome' => lia.available_name)
      expect(Crm::Meeting.sole.created_by_id).to eq(lia.id)
      expect(Crm::BookingInvite.sole.booking_link).to eq(profile.agent_booking_links.find_by(agent: lia))
    end

    it 'uma liberada só: marca com ela sem pessoa_id' do
      liberar!([lia.id])

      expect(JSON.parse(agendar)).to include('marcada' => true)
      expect(Crm::Meeting.sole.created_by_id).to eq(lia.id)
    end

    it 'horário ocupado da pessoa escolhida: novas opções dela, em campos' do
      create_internal_meeting(world: world, starts_at: Time.iso8601(slot), created_by: lia)

      resposta = JSON.parse(agendar(pessoa_id: lia.id))

      expect(resposta).to include('marcada' => false, 'motivo' => 'horario_ocupado')
      expect(resposta['horarios'].pluck('pessoa_id').uniq).to eq([lia.id])
      expect(resposta['horarios'].pluck('inicio')).not_to include(slot)
    end
  end

  describe 'página de responsável único' do
    it 'traz uma pessoa só; booking_agent_ids apontando outra pessoa não vale' do
      expect(JSON.parse(horarios)['horarios'].pluck('pessoa_id').uniq).to eq([world.host.id])

      liberar!([rui.id])

      expect(agenda.estado(agent)).to eq('sem_responsavel')
      expect(JSON.parse(agendar(pessoa_id: rui.id))).to include('marcada' => false)
      expect(Crm::Meeting.count).to be_zero
    end
  end

  describe 'conferência da liberação (controller)' do
    it 'só ids que são pessoas da página, inteiros únicos' do
      por_pessoa!
      de_fora = create(:user, account: create(:account), role: :agent)
      paginas = Crm::BookingV2::InvitePages.new(account)

      ids = described_class.conferir([lia.id.to_s, lia.id, de_fora.id, 'x', nil, -1, rui.id], pagina: profile.reload, paginas: paginas)

      expect(ids).to eq([lia.id, rui.id])
      expect(described_class.conferir([lia.id], pagina: nil, paginas: paginas)).to eq([])
      expect(described_class.conferir('1,2', pagina: profile, paginas: paginas)).to eq([])
    end
  end

  describe 'instrução "# Agenda"' do
    it 'várias pessoas: lista pelo nome e manda seguir o dono, preferir quem atende a conversa e senão oferecer as liberadas' do
      por_pessoa!

      texto = agenda.instrucao(agent)

      expect(texto).to include("#{rui.available_name} (pessoa_id #{rui.id}), #{lia.available_name} (pessoa_id #{lia.id})")
      expect(texto.squish).to include('siga a instrução do dono', 'prefira quem atende esta conversa, se essa pessoa estiver na lista',
                                      'Senão, ofereça os horários das pessoas da lista')
    end

    it 'uma pessoa: diz com quem marca' do
      expect(agenda.instrucao(agent)).to include("Você marca com #{world.host.available_name} (pessoa_id #{world.host.id})")
    end

    # Revisão do #1347: agente scheduler antigo tem "encaminhar remarcação à equipe" gravado.
    it 'vale sobre regra anterior também para remarcar e cancelar (mandar o link de gestão)' do
      texto = agenda.instrucao(agent)

      expect(texto.squish).to include('passar para a equipe quem quer remarcar ou cancelar: para remarcar ou cancelar, siga o que esta seção diz')
      expect(texto.squish).to include('Para remarcar ou cancelar, mande o link de gestão')
    end

    it 'diz o prazo para mudar ou cancelar quando a página tem um; sem prazo, não fala de prazo' do
      profile.update_columns(cancel_until_minutes: 1440) # rubocop:disable Rails/SkipsModelValidations
      expect(agenda.instrucao(agent)).to include('só até 24 horas antes do horário')

      profile.update_columns(cancel_until_minutes: 90) # rubocop:disable Rails/SkipsModelValidations
      expect(agenda.instrucao(agent)).to include('só até 90 minutos antes do horário')

      profile.update_columns(cancel_until_minutes: 0) # rubocop:disable Rails/SkipsModelValidations
      expect(agenda.instrucao(agent)).not_to include('antes do horário')
    end
  end

  describe 'confirmação da reunião (instrução do retorno)' do
    before { world.card.update!(conversation_id: conversation.id) }

    it 'WhatsApp: não diz que mandou convite por e-mail; com prazo, diz o prazo' do
      profile.update_columns(cancel_until_minutes: 120) # rubocop:disable Rails/SkipsModelValidations

      instrucao = JSON.parse(agendar)['instrucao']

      expect(instrucao).to include('Não diga que mandou convite por e-mail', 'só até 2 horas antes do horário')
    end

    it 'Meet/Teams: diz que o convite do calendário vai para o e-mail do cliente' do
      ferramenta = Autonomia::Agents::Tools::Native::AgendarReuniao.new(agent: agent, params: {}, delivery: delivery)

      %w[google_meet teams].each do |tipo|
        instrucao = ferramenta.send(:instrucao_confirmada, { 'type' => tipo })
        expect(instrucao).to include('convite do calendário vai para o e-mail do cliente')
        expect(instrucao).not_to include('Não diga que mandou convite')
      end
    end
  end

  describe 'memória do turno' do
    it 'o gate das duas ferramentas e a instrução leem o estado uma vez por turno; fora do turno, sempre de novo' do
      allow(Crm::BookingV2::InvitePages).to receive(:new).and_call_original

      agenda.no_turno do
        Autonomia::Agents::Tools::Registry.for_agent(agent)
        agenda.estado(agent)
      end
      expect(Crm::BookingV2::InvitePages).to have_received(:new).once

      Autonomia::Agents::Tools::Registry.for_agent(agent)
      expect(Crm::BookingV2::InvitePages).to have_received(:new).exactly(3).times
    end
  end
end
