require 'rails_helper'

# Funções personalizadas, lote 1 (#1788): a área de Agentes de IA respeita a caixa.
# - Conversas por resultado (aba Desempenho) seguem a regra da lista de conversas: caixa, funil e função.
# - Regra G: pôr ou tirar agente de uma caixa pede ser membro dela ou ter inbox_manage. Administrador passa sempre.
RSpec.describe 'Agentes de IA respeitam a caixa', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:dela) { create(:inbox, account: account, name: 'Vendas') }
  let(:alheia) { create(:inbox, account: account, name: 'Suporte') }
  let(:outra) { create(:inbox, account: account, name: 'Instagram') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda.' }.merge(attrs))
  end

  def pessoa_com(permissions, caixas: [dela])
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixas.each { |caixa| caixa.add_members([user.id]) }
    user
  end

  describe 'GET analytics/conversations' do
    let(:ana) { agente('Ana') }
    let(:conversa_dela) { create(:conversation, account: account, inbox: dela) }
    let(:conversa_alheia) { create(:conversation, account: account, inbox: alheia) }

    before do
      [conversa_dela, conversa_alheia].each do |conversa|
        Autonomia::Agents::AgentEvent.create!(agent: ana, account: account, conversation_id: conversa.id, event_type: :replied)
      end
    end

    def listar(user)
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{ana.id}/analytics/conversations",
          params: { range: '7d', metric: 'handled' }, headers: user.create_new_auth_token, as: :json
      response.parsed_body['payload'].map { |item| item.dig('conversation', 'display_id') }
    end

    it 'mostra só as conversas das caixas de que a pessoa é membro' do
      ids = listar(pessoa_com(%w[autonomia_view conversation_manage]))

      expect(response).to have_http_status(:success)
      expect(ids).to eq([conversa_dela.display_id])
    end

    it 'mostra todas para o administrador' do
      expect(listar(admin)).to contain_exactly(conversa_dela.display_id, conversa_alheia.display_id)
    end

    it 'não mostra nenhuma para a função sem chave de conversa' do
      expect(listar(pessoa_com(%w[autonomia_view]))).to eq([])
    end

    it 'mantém os totais do painel da conta' do
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{ana.id}/analytics",
          params: { range: '7d' }, headers: pessoa_com(%w[autonomia_view]).create_new_auth_token, as: :json

      expect(response.parsed_body.dig('outcomes', 'handled')).to eq(2)
    end
  end

  describe 'POST e DELETE channels' do
    let(:bruno) { agente('Bruno', actuation: :external) }

    def ligar(user, caixa)
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{bruno.id}/channels",
           params: { inbox_id: caixa.id }, headers: user.create_new_auth_token, as: :json
    end

    it 'liga o agente na caixa de que a pessoa é membro' do
      ligar(pessoa_com(%w[autonomia_manage]), dela)

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: bruno).pluck(:inbox_id)).to eq([dela.id])
    end

    it 'recusa a caixa de que a pessoa não é membro, com o motivo, sem ligar nada' do
      ligar(pessoa_com(%w[autonomia_manage]), alheia)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.operate.connect_errors.fora_do_alcance'))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: bruno)).to be_empty
    end

    it 'recusa pôr o agente na equipe de uma caixa de que a pessoa não é membro' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{bruno.id}/channels",
           params: { inbox_id: alheia.id, papel: 'area' }, headers: pessoa_com(%w[autonomia_manage]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.operate.connect_errors.fora_do_alcance'))
      expect(Autonomia::Agents::AgentInbox.where(agent: bruno)).to be_empty
    end

    it 'aceita qualquer caixa para quem tem inbox_manage' do
      ligar(pessoa_com(%w[autonomia_manage inbox_manage], caixas: []), alheia)

      expect(response).to have_http_status(:created)
    end

    it 'aceita qualquer caixa para o administrador' do
      ligar(admin, alheia)

      expect(response).to have_http_status(:created)
    end

    it 'não deixa tirar o agente de uma caixa que a pessoa não alcança' do
      Autonomia::Agents::Operate::InboxConnector.new(agent: bruno, inbox: alheia).perform(connect: true)

      delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{bruno.id}/channels/#{alheia.id}",
             headers: pessoa_com(%w[autonomia_manage]).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: bruno).pluck(:inbox_id)).to eq([alheia.id])
    end

    it 'diz em canais_ocupados quais caixas a pessoa alcança' do
      account.enable_features!('autonomia_agents_journey')
      [dela, alheia].each(&:id)

      get "/api/v1/accounts/#{account.id}/autonomia/canais_ocupados",
          headers: pessoa_com(%w[autonomia_manage]).create_new_auth_token, as: :json

      alcance = response.parsed_body['payload'].to_h { |canal| [canal['inbox_id'], canal['alcanca']] }
      expect(response).to have_http_status(:success)
      expect(alcance).to eq(dela.id => true, alheia.id => false)
    end

    it 'oferece só as caixas que a pessoa alcança' do
      [dela, alheia].each(&:id)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{bruno.id}/channels",
          headers: pessoa_com(%w[autonomia_manage]).create_new_auth_token, as: :json

      expect(response.parsed_body['eligible_inboxes'].pluck('id')).to eq([dela.id])
    end
  end

  describe 'PUT onde_atende' do
    let(:hubber) { agente('Hubber') }

    before do
      Autonomia::Agents::Fase2.ligar!(account)
      Autonomia::Agents::Operate::InboxConnector.new(agent: agente('Clara'), inbox: outra).perform(connect: true)
      Autonomia::Agents::Areas.vincular!(agent: hubber, inbox: dela)
      Autonomia::Agents::Areas.vincular!(agent: hubber, inbox: alheia)
    end

    def salvar(user, **params)
      put "/api/v1/accounts/#{account.id}/autonomia/agents/#{hubber.id}/onde_atende",
          params: params, headers: user.create_new_auth_token, as: :json
    end

    def areas
      Autonomia::Agents::AgentInbox.kept.area.where(autonomia_agent_id: hubber.id).pluck(:inbox_id).sort
    end

    it 'mantém a área na caixa que a pessoa não alcança, mesmo fora do pedido' do
      salvar(pessoa_com(%w[autonomia_manage]), manter_primeiro: true, area_inbox_ids: [dela.id])

      expect(response).to have_http_status(:no_content)
      expect(areas).to eq([dela.id, alheia.id].sort)
    end

    it 'tira a área de uma caixa que a pessoa alcança' do
      salvar(pessoa_com(%w[autonomia_manage], caixas: [dela, alheia]), manter_primeiro: true, area_inbox_ids: [alheia.id])

      expect(response).to have_http_status(:no_content)
      expect(areas).to eq([alheia.id])
    end

    it 'recusa pôr área numa caixa que a pessoa não alcança' do
      salvar(pessoa_com(%w[autonomia_manage]), manter_primeiro: true, area_inbox_ids: [dela.id, alheia.id, outra.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'fora_do_alcance')
      expect(areas).to eq([dela.id, alheia.id].sort)
    end

    it 'recusa trocar onde atende primeiro quando a porta de hoje está numa caixa que a pessoa não alcança' do
      Autonomia::Agents::Operate::InboxConnector.new(agent: hubber, inbox: create(:inbox, account: account)).perform(connect: true)

      salvar(pessoa_com(%w[autonomia_manage]), primeiro_inbox_id: nil, area_inbox_ids: [dela.id, alheia.id], parar: true)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'fora_do_alcance')
      expect(Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: hubber.id)).to exist
    end

    it 'recusa escolher para atender primeiro uma caixa que a pessoa não alcança' do
      livre = create(:inbox, account: account)

      salvar(pessoa_com(%w[autonomia_manage]), primeiro_inbox_id: livre.id, area_inbox_ids: [dela.id, alheia.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'fora_do_alcance')
      expect(Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: hubber.id)).to be_empty
    end

    it 'deixa a área alcançável virar porta, e a área escondida fica' do
      salvar(pessoa_com(%w[autonomia_manage]), primeiro_inbox_id: dela.id, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: hubber.id).pluck(:inbox_id)).to eq([dela.id])
      expect(areas).to eq([alheia.id])
    end

    it 'troca a porta quando todas as portas de hoje são alcançáveis' do
      antiga = create(:inbox, account: account)
      Autonomia::Agents::Operate::InboxConnector.new(agent: hubber, inbox: antiga).perform(connect: true)
      nova = create(:inbox, account: account)

      salvar(pessoa_com(%w[autonomia_manage], caixas: [antiga, nova]), primeiro_inbox_id: nova.id, area_inbox_ids: [dela.id, alheia.id])

      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: hubber.id).pluck(:inbox_id)).to eq([nova.id])
    end

    it 'não pede para confirmar a parada quando a área escondida segue' do
      salvar(pessoa_com(%w[autonomia_manage]), primeiro_inbox_id: nil, area_inbox_ids: [])

      expect(response).to have_http_status(:no_content)
      expect(areas).to eq([alheia.id])
    end

    it 'deixa quem tem inbox_manage mexer em qualquer caixa' do
      salvar(pessoa_com(%w[autonomia_manage inbox_manage], caixas: []), manter_primeiro: true, area_inbox_ids: [outra.id])

      expect(response).to have_http_status(:no_content)
      expect(areas).to eq([outra.id])
    end

    it 'deixa o administrador mexer em tudo' do
      salvar(admin, manter_primeiro: true, area_inbox_ids: [dela.id])

      expect(response).to have_http_status(:no_content)
      expect(areas).to eq([dela.id])
    end
  end
end
