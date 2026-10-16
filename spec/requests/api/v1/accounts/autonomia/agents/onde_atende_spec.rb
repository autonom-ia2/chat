require 'rails_helper'

# chat#1720 — o "Salvar" da gaveta "Onde e quando {nome} responde" (PUT agents/:id/onde_atende): onde atende primeiro
# (porta), onde recebe quando alguém passa (áreas) e o "Quando atende", numa transação só.
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

  def salvar(agent = hubber, conta: account, **params)
    put "/api/v1/accounts/#{conta.id}/autonomia/agents/#{agent.id}/onde_atende",
        params: params, headers: admin.create_new_auth_token, as: :json
  end

  def portas(agent = hubber)
    Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: agent.id).pluck(:inbox_id)
  end

  def areas(agent = hubber)
    Autonomia::Agents::AgentInbox.kept.area.where(autonomia_agent_id: agent.id).pluck(:inbox_id)
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

    it 'turns a team channel into the first channel' do
      porta!(hubber, comercial)
      area!(hubber, da_clara)

      salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(portas).to eq([da_clara.id])
      expect(areas).to be_empty
    end
  end

  # #1720 — a única área dele vira a porta: ele não para no meio, e nenhum evento de parada falso fica gravado.
  it 'turns its only team channel into the first channel without stopping or recording a stop' do
    area!(hubber, da_clara)

    salvar(primeiro_inbox_id: da_clara.id, area_inbox_ids: [])

    expect(response).to have_http_status(:no_content)
    expect(portas).to eq([da_clara.id])
    expect(areas).to be_empty
    expect(hubber.reload).to have_attributes(status: 'active', enabled: true)
    expect(hubber.events.parado_sem_onde_trabalhar.count).to eq(0)
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

    it 'undoes everything with its own message when leaving the old first channel fails' do
      original = Autonomia::Agents::Operate::InboxConnector.instance_method(:perform)
      allow_any_instance_of(Autonomia::Agents::Operate::InboxConnector).to receive(:perform) do |conector, connect:| # rubocop:disable RSpec/AnyInstance
        if connect
          original.bind_call(conector, connect: connect)
        else
          Autonomia::Agents::Operate::InboxConnector::Result.new(status: :error, error: :not_connected)
        end
      end

      salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(codigo).to eq('saida_recusada')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.onde_atende.saida_recusada', nome: 'Hubber', canal: 'Comercial'))
      expect(portas).to eq([comercial.id])
      expect(areas).to be_empty
    end
  end

  describe 'tenancy' do
    let(:outra_conta) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }

    it 'does not find a channel of another account' do
      porta!(hubber, comunidade)
      de_fora = create(:inbox, account: outra_conta)

      salvar(primeiro_inbox_id: nil, area_inbox_ids: [de_fora.id])

      expect(response).to have_http_status(:not_found)
      expect(portas).to eq([comunidade.id])
    end

    it 'does not find an agent of another account' do
      de_fora = Autonomia::Agents::Agent.create!(account: outra_conta, name: 'Fora', agent_type: 'custom', status: :active, enabled: true)

      salvar(de_fora, primeiro_inbox_id: comunidade.id)

      expect(response).to have_http_status(:not_found)
      expect(portas(de_fora)).to be_empty
    end
  end

  it 'leaves the team channels alone when the screen did not show them (no area_inbox_ids)' do
    porta!(hubber, comunidade)
    area!(hubber, da_clara)

    salvar(primeiro_inbox_id: comercial.id, response_window: 'always')

    expect(response).to have_http_status(:no_content)
    expect(portas).to eq([comercial.id])
    expect(areas).to eq([da_clara.id])
  end

  it 'refuses team channels without the Fase 2, and the same channel as first and team' do
    porta!(hubber, comunidade)

    salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [comunidade.id])
    expect(codigo).to eq('pedido_invalido')

    Autonomia::Agents::Fase2.desligar!(account)
    salvar(primeiro_inbox_id: comunidade.id, area_inbox_ids: [da_clara.id])
    expect(codigo).to eq('fase2_off')
    expect(areas).to be_empty
  end

  it 'refuses an invalid window' do
    salvar(primeiro_inbox_id: comunidade.id, response_window: 'midnight')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(codigo).to eq('pedido_invalido')
  end
end
