require 'rails_helper'

# #1433 (tema 13, tela) — "Agente da equipe" na criação: POST channels com papel 'area' põe o agente na caixa como área
# (recebe quando alguém passa) e já o liga, pelo Autonomia::Agents::Areas. Só na Fase 2, em caixa com principal
# atendendo ou atendida só por pessoas (sem principal e sem robô de fora). A leitura de canais diz quem está na equipe
# de cada caixa, e o agente diz se está só na equipe.
RSpec.describe 'Autonomia agente da equipe', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Vendas') }
  let(:principal) { agente('Sofia', status: :active, enabled: true) }
  # O rascunho da criação com a conversa já fechada (tem instrução): é quem "Começar a trabalhar" põe na equipe.
  let(:novo) { agente('Bruno', instruction: 'Atende o financeiro.') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    Autonomia::Agents::Fase2.ligar!(account)
    account.enable_features!('autonomia_agents_journey')
    conectar(principal, inbox)
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', mode: :guided,
                                       status: :draft, enabled: false }.merge(attrs))
  end

  def conectar(agent, caixa)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
  end

  def pedir_area(agent = novo, caixa = inbox, conta: account)
    post "/api/v1/accounts/#{conta.id}/autonomia/agents/#{agent.id}/channels",
         params: { inbox_id: caixa.id, papel: 'area' }, headers: headers, as: :json
  end

  def erro(chave, agent: novo, caixa: inbox)
    I18n.t("autonomia.agents.operate.area_errors.#{chave}", nome: agent.name, canal: caixa.name)
  end

  describe 'POST channels com papel area' do
    it 'vincula como área e liga o agente na mesma ação, e a caixa segue com o principal' do
      pedir_area

      expect(response).to have_http_status(:created)
      vinculo = Autonomia::Agents::AgentInbox.kept.find_by(agent: novo, inbox: inbox)
      expect(vinculo).to have_attributes(papel: 'area')
      expect(novo.reload).to have_attributes(status: 'active', enabled: true)
      expect(inbox.reload.agent_bot).to eq(principal.agent_inboxes.kept.porta.first.agent_bot)
      expect(response.parsed_body['payload']).to contain_exactly(include('inbox_id' => inbox.id, 'papel' => 'area'))
    end

    it 'aceita a caixa só de pessoas (sem principal e sem robô): vincula como área e liga, e a caixa segue sem robô' do
      livre = create(:inbox, account: account, name: 'Instagram')

      expect { pedir_area(novo, livre) }.to change(Autonomia::Agents::AgentInbox, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::AgentInbox.kept.find_by(agent: novo, inbox: livre)).to have_attributes(papel: 'area')
      expect(novo.reload).to have_attributes(status: 'active', enabled: true)
      expect(livre.reload.agent_bot).to be_nil
    end

    it 'devolve 422 quando o principal da caixa está parado' do
      principal.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

      pedir_area

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:sem_principal))
    end

    it 'devolve 422 para caixa com outro robô (webhook), que não é um principal da Autonom.ia, e nada muda' do
      externa = create(:inbox, account: account, name: 'Site')
      AgentBotInbox.create!(inbox: externa, agent_bot: create(:agent_bot, account: account))

      expect { pedir_area(novo, externa) }.not_to change(Autonomia::Agents::AgentInbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:robo_externo, caixa: externa))
      expect(novo.reload).to have_attributes(status: 'draft', enabled: false)
    end

    it 'confere o robô de fora dentro da trava: se ele entrar entre a leitura e o vínculo, 422 e nada muda' do
      livre = create(:inbox, account: account, name: 'Instagram')
      allow(Autonomia::Agents::Areas).to receive(:vincular!).and_wrap_original do |original, **kwargs|
        AgentBotInbox.create!(inbox: livre, agent_bot: create(:agent_bot, account: account))
        original.call(**kwargs)
      end

      pedir_area(novo, livre)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:robo_externo, caixa: livre))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: novo)).to be_empty
      expect(novo.reload).to have_attributes(status: 'draft', enabled: false)
    end

    it 'devolve 422 para o rascunho cuja conversa de criação não fechou (sem instrução), e nada muda' do
      pela_metade = agente('Pela metade')

      expect { pedir_area(pela_metade) }.not_to change(Autonomia::Agents::AgentInbox, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:rascunho, agent: pela_metade))
      expect(pela_metade.reload).to have_attributes(status: 'draft', enabled: false)
    end

    it 'devolve 422 para quem foi pausado de propósito e ainda tem caixa, e não o liga' do
      outra = create(:inbox, account: account, name: 'WhatsApp Suporte')
      pausado = agente('Leo', status: :active, enabled: true, instruction: 'Atende o suporte.')
      conectar(pausado, outra)
      pausado.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

      pedir_area(pausado)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:nao_pode_ser_area, agent: pausado))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: pausado, inbox: inbox)).to be_empty
      expect(pausado.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'devolve 422 para o agente interno (Copiloto da equipe)' do
      copiloto = agente('Copiloto', actuation: :internal)

      pedir_area(copiloto)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:agent_internal, agent: copiloto))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: copiloto)).to be_empty
    end

    it 'repetir o pedido da área que já está ativa é sucesso: 200 e o mesmo vínculo, sem outro espelho' do
      pedir_area
      vinculo = Autonomia::Agents::AgentInbox.kept.find_by(agent: novo, inbox: inbox)

      expect { pedir_area }.not_to(change { [AgentBot.count, Autonomia::Agents::AgentInbox.count] })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to contain_exactly(include('id' => vinculo.id, 'papel' => 'area'))
    end

    it 'devolve 422 quando o agente já é o principal da caixa' do
      pedir_area(principal)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:already_linked, agent: principal))
    end

    it 'confere o principal atendendo dentro da trava: se ele parar entre a leitura e o vínculo, 422 e nada muda' do
      allow(Autonomia::Agents::Areas).to receive(:vincular!).and_wrap_original do |original, **kwargs|
        principal.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
        original.call(**kwargs)
      end

      pedir_area

      expect(Autonomia::Agents::Areas).to have_received(:vincular!).with(agent: novo, inbox: inbox, ativar: true, de_rascunho: true)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:sem_principal))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: novo)).to be_empty
      expect(novo.reload).to have_attributes(status: 'draft', enabled: false)
    end

    it 'responde 422 (nunca 500) quando dois pedidos iguais correm juntos e o índice único recusa o segundo' do
      allow(Autonomia::Agents::Areas).to receive(:vincular!).and_raise(ActiveRecord::RecordNotUnique)

      pedir_area

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:already_linked))
    end

    it 'devolve 422 sem a Fase 2 na conta' do
      Autonomia::Agents::Fase2.desligar!(account)

      pedir_area

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(erro(:fase2_off))
      expect(Autonomia::Agents::AgentInbox.kept.where(agent: novo)).to be_empty
    end

    it 'isola a conta: caixa ou agente de outra conta não existem para esta (404), e nada é vinculado' do
      outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      Autonomia::Agents::Fase2.ligar!(outra)
      caixa_de_fora = create(:inbox, account: outra)
      agente_de_fora = Autonomia::Agents::Agent.create!(account: outra, name: 'Fora', agent_type: 'custom', status: :draft,
                                                        enabled: false)

      pedir_area(novo, caixa_de_fora)
      expect(response).to have_http_status(:not_found)

      pedir_area(agente_de_fora, inbox)
      expect(response).to have_http_status(:not_found)

      expect(Autonomia::Agents::AgentInbox.where(inbox: caixa_de_fora).or(
               Autonomia::Agents::AgentInbox.where(agent: agente_de_fora)
             )).to be_empty
    end

    it 'sem papel, segue o caminho de sempre (o principal): caixa ocupada é recusada' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{novo.id}/channels",
           params: { inbox_id: inbox.id, ativar: true }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.operate.connect_errors.inbox_already_connected'))
    end
  end

  describe 'leituras' do
    before { pedir_area }

    it 'channels#index mostra só os vínculos ativos, com o papel; a área arquivada some' do
      outra = create(:inbox, account: account, name: 'WhatsApp Suporte')
      conectar(agente('Leo', status: :active, enabled: true), outra)
      pedir_area(novo, outra)
      Autonomia::Agents::Areas.desvincular!(agent: novo, inbox: outra)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{novo.id}/channels", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to contain_exactly(include('inbox_id' => inbox.id, 'papel' => 'area'))
      expect(Autonomia::Agents::AgentInbox.where(agent: novo, inbox: outra).where.not(deleted_at: nil)).to exist
    end

    it 'canais_ocupados lista o agente da equipe da caixa, sem tirar o principal' do
      get "/api/v1/accounts/#{account.id}/autonomia/canais_ocupados", headers: headers, as: :json

      linha = response.parsed_body['payload'].find { |row| row['inbox_id'] == inbox.id }
      expect(linha['occupied_by']).to include('kind' => 'agent', 'agent_id' => principal.id, 'operating' => true)
      expect(linha['areas']).to eq([{ 'agent_id' => novo.id, 'agent_name' => 'Bruno', 'operating' => true }])
    end

    it 'o agente diz que está só na equipe; o principal não' do
      get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers, as: :json

      por_id = response.parsed_body['payload'].index_by { |agent| agent['id'] }
      expect(por_id[novo.id]).to include('na_equipe' => true, 'tem_onde_trabalhar' => true, 'status' => 'active')
      expect(por_id[principal.id]).to include('na_equipe' => false)
    end

    it 'a conta diz se a Fase 2 está ligada' do
      get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

      expect(response.parsed_body['autonomia_agents_fase2']).to be(true)
    end
  end
end
