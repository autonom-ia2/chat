require 'rails_helper'

# Funis visíveis (#1148, PR D, decisão do Rodrigo em 11/10): o seletor do Kanban, as etapas, o painel do CRM (relatórios
# e resumo da Meta) e a soma da CTWA mostram só os funis e os cards da pessoa. Cada caso confere o que ela NÃO vê; o
# fim do arquivo confere que, sem nenhuma linha de acesso, tudo segue como antes.
RSpec.describe Crm::Access::VisiblePipelines do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:outra_caixa) { create_crm_inbox(account: account, name: 'Instagram', members: [agent]) }
  let(:caixa_alheia) { create_crm_inbox(account: account, name: 'Filial') }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:instagram) { create_crm_pipeline(account: account, user: admin, name: 'Instagram') }
  let(:filial) { create_crm_pipeline(account: account, user: admin, name: 'Filial') }
  let(:avulso) { create_crm_pipeline(account: account, user: admin, name: 'Prospecção') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: BigDecimal('5.00'), fetched_at: Time.current.iso8601,
                                                                 rate_unavailable: false)
    link(inbox, vendas, sinistro)
    link(outra_caixa, instagram)
    link(caixa_alheia, filial)
    avulso
  end

  def link(target_inbox, *pipelines)
    pipelines.each { |(pipeline, _stage)| Crm::PipelineInbox.create!(account: account, inbox: target_inbox, pipeline: pipeline) }
  end

  def restrict(user, pipelines: [vendas], all_pipelines: false, only_own: false, target_inbox: inbox)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: target_inbox, user: user, all_pipelines: all_pipelines,
                                           triage: false, only_own: only_own)
    pipelines.each { |(pipeline, _stage)| access.agent_pipelines.create!(account: account, pipeline: pipeline) }
    access
  end

  def visible(user = agent)
    described_class.new(user: user, account: account).apply(account.crm_pipelines).pluck(:name)
  end

  def report_visible(user = agent)
    described_class.new(user: user, account: account).apply_to_reports(account.crm_pipelines).pluck(:name)
  end

  def headers(user = agent)
    user.create_new_auth_token
  end

  def api(path)
    "/api/v1/accounts/#{account.id}/#{path}"
  end

  describe 'quais funis a pessoa vê' do
    it 'com funis escolhidos numa caixa: só esses dali, os das caixas sem restrição e os avulsos' do
      restrict(agent)

      expect(visible).to contain_exactly('Vendas', 'Instagram', 'Prospecção')
      expect(report_visible).to contain_exactly('Vendas', 'Instagram', 'Prospecção')
    end

    it 'com todos os funis da caixa: todos os ligados a ela' do
      restrict(agent, pipelines: [], all_pipelines: true)

      expect(visible).to include('Vendas', 'Sinistro')
      expect(visible).not_to include('Filial')
    end

    it 'em "Só as suas": os funis da caixa aparecem no Kanban, mas não no painel' do
      restrict(agent, pipelines: [], only_own: true)

      expect(visible).to include('Vendas', 'Sinistro')
      expect(report_visible).not_to include('Vendas', 'Sinistro')
    end

    it 'linha de uma caixa da qual ela saiu não libera nada' do
      restrict(agent, pipelines: [filial], target_inbox: caixa_alheia)
      restrict(agent)

      expect(visible).not_to include('Filial')
    end

    it 'administrador vê todos os funis, mesmo com linha' do
      restrict(admin)

      expect(visible(admin)).to contain_exactly('Vendas', 'Sinistro', 'Instagram', 'Filial', 'Prospecção')
    end
  end

  describe 'telas e APIs', type: :request do
    before { restrict(agent) }

    it 'a lista de funis e o seletor do Kanban não trazem o funil de fora' do
      get api('crm/pipelines'), headers: headers

      expect(response.parsed_body['payload'].pluck('name')).not_to include('Sinistro', 'Filial')

      get api('crm/kanban'), params: { pipeline_id: sinistro.first.id }, headers: headers

      expect(response.parsed_body.dig('payload', 'pipeline')).to be_nil
    end

    it 'as etapas de um funil de fora respondem 404' do
      get api("crm/pipelines/#{sinistro.first.id}/stages"), headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'a contagem por etapa soma só os cards que a pessoa vê' do
      account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Meu', inbox: inbox, owner: agent)
      account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Outro', inbox: outra_caixa)
      restrict(agent, pipelines: [], target_inbox: outra_caixa)

      get api("crm/pipelines/#{vendas.first.id}/stages"), headers: headers

      expect(response.parsed_body['payload'].first['total_cards_count']).to eq(1)
    end

    it 'o painel lista só os funis dela e recusa o relatório de outro funil' do
      get api('crm/reports/pipelines'), headers: headers
      expect(response.parsed_body['payload'].pluck('name')).to contain_exactly('Vendas', 'Instagram', 'Prospecção')

      get api('crm/reports/summary'), params: { pipeline_id: sinistro.first.id }, headers: headers
      expect(response).to have_http_status(:not_found)

      get api('crm/reports/summary'), headers: headers
      expect(response.parsed_body.dig('payload', 'pipeline', 'name')).to be_in(%w[Vendas Instagram Prospecção])
    end

    it 'sem funil nenhum no painel, não há relatório (nada da conta inteira)' do
      Crm::InboxAgentAccess.find_by(user: agent).update!(only_own: true)
      restrict(agent, pipelines: [], only_own: true, target_inbox: outra_caixa)
      link(caixa_alheia, avulso)

      get api('crm/reports/pipelines'), headers: headers
      expect(response.parsed_body['payload']).to eq([])

      get api('crm/reports/workload'), headers: headers
      expect(response.parsed_body['payload']).to be_nil
    end

    it 'o resumo da Meta soma só os funis do painel dela' do
      create_meta_event(vendas.first, 10_000)
      create_meta_event(sinistro.first, 90_000)

      get api('crm/meta_conversions/summary'), headers: headers

      expect(response.parsed_body.dig('payload', 'accepted_value_by_currency')).to eq('BRL' => 10_000)
    end

    it 'a soma da campanha (CTWA) conta só os cards que a pessoa vê' do
      conversation = conversation_from_campaign
      won_card(vendas, conversation, 300_000)
      won_card(sinistro, conversation, 800_000)

      get api('ctwa_campaigns'), params: { include_origin_metrics: true, since: 2.days.ago.iso8601, until: 1.day.from_now.iso8601 },
                                 headers: headers

      expect(response.parsed_body['origin_metrics'].first['won_value_by_currency']).to eq([{ 'currency' => 'BRL', 'value_cents' => 300_000 }])
    end
  end

  describe 'outras portas para um funil escondido (revisão do PR D)', type: :request do
    around { |example| with_modified_env(CRM_AI_ENABLED: 'true') { example.run } }

    before { restrict(agent) }

    it 'o consumo de IA de um funil que a pessoa não tem é 404; sem funil, segue o da conta' do
      get api('crm/ai_usage'), params: { pipeline_id: sinistro.first.id }, headers: headers
      expect(response).to have_http_status(:not_found)

      get api('crm/ai_usage'), headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'o resumo da Meta de um funil escondido é 404' do
      get api('crm/meta_conversions/summary'), params: { pipeline_id: sinistro.first.id }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'visão salva de funil escondido não aparece nem pode ser gravada' do
      saved_view(sinistro, 'Sinistros abertos')
      saved_view(vendas, 'Vendas da semana')

      get api('crm/saved_views'), headers: headers
      expect(response.parsed_body['payload'].pluck('name')).to contain_exactly('Vendas da semana')

      post api('crm/saved_views'), params: { saved_view: { name: 'X', pipeline_id: sinistro.first.id, config: { columns: ['title'] } } },
                                   headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'a sugestão de assunto novo num funil que a pessoa não pode criar não aparece' do
      conversation = suggested_conversation(sinistro)

      get api("crm/conversations/#{conversation.display_id}/cards"), headers: headers

      expect(response.parsed_body['suggestion']).to be_nil
    end
  end

  describe Crm::Access::ConversationScope do
    it 'usuário de integração com linha antiga não fica restrito' do
      bot_user = create_crm_agent(account: account, name: 'n8n').first
      inbox.add_members([bot_user.id])
      Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: bot_user, all_pipelines: false, triage: false)
      AccountUser.find_by(account: account, user: bot_user).update!(integration: true)

      expect(described_class.new(user: bot_user, account: account).restricted?).to be(false)
    end
  end

  describe Crm::InboxAgentAccess do
    it 'usuário de integração (token do n8n, MCP) não pode ter acesso por funil' do
      bot_user = create(:user, account: account, role: :agent)
      AccountUser.find_by(account: account, user: bot_user).update!(integration: true)
      inbox.add_members([bot_user.id])

      access = described_class.new(account: account, inbox: inbox, user: bot_user, all_pipelines: false, triage: false)

      expect(access).not_to be_valid
      expect(access.errors[:user_id]).to include('must not be an integration user')
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)', type: :request do
    it 'funis, painel, etapas e CTWA seguem como antes' do
      expect(described_class.new(user: agent, account: account).apply(account.crm_pipelines)).to equal(account.crm_pipelines)

      get api('crm/reports/pipelines'), headers: headers
      expect(response.parsed_body['payload'].size).to eq(5)

      get api('crm/reports/summary'), params: { pipeline_id: 0 }, headers: headers
      expect(response).to have_http_status(:ok)

      get api("crm/pipelines/#{filial.first.id}/stages"), headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'CTWA, visões salvas, consumo de IA e sugestão seguem como antes' do
      conversation = conversation_from_campaign
      won_card(vendas, conversation, 300_000)
      won_card(sinistro, conversation, 800_000)
      saved_view(sinistro, 'Sinistros abertos')

      get api('ctwa_campaigns'), params: { include_origin_metrics: true, since: 2.days.ago.iso8601, until: 1.day.from_now.iso8601 },
                                 headers: headers
      expect(response.parsed_body['origin_metrics'].first['won_value_by_currency']).to eq([{ 'currency' => 'BRL', 'value_cents' => 1_100_000 }])

      get api('crm/saved_views'), headers: headers
      expect(response.parsed_body['payload'].pluck('name')).to include('Sinistros abertos')

      get api("crm/conversations/#{suggested_conversation(sinistro).display_id}/cards"), headers: headers
      expect(response.parsed_body['suggestion']).to include('pipeline_name' => 'Sinistro')

      with_modified_env(CRM_AI_ENABLED: 'true') { get api('crm/ai_usage'), params: { pipeline_id: sinistro.first.id }, headers: headers }
      expect(response).to have_http_status(:ok)
    end
  end

  def saved_view((pipeline, _stage), name)
    Crm::SavedView.create!(account: account, user: admin, pipeline: pipeline, name: name, visibility: :account,
                           config: { 'columns' => ['title'] })
  end

  def suggested_conversation((pipeline, _stage))
    account.crm_inbox_settings.find_or_create_by!(inbox: inbox) { |setting| setting.assign_attributes(crm_enabled: true, subject_ai_mode: :suggest) }
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: agent)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
    Crm::SubjectDecision.create!(account: account, conversation: conversation, message: message, mode: 'suggest', action: 'create',
                                 state: 'suggested', title: 'Batida no carro', pipeline: pipeline)
    conversation
  end

  def create_meta_event(pipeline, value_cents)
    card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Ganho', inbox: inbox)
    Crm::MetaConversionEvent.create!(account_id: account.id, card_id: card.id, pipeline_id: pipeline.id, event_type: 'won',
                                     status: :accepted, value_cents: value_cents, currency: 'BRL', event_id: SecureRandom.uuid,
                                     sent_at: Time.current)
  end

  def conversation_from_campaign
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511999990000')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    touch = { 'source_id' => 'ad-1', 'source' => 'meta_ctwa', 'headline' => 'Promo', 'touched_at' => 1.day.ago.iso8601 }
    conversation.update!(additional_attributes: { 'campaign' => touch, 'campaign_touches' => [touch], 'campaign_source_ids' => ['ad-1'] })
    conversation
  end

  def won_card(pipeline_and_stage, conversation, value_cents)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: "Ganho #{pipeline.name}", inbox: inbox,
                                     contact: conversation.contact, primary_conversation: conversation, value_cents: value_cents,
                                     currency: 'BRL')
    card.update!(status: :won)
    card
  end
end
