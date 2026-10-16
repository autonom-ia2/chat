require 'rails_helper'

# chat#1720 — o "Salvar" da gaveta "Onde e quando {nome} responde" (PUT agents/:id/onde_atende): onde atende primeiro
# (porta), onde recebe quando alguém passa (áreas) e o "Quando atende", numa transação só. Só com a Fase 2.
RSpec.describe 'Autonomia onde_atende', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:comunidade) { create(:inbox, account: account, name: 'HUBBER COMUNIDADE') }
  let(:da_clara) { create(:inbox, account: account, name: '5511944547873') }
  let(:comercial) { create(:inbox, account: account, name: 'Comercial') }
  let(:hubber) { agente('Hubber') }
  let(:clara) { agente('Clara') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    Autonomia::Agents::Fase2.ligar!(account)
    porta!(clara, da_clara)
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def porta!(agent, caixa)
    resultado = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
    expect(resultado).to be_success
  end

  def area!(agent, caixa)
    Autonomia::Agents::Areas.vincular!(agent: agent, inbox: caixa)
  end

  def salvar(agent = hubber, user: admin, **params)
    put "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/onde_atende",
        params: params, headers: user.create_new_auth_token, as: :json
  end

  def portas(agent = hubber)
    Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: agent.id).pluck(:inbox_id).sort
  end

  def areas(agent = hubber)
    Autonomia::Agents::AgentInbox.kept.area.where(autonomia_agent_id: agent.id).pluck(:inbox_id).sort
  end

  def espelho(agent, caixa, papel)
    Autonomia::Agents::AgentInbox.kept.find_by(autonomia_agent_id: agent.id, inbox_id: caixa.id, papel: papel).agent_bot_id
  end

  def codigo
    response.parsed_body['code']
  end

  describe '"Sim, no canal"' do
    it 'puts the agent first in the channel, adds the checked team channels and saves the window' do
      porta!(hubber, comercial)

      salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id], response_window: 'business_hours')

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([comunidade.id])
      expect(areas).to eq([da_clara.id])
      expect(hubber.reload).to have_attributes(status: 'active', enabled: true, response_window: 'business_hours')
      expect(hubber.events.parado_sem_onde_trabalhar.count).to eq(0)
    end

    it 'takes the other agent out when the channel already has someone first' do
      salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([da_clara.id])
      expect(portas(clara)).to be_empty
    end

    it 'turns its only team channel into the first channel without stopping or recording a stop' do
      area!(hubber, da_clara)

      salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([da_clara.id])
      expect(areas).to be_empty
      expect(hubber.reload).to have_attributes(status: 'active', enabled: true)
      expect(hubber.events.parado_sem_onde_trabalhar.count).to eq(0)
    end

    it 'keeps with the agent the conversations it answered as a team agent there (no hand-back)' do
      area!(hubber, da_clara)
      # A conversa que alguém passou para ele na caixa da Clara (o espelho da área é o dono dela).
      aberta = create(:conversation, account: account, inbox: da_clara, status: :open)
      aberta.update!(ai_assignee: AgentBot.find(espelho(hubber, da_clara, 'area')))

      salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(aberta.reload).to have_attributes(status: 'open', assignee_agent_bot_id: espelho(hubber, da_clara, 'porta'))
      expect(aberta.bot_handoff_waiting?).to be(false)
    end

    it 'redoes, through the new first channel, the turn that was in progress (once, after the commit)' do
      area!(hubber, da_clara)
      aberta = create(:conversation, account: account, inbox: da_clara, status: :open)
      aberta.update!(ai_assignee: AgentBot.find(espelho(hubber, da_clara, 'area')))
      pergunta = create(:message, account: account, conversation: aberta, message_type: :incoming, content: 'e o boleto?')
      aberta.update!(additional_attributes: aberta.additional_attributes.to_h.merge(
        Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => pergunta.id, 'at' => Time.current.to_f }
      ))

      expect { salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: []) }
        .to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob).with(aberta.id, pergunta.id).exactly(:once)
      expect(aberta.reload.assignee_agent_bot_id).to eq(espelho(hubber, da_clara, 'porta'))
    end

    it 'never removes an agent from another system, even an inactive one' do
      porta!(hubber, comercial)
      outro = create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook')
      AgentBotInbox.create!(inbox: comunidade, agent_bot: outro, account: account, status: :inactive)

      salvar(primeiro_inbox_id: comunidade.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(codigo).to eq('canal_com_outro_sistema')
      expect(AgentBotInbox.where(inbox_id: comunidade.id, agent_bot_id: outro.id)).to exist
      expect(portas).to eq([comercial.id])
    end

    it 'works for the quote agent (Lia) too' do
      lia = agente('Lia', agent_type: 'insurance_quote')

      salvar(lia, primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id])

      expect(response).to have_http_status(:no_content)
      expect(portas(lia)).to eq([comunidade.id])
      expect(areas(lia)).to eq([da_clara.id])
    end
  end

  describe 'agent first in two channels' do
    before do
      porta!(hubber, comunidade)
      porta!(hubber, comercial)
    end

    it 'keeps both when only the window changes' do
      salvar(manter_primeiro: true, primeiro_inbox_id: comunidade.id, response_window: 'outside_business_hours')

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([comunidade.id, comercial.id].sort)
      expect(hubber.reload.response_window).to eq('outside_business_hours')
    end

    it 'keeps both when only the team channels change' do
      salvar(manter_primeiro: true, area_inbox_ids: [da_clara.id])

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([comunidade.id, comercial.id].sort)
      expect(areas).to eq([da_clara.id])
    end
  end

  it 'removes a team channel with area_inbox_ids [] and keeps the first channel' do
    porta!(hubber, comunidade)
    area!(hubber, da_clara)

    salvar(manter_primeiro: true, area_inbox_ids: [])

    expect(response).to have_http_status(:no_content)
    expect(portas).to eq([comunidade.id])
    expect(areas).to be_empty
    expect(hubber.reload).to have_attributes(status: 'active', enabled: true)
  end

  describe '"Não, só quando alguém passar a conversa"' do
    before { porta!(hubber, comunidade) }

    it 'leaves the first channel, keeps receiving on the checked channels and stays on' do
      salvar(primeiro_inbox_id: nil, area_inbox_ids: [da_clara.id])

      expect(response).to have_http_status(:no_content)
      expect(portas).to be_empty
      expect(areas).to eq([da_clara.id])
      expect(hubber.reload).to have_attributes(status: 'active', enabled: true)
      expect(hubber.events.parado_sem_onde_trabalhar.count).to eq(0)
    end

    it 'refuses without the confirmation when nothing is checked, and changes nothing' do
      salvar(primeiro_inbox_id: nil, area_inbox_ids: [])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(codigo).to eq('confirmar_parado')
      expect(portas).to eq([comunidade.id])
      expect(hubber.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'stops the agent when nothing is checked and the screen confirmed' do
      salvar(primeiro_inbox_id: nil, area_inbox_ids: [], parar: true)

      expect(response).to have_http_status(:no_content)
      expect(portas).to be_empty
      expect(areas).to be_empty
      expect(hubber.reload).to have_attributes(status: 'paused', enabled: false)
      expect(hubber.events.parado_sem_onde_trabalhar.count).to eq(1)
    end
  end

  describe 'failure in the middle' do
    before { porta!(hubber, comercial) }

    it 'undoes everything when a team channel refuses after the new first channel was picked' do
      parada = agente('Lia')
      caixa_parada = create(:inbox, account: account, name: '5551996569128')
      porta!(parada, caixa_parada)
      parada.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

      salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id, caixa_parada.id], response_window: 'business_hours')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(codigo).to eq('area_recusada')
      expect(response.parsed_body['error']).to include('5551996569128')
      expect(portas).to eq([comercial.id])
      expect(areas).to be_empty
      expect(hubber.reload.response_window).to be_nil
    end

    context 'when leaving the old first channel fails' do
      before do
        original = Autonomia::Agents::Operate::InboxConnector.instance_method(:perform)
        hubber_id = hubber.id
        allow_any_instance_of(Autonomia::Agents::Operate::InboxConnector).to receive(:perform) do |conector, connect:| # rubocop:disable RSpec/AnyInstance
          if connect || conector.instance_variable_get(:@agent).id != hubber_id
            original.bind_call(conector, connect: connect)
          else
            Autonomia::Agents::Operate::InboxConnector::Result.new(status: :error, error: :not_connected)
          end
        end
      end

      it 'undoes everything with its own message' do
        salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(codigo).to eq('saida_recusada')
        expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.onde_atende.saida_recusada', nome: 'Hubber', canal: 'Comercial'))
        expect(portas).to eq([comercial.id])
        expect(areas).to be_empty
      end

      it 'sends no hand-off event for the conversations of the agent that left (the change was undone)' do
        pendente = create(:conversation, account: account, inbox: da_clara, status: :pending)
        allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

        salvar(primeiro_inbox_id: da_clara.id)

        expect(codigo).to eq('saida_recusada')
        expect(portas(clara)).to eq([da_clara.id])
        expect(pendente.reload.status).to eq('pending')
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, any_args)
      end
    end

    it 'sends the hand-off event after the commit when the change goes through' do
      pendente = create(:conversation, account: account, inbox: da_clara, status: :pending)
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      salvar(primeiro_inbox_id: da_clara.id)

      expect(response).to have_http_status(:no_content)
      expect(pendente.reload.status).to eq('open')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: pendente)).once
    end
  end

  # #1720 — a regra da Atribuição dentro da passagem (bot_handoff!) das conversas de quem sai do canal.
  describe 'hand-off with the Atribuição rule' do
    let!(:pendente) { create(:conversation, account: account, inbox: da_clara, status: :pending) }
    let(:outro_agente) { create(:agent_bot, account: account, name: 'Lia', outgoing_url: nil) }

    before do
      allow_any_instance_of(Crm::Entrega).to receive(:na_passagem) # rubocop:disable RSpec/AnyInstance
        .and_return(Crm::Entrega::Resultado.new(status: :para_ia))
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    end

    def avisos
      have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: pendente))
    end

    it 'sends no hand-off event when the rule hands the conversation to an AI agent' do
      robo = outro_agente
      allow_any_instance_of(Crm::Entrega).to receive(:concluir_para_ia!) do # rubocop:disable RSpec/AnyInstance
        pendente.reload.update!(ai_assignee: robo)
        Crm::Entrega::Resultado.new(status: :com_ia)
      end

      salvar(primeiro_inbox_id: da_clara.id)

      expect(response).to have_http_status(:no_content)
      expect(Rails.configuration.dispatcher).not_to avisos
    end

    it 'sends exactly one hand-off event when the AI agent refuses and the conversation goes to the team' do
      allow_any_instance_of(Crm::Entrega).to receive(:concluir_para_ia!) # rubocop:disable RSpec/AnyInstance
        .and_return(Crm::Entrega::Resultado.new(status: :nada))

      salvar(primeiro_inbox_id: da_clara.id)

      expect(response).to have_http_status(:no_content)
      expect(Rails.configuration.dispatcher).to avisos.once
    end

    it 'keeps sending the other events when a conversation is deleted before the commit' do
      allow_any_instance_of(Crm::Entrega).to receive(:concluir_para_ia!) # rubocop:disable RSpec/AnyInstance
        .and_return(Crm::Entrega::Resultado.new(status: :nada))
      apagada = create(:conversation, account: account, inbox: da_clara, status: :pending)

      ActiveRecord::Base.transaction do
        Autonomia::Agents::Operate::InboxConnector.new(agent: clara, inbox: da_clara).perform(connect: false)
        apagada.destroy!
      end

      expect(Rails.configuration.dispatcher).to avisos.once
    end
  end

  describe 'who can and which agent' do
    it 'refuses without the Fase 2 and changes nothing' do
      porta!(hubber, comunidade)
      Autonomia::Agents::Fase2.desligar!(account)

      salvar(primeiro_inbox_id: comercial.id, area_inbox_ids: [])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(codigo).to eq('fase2_off')
      expect(portas).to eq([comunidade.id])
    end

    it 'refuses a member without autonomia_manage' do
      porta!(hubber, comunidade)
      membro = create(:user, account: account, role: :agent)

      salvar(user: membro, primeiro_inbox_id: comercial.id)

      expect(response).to have_http_status(:unauthorized)
      expect(portas).to eq([comunidade.id])
    end

    it 'refuses an internal agent' do
      interno = agente('Copiloto', actuation: :internal)

      salvar(interno, primeiro_inbox_id: comunidade.id)

      expect(codigo).to eq('agente_interno')
      expect(portas(interno)).to be_empty
    end

    it 'does not find a system agent' do
      guia = agente('Guia', config: { 'system_key' => 'guide' })

      salvar(guia, primeiro_inbox_id: comunidade.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'does not find a channel of another account' do
      porta!(hubber, comunidade)
      de_fora = create(:inbox, account: create(:account))

      salvar(primeiro_inbox_id: nil, area_inbox_ids: [de_fora.id])

      expect(response).to have_http_status(:not_found)
      expect(portas).to eq([comunidade.id])
    end

    it 'does not find an agent of another account' do
      outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      de_fora = Autonomia::Agents::Agent.create!(account: outra, name: 'Fora', agent_type: 'custom', status: :active, enabled: true)

      salvar(de_fora, primeiro_inbox_id: comunidade.id)

      expect(response).to have_http_status(:not_found)
      expect(portas(de_fora)).to be_empty
    end
  end

  describe 'request shape' do
    before { porta!(hubber, comunidade) }

    it 'leaves the team channels alone when the screen did not show them (no area_inbox_ids)' do
      area!(hubber, da_clara)

      salvar(primeiro_inbox_id: comercial.id, response_window: 'always')

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([comercial.id])
      expect(areas).to eq([da_clara.id])
    end

    it 'answers mudou_agora when the database refuses a duplicate saved at the same time' do
      allow(Autonomia::Agents::Areas).to receive(:vincular!).and_raise(ActiveRecord::RecordNotUnique)

      salvar(manter_primeiro: true, area_inbox_ids: [da_clara.id])

      expect(codigo).to eq('mudou_agora')
      expect(portas).to eq([comunidade.id])
    end

    it 'refuses the same channel as first and team' do
      salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [comunidade.id])

      expect(codigo).to eq('pedido_invalido')
    end

    it 'refuses wrong types and an invalid window', :aggregate_failures do
      [
        { primeiro_inbox_id: comercial.id, response_window: 'midnight' },
        { primeiro_inbox_id: [comercial.id] },
        { primeiro_inbox_id: 'abc' },
        { area_inbox_ids: da_clara.id },
        { area_inbox_ids: ['x'] },
        { area_inbox_ids: [{ id: da_clara.id }] }
      ].each do |pedido|
        salvar(**pedido)
        expect(codigo).to eq('pedido_invalido'), pedido.inspect
      end
      expect(portas).to eq([comunidade.id])
    end
  end
end
