require 'rails_helper'

# Caixas no CRM → Quem cuida do quê? (#1447): os agentes de IA de área da caixa e os funis de cada um. Onde o agente
# trabalha é do Agentes IA (Autonomia::Agents::Areas); de qual funil ele cuida é crm_inbox_ai_agents.
RSpec.describe 'CRM Caixas no CRM API — agentes de IA', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp Comercial', members: [admin]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').first }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').first }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/caixas" }
  let(:clara) { agente('Clara') }
  let(:maria) { agente('Maria') }
  let(:marta) { agente('Marta', status: :paused, enabled: false) }

  before do
    account.enable_features!('crm_configurar_caixas')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    Autonomia::Agents::Operate::InboxConnector.new(agent: clara, inbox: inbox).perform(connect: true)
    Autonomia::Agents::Areas.vincular!(agent: maria, inbox: inbox)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, subject_ai_mode: 'auto')
    [vendas, suporte].each { |pipeline| account.crm_pipeline_inboxes.create!(inbox: inbox, pipeline: pipeline) }
    Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: vendas, agent: maria)
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def salvar(ai_agents, pipeline_ids: [vendas.id, suporte.id])
    put "#{url}/#{inbox.id}", params: { caixa: { pipeline_ids: pipeline_ids, modo: 'auto', people: [], ai_agents: ai_agents } },
                              headers: auth_headers(admin), as: :json
  end

  def agentes_da_caixa
    get "#{url}/#{inbox.id}", headers: auth_headers(admin)
    response.parsed_body.dig('payload', 'caixa', 'ai_agents')
  end

  def linhas
    Crm::InboxAiAgent.where(inbox: inbox).order(:pipeline_id).pluck(:pipeline_id, :autonomia_agent_id)
  end

  def area?(agent)
    Autonomia::Agents::AgentInbox.kept.area.exists?(inbox: inbox, agent: agent)
  end

  it 'mostra a porta, as áreas com os funis delas e quem pode entrar' do
    agente('Copiloto', actuation: :internal)
    agente('Apagado').update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    marta

    expect(agentes_da_caixa).to eq(
      'porta' => { 'id' => clara.id, 'name' => 'Clara' },
      'pode_mudar' => true,
      'areas' => [{ 'id' => maria.id, 'name' => 'Maria', 'pipeline_ids' => [vendas.id], 'parado' => false, 'ultima_caixa' => true }],
      'disponiveis' => [{ 'id' => marta.id, 'name' => 'Marta', 'parado' => true }]
    )
  end

  it 'não oferece rascunho nem pausado de propósito (com caixa); oferece a Lia (#1433)' do
    marta
    agente('Rascunho', status: :draft, enabled: false, instruction: 'Pronto.')
    lia = agente('Lia', agent_type: 'insurance_quote', status: :paused, enabled: false)
    pausado = agente('Pausado')
    Autonomia::Agents::Operate::InboxConnector.new(agent: pausado, inbox: create(:inbox, account: account)).perform(connect: true)
    pausado.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

    expect(agentes_da_caixa['disponiveis']).to eq(
      [{ 'id' => lia.id, 'name' => 'Lia', 'parado' => true }, { 'id' => marta.id, 'name' => 'Marta', 'parado' => true }]
    )
  end

  it 'sem a Fase 2 a caixa não leva os agentes e a tela os esconde' do
    Autonomia::Agents::Fase2.desligar!(account)

    get url, headers: auth_headers(admin)

    caixa = response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
    expect(caixa).not_to have_key('ai_agents')
  end

  it 'põe o agente parado como área, liga e grava o funil, tirando-o de quem tinha' do
    salvar([{ id: maria.id, pipeline_ids: [] }, { id: marta.id, pipeline_ids: [vendas.id] }])

    expect(response).to have_http_status(:ok)
    expect(area?(marta)).to be(true)
    expect(marta.reload).to have_attributes(status: 'active', enabled: true)
    expect(area?(maria)).to be(true)
    expect(linhas).to eq([[vendas.id, marta.id]])
    expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents', 'areas').pluck('name', 'pipeline_ids'))
      .to eq([['Maria', []], ['Marta', [vendas.id]]])
  end

  it 'tira da caixa o agente que não veio: apaga os funis dele e, sendo a última caixa, ele para' do
    salvar([])

    expect(response).to have_http_status(:ok)
    expect(area?(maria)).to be(false)
    expect(linhas).to be_empty
    expect(maria.reload).to have_attributes(status: 'paused', enabled: false)
    expect(maria.events.where(event_type: :parado_sem_onde_trabalhar)).to exist
  end

  it 'sem a chave ai_agents não mexe nos agentes; funil que sai da caixa leva a linha junto' do
    put "#{url}/#{inbox.id}", params: { caixa: { pipeline_ids: [suporte.id], modo: 'off', people: [] } },
                              headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(area?(maria)).to be(true)
    expect(linhas).to be_empty
  end

  it 'com o principal pausado, a área que já está na caixa fica e troca de funil: o leitor só vale para quem entra (#1570)' do
    clara.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

    salvar([{ id: maria.id, pipeline_ids: [suporte.id] }])

    expect(response).to have_http_status(:ok)
    expect(area?(maria)).to be(true)
    expect(linhas).to eq([[suporte.id, maria.id]])
  end

  it 'a lista de caixas não consulta se a caixa aceita área; só a caixa aberta (#1570)' do
    sem_principal = create_crm_inbox(account: account, name: 'WhatsApp Recepção', members: [admin])
    allow(Autonomia::Agents::Areas).to receive(:caixa_aceita_area?).and_call_original

    get url, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(Autonomia::Agents::Areas).not_to have_received(:caixa_aceita_area?)

    get "#{url}/#{sem_principal.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents')).to include('porta' => nil, 'pode_mudar' => true)
    expect(Autonomia::Agents::Areas).to have_received(:caixa_aceita_area?).once
  end

  it 'diz se quem atende primeiro é agente de IA ou agente externo (#1570)' do
    get "#{url}/#{inbox.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'caixa', 'agent_bot')).to include('name' => 'Clara', 'tipo_do_principal' => 'ia')

    externa = create(:inbox, account: account)
    robo = create(:agent_bot, account: account, name: 'Robô n8n')
    AgentBotInbox.create!(inbox: externa, agent_bot: robo, account: account, status: :active)
    get "#{url}/#{externa.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'caixa', 'agent_bot')).to include('name' => 'Robô n8n', 'tipo_do_principal' => 'externo')

    # Vínculo da porta apagado com o robô ainda ligado na caixa: não é mais a porta, é agente externo (mesma regra de
    # AgentInbox.robo_externo_na_caixa?).
    Autonomia::Agents::AgentInbox.kept.porta.find_by!(inbox: inbox).update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    get "#{url}/#{inbox.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'caixa', 'agent_bot')).to include('tipo_do_principal' => 'externo')
  end

  it 'o principal sai da caixa: ela fica só de pessoas e a área continua listada e ativa (#1570)' do
    Autonomia::Agents::Operate::InboxConnector.new(agent: clara, inbox: inbox).perform(connect: false)

    caixa = agentes_da_caixa
    expect(caixa['porta']).to be_nil
    expect(caixa['areas'].pluck('name')).to eq(['Maria'])
    expect(area?(maria)).to be(true)
    expect(maria.reload).to be_operating
  end

  it 'funil arquivado não aparece na tela e o responsável dele fica' do
    arquivado = create_crm_pipeline(account: account, user: admin, name: 'Antigo').first
    account.crm_pipeline_inboxes.create!(inbox: inbox, pipeline: arquivado)
    Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: arquivado, agent: maria)
    arquivado.update!(status: :archived)

    salvar([{ id: maria.id, pipeline_ids: [] }])

    expect(response).to have_http_status(:ok)
    expect(linhas).to eq([[arquivado.id, maria.id]])
  end

  # #1433: a mesma regra da caixa da API dos Agentes e da gaveta (Areas.caixa_aceita_area?, leitor único).
  describe 'caixa sem principal' do
    let(:so_de_pessoas) { create_crm_inbox(account: account, name: 'WhatsApp Recepção', members: [admin]) }

    before do
      account.crm_inbox_settings.create!(inbox: so_de_pessoas, crm_enabled: true, subject_ai_mode: 'auto')
      account.crm_pipeline_inboxes.create!(inbox: so_de_pessoas, pipeline: vendas)
    end

    def salvar_na(caixa, ai_agents)
      put "#{url}/#{caixa.id}", params: { caixa: { pipeline_ids: [vendas.id], modo: 'chegou', people: [], ai_agents: ai_agents } },
                                headers: auth_headers(admin), as: :json
    end

    it 'caixa só de pessoas aceita área pelo CRM, e a tela a oferece' do
      get "#{url}/#{so_de_pessoas.id}", headers: auth_headers(admin)
      expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents')).to include('porta' => nil, 'pode_mudar' => true)

      salvar_na(so_de_pessoas, [{ id: marta.id, pipeline_ids: [vendas.id] }])

      expect(response).to have_http_status(:ok)
      expect(Autonomia::Agents::AgentInbox.kept.area.exists?(inbox: so_de_pessoas, agent: marta)).to be(true)
      expect(marta.reload).to be_operating
    end

    it 'caixa com agente externo recusa com crm.caixas.robo_externo, e a tela não a oferece' do
      AgentBotInbox.create!(inbox: so_de_pessoas, agent_bot: create(:agent_bot, account: account), account: account)
      get "#{url}/#{so_de_pessoas.id}", headers: auth_headers(admin)
      expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents')).to include('pode_mudar' => false, 'disponiveis' => [])

      salvar_na(so_de_pessoas, [{ id: marta.id, pipeline_ids: [vendas.id] }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.robo_externo')
      expect(Autonomia::Agents::AgentInbox.kept.where(inbox: so_de_pessoas)).to be_empty
    end

    it 'principal parado recusa com crm.caixas.principal_parado' do
      clara.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

      salvar([{ id: maria.id, pipeline_ids: [vendas.id] }, { id: marta.id, pipeline_ids: [suporte.id] }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.principal_parado')
      expect(area?(marta)).to be(false)
    end

    it 'a recusa que vem de dentro do Areas (caixa travada) também sai pelo código' do
      allow(Autonomia::Agents::Areas).to receive(:vincular!).and_raise(Autonomia::Agents::Areas::CaixaNaoAceitaArea.new(:robo_externo))

      salvar_na(so_de_pessoas, [{ id: marta.id, pipeline_ids: [vendas.id] }])

      expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.robo_externo')
    end
  end

  describe 'recusa sem gravar nada' do
    def expect_recusa(code, status: :unprocessable_entity)
      expect(response).to have_http_status(status)
      expect(response.parsed_body.dig('error', 'code')).to eq(code)
      expect(linhas).to eq([[vendas.id, maria.id]])
      expect(area?(marta)).to be(false)
    end

    it 'o mesmo funil com dois agentes' do
      salvar([{ id: maria.id, pipeline_ids: [vendas.id] }, { id: marta.id, pipeline_ids: [vendas.id] }])
      expect_recusa('crm.caixas.funil_com_dois_agentes')
    end

    it 'funil que não é desta caixa' do
      outro = create_crm_pipeline(account: account, user: admin, name: 'Outro').first
      salvar([{ id: marta.id, pipeline_ids: [outro.id] }])
      expect_recusa('crm.caixas.funil_invalido')
    end

    it 'a porta, agente interno ou de outra conta como área' do
      salvar([{ id: clara.id, pipeline_ids: [suporte.id] }])
      expect_recusa('crm.caixas.agente_invalido')

      salvar([{ id: agente('Copiloto', actuation: :internal).id, pipeline_ids: [] }])
      expect_recusa('crm.caixas.agente_invalido')

      alheio = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Alheio', agent_type: 'custom')
      salvar([{ id: alheio.id, pipeline_ids: [] }])
      expect_recusa('crm.caixas.agente_invalido')
    end

    it 'rascunho (código próprio, #1570) ou pausado de propósito como área: 422, nunca 500 (#1433)' do
      salvar([{ id: agente('Rascunho', status: :draft, enabled: false, instruction: 'Pronto.').id, pipeline_ids: [] }])
      expect_recusa('crm.caixas.agente_rascunho')

      pausado = agente('Pausado')
      Autonomia::Agents::Operate::InboxConnector.new(agent: pausado, inbox: create(:inbox, account: account)).perform(connect: true)
      pausado.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
      salvar([{ id: pausado.id, pipeline_ids: [] }])
      expect_recusa('crm.caixas.agente_invalido')
      expect(pausado.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'o mesmo agente duas vezes' do
      salvar([{ id: marta.id, pipeline_ids: [suporte.id] }, { id: marta.id, pipeline_ids: [] }])
      expect_recusa('crm.caixas.agente_invalido')
    end

    it 'sem a Fase 2' do
      Autonomia::Agents::Fase2.desligar!(account)
      salvar([{ id: marta.id, pipeline_ids: [suporte.id] }])
      expect_recusa('crm.caixas.agentes_desligados')
    end
  end
end
