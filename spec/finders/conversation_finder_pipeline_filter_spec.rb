require 'rails_helper'

# Filtro "Funil" na lista de conversas (multifunil #1150): o parâmetro crm_pipeline_id restringe a lista e as contagens
# das abas, sempre por cima da regra de caixa e do acesso por funil.
RSpec.describe ConversationFinder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }

  let!(:minha_vendas) { conversation(assignee: agent).tap { |conversa| card(conversa, vendas) } }
  let!(:livre_vendas) { conversation.tap { |conversa| card(conversa, vendas) } }
  let!(:livre_sinistro) { conversation.tap { |conversa| card(conversa, sinistro) } }
  let!(:triagem) { conversation }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [vendas, sinistro].each { |(pipeline, _stage)| Crm::PipelineInbox.create!(account: account, inbox: inbox, pipeline: pipeline) }
    Current.account = account
  end

  def conversation(assignee: nil)
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: assignee)
  end

  def card(conversa, (pipeline, stage))
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: pipeline.name, inbox: inbox, contact: conversa.contact,
                              primary_conversation: conversa)
  end

  def perform(user, **params)
    described_class.new(user, ActionController::Parameters.new({ assignee_type: 'all' }.merge(params))).perform
  end

  it 'filtra a lista e as contagens das abas pelo funil' do
    result = perform(agent, crm_pipeline_id: vendas.first.id.to_s)

    expect(result[:conversations]).to contain_exactly(minha_vendas, livre_vendas)
    expect(result[:count]).to eq(mine_count: 1, assigned_count: 1, unassigned_count: 1, all_count: 2)
  end

  it '"none" traz só a triagem (sem card)' do
    expect(perform(agent, crm_pipeline_id: 'none')[:conversations]).to contain_exactly(triagem)
  end

  it 'sem o parâmetro a lista segue como antes' do
    expect(perform(agent)[:conversations]).to contain_exactly(minha_vendas, livre_vendas, livre_sinistro, triagem)
  end

  context 'with acesso por funil só em Vendas' do
    before do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    end

    it 'filtrar pelo funil que ela não tem não mostra nada nem conta nada' do
      result = perform(agent, crm_pipeline_id: sinistro.first.id.to_s)

      expect(result[:conversations]).to be_empty
      expect(result[:count][:all_count]).to eq(0)
    end

    it '"Sem assunto" não fura o acesso: sem triagem, nada' do
      expect(perform(agent, crm_pipeline_id: 'none')[:conversations]).to be_empty
    end

    it 'o funil dela continua filtrando' do
      expect(perform(agent, crm_pipeline_id: vendas.first.id.to_s)[:conversations]).to contain_exactly(minha_vendas, livre_vendas)
    end
  end
end
