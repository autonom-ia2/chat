require 'rails_helper'

# Filtro do link `no_funil=1` (Números F5, #1999): só as conversas de cliente com card num funil que a pessoa vê no
# Números (Crm::Access::VisiblePipelines#apply_to_reports), pelo card principal ou pelo vínculo. É o escopo do "a IA está
# esperando" da visão "Equipe": a caixa aberta pelo link mostra o mesmo conjunto que o número conta.
RSpec.describe ConversationFinder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }

  let!(:principal_vendas) { conversation.tap { |conversa| card(conversa, vendas) } }
  let!(:vinculada_vendas) { conversation.tap { |conversa| vincular(conversa, card(conversa, vendas, principal: false)) } }
  let!(:de_suporte) { conversation.tap { |conversa| card(conversa, suporte) } }
  let!(:sem_card) { conversation }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [vendas, suporte].each { |(pipeline, _stage)| Crm::PipelineInbox.create!(account: account, inbox: inbox, pipeline: pipeline) }
    Current.account = account
  end

  def conversation
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contact)
  end

  def card(conversa, (pipeline, stage), principal: true)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: pipeline.name, inbox: inbox, contact: conversa.contact,
                              primary_conversation: principal ? conversa : nil)
  end

  def vincular(conversa, card)
    Crm::CardConversation.create!(account: account, card: card, conversation: conversa)
  end

  def perform(user, **params)
    described_class.new(user, ActionController::Parameters.new({ assignee_type: 'all' }.merge(params))).perform
  end

  it 'traz só as de cliente num funil, pelo card principal ou pelo vínculo, e as abas contam o mesmo' do
    result = perform(admin, no_funil: '1')

    expect(result[:conversations]).to contain_exactly(principal_vendas, vinculada_vendas, de_suporte)
    expect(result[:count][:all_count]).to eq(result[:conversations].size)
  end

  it 'sem o parâmetro a lista segue como antes' do
    expect(perform(admin)[:conversations]).to include(sem_card)
  end

  context 'with acesso aos relatórios só de Vendas' do
    before do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: true)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    end

    it 'a conversa de um funil que ela não vê no Números não entra' do
      conversas = perform(agent, no_funil: '1')[:conversations]

      expect(conversas).to include(principal_vendas, vinculada_vendas)
      expect(conversas).not_to include(de_suporte, sem_card)
    end
  end
end
