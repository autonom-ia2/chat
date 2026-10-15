require 'rails_helper'

# Filtro "Funil" da lista de conversas (multifunil #1150). A lista (PipelineFilter, SQL) e o tempo real (PipelineIds, na
# conversa que chega pelo websocket) seguem a regra do acesso por funil: card aberto manda, ganho/perdido vale sem card
# aberto, arquivado/resolvido/cancelado não contam. "Sem assunto" é a conversa sem card que a prenda.
RSpec.describe Crm::Conversations::PipelineFilter do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:caixa_sem_funil) { create_crm_inbox(account: account, name: 'Sem funil', members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }

  # Uma conversa por caso; o nome diz o que ela tem.
  let!(:conversas) do
    {
      vendas: conversation.tap { |conversa| card(conversa, vendas) },
      sinistro: conversation.tap { |conversa| card(conversa, sinistro) },
      vinculada: conversation.tap { |conversa| card(conversa, sinistro, linked: true) },
      aberto_manda: conversation.tap do |conversa|
        card(conversa, vendas)
        card(conversa, sinistro, :won)
      end,
      ganha: conversation.tap { |conversa| card(conversa, sinistro, :won) },
      resolvida: conversation.tap { |conversa| card(conversa, vendas, :resolved) },
      arquivada: conversation.tap { |conversa| card(conversa, vendas, :archived) },
      triagem: conversation,
      caixa_sem_funil: conversation(caixa_sem_funil)
    }
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [vendas, sinistro].each { |(pipeline, _stage)| Crm::PipelineInbox.create!(account: account, inbox: inbox, pipeline: pipeline) }
  end

  def conversation(target_inbox = inbox)
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: target_inbox, contact: contact)
  end

  def card(conversa, (pipeline, stage), status = :open, linked: false)
    created = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: pipeline.name, inbox: conversa.inbox,
                                        contact: conversa.contact, primary_conversation: linked ? nil : conversa)
    Crm::CardConversation.create!(account: account, card: created, conversation: conversa) if linked
    created.update_columns(status: Crm::Card.statuses[status]) unless status == :open # rubocop:disable Rails/SkipsModelValidations
    created
  end

  def filtered(value, user: admin)
    described_class.new(user: user, account: account, value: value).apply(account.conversations).to_a
  end

  def all_conversations
    conversas.values
  end

  it 'sem valor não filtra' do
    expect(filtered(nil)).to match_array(all_conversations)
    expect(filtered('')).to match_array(all_conversations)
  end

  it 'funil: card principal, vinculado, aberto que manda e ganho sem card aberto' do
    expect(filtered(vendas.first.id)).to contain_exactly(conversas[:vendas], conversas[:aberto_manda])
    expect(filtered(sinistro.first.id.to_s)).to contain_exactly(conversas[:sinistro], conversas[:vinculada], conversas[:ganha])
  end

  it 'Sem assunto: sem card, card resolvido ou arquivado e caixa sem funil ligado' do
    expect(filtered('none')).to contain_exactly(conversas[:resolvida], conversas[:arquivada], conversas[:triagem],
                                                conversas[:caixa_sem_funil])
  end

  it 'valor que não é funil desta conta responde lista vazia' do
    outra_conta = create(:account)
    (alheio, _stage) = create_crm_pipeline(account: outra_conta, user: create(:user, account: outra_conta), name: 'Alheio')

    expect(filtered(alheio.id)).to be_empty
    expect(filtered('abc')).to be_empty
    expect(filtered("#{vendas.first.id} OR 1=1")).to be_empty
    expect(filtered(0)).to be_empty
  end

  describe 'acesso por funil (Crm::Access::VisiblePipelines)' do
    before do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: true)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    end

    it 'funil que a pessoa não enxerga responde vazio, igual a funil que não existe (sem vazamento)' do
      expect(filtered(sinistro.first.id, user: agent)).to be_empty
      expect(filtered(sinistro.first.id, user: agent)).to eq(filtered(Crm::Pipeline.maximum(:id) + 1_000, user: agent))
    end

    it 'o funil dela filtra normalmente' do
      expect(filtered(vendas.first.id, user: agent)).to contain_exactly(conversas[:vendas], conversas[:aberto_manda])
    end

    it 'na lista real o filtro só restringe o que o acesso já liberou' do
      scope = Crm::Access::ConversationScope.new(user: agent, account: account)
      seen = described_class.new(user: agent, account: account, value: 'none').apply(scope.apply(account.conversations))

      expect(seen).to contain_exactly(conversas[:resolvida], conversas[:arquivada], conversas[:triagem], conversas[:caixa_sem_funil])
      expect(seen).not_to include(conversas[:ganha])
    end
  end

  describe 'paridade' do
    let(:ids) { Crm::Conversations::PipelineIds.for(account.conversations.to_a) }

    it 'o tempo real (PipelineIds) concorda com a lista (PipelineFilter) em cada conversa e funil' do
      [vendas, sinistro].each do |(pipeline, _stage)|
        by_list = filtered(pipeline.id).map(&:id)
        by_realtime = ids.select { |_id, pipelines| pipelines.include?(pipeline.id) }.keys

        expect(by_realtime).to match_array(by_list)
      end
      expect(ids.select { |_id, pipelines| pipelines.empty? }.keys).to match_array(filtered('none').map(&:id))
    end

    it 'concorda com o ConversationScope: quem só tem o funil vê o mesmo que o filtro desse funil mostra' do
      outro = create_crm_agent(account: account, name: 'Só Sinistro').first
      inbox.add_members([outro.id])
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: outro, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: sinistro.first)
      by_scope = Crm::Access::ConversationScope.new(user: outro, account: account).apply(account.conversations.where(inbox: inbox))

      expect(by_scope).to match_array(filtered(sinistro.first.id).select { |conversa| conversa.inbox_id == inbox.id })
    end

    it 'concorda com o ConversationScope na triagem: só triagem vê o mesmo que "Sem assunto" mostra na caixa' do
      triagem = create_crm_agent(account: account, name: 'Triagem').first
      inbox.add_members([triagem.id])
      Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: triagem, all_pipelines: false, triage: true)
      by_scope = Crm::Access::ConversationScope.new(user: triagem, account: account).apply(account.conversations.where(inbox: inbox))

      expect(by_scope).to match_array(filtered('none').select { |conversa| conversa.inbox_id == inbox.id })
    end
  end

  describe Crm::Conversations::PipelineIds do
    it 'traz toda conversa pedida, com os funis pela regra do card aberto' do
      ids = described_class.for([conversas[:vendas], conversas[:vinculada], conversas[:aberto_manda], conversas[:ganha],
                                 conversas[:resolvida], conversas[:triagem]])

      expect(ids).to eq(conversas[:vendas].id => [vendas.first.id], conversas[:vinculada].id => [sinistro.first.id],
                        conversas[:aberto_manda].id => [vendas.first.id], conversas[:ganha].id => [sinistro.first.id],
                        conversas[:resolvida].id => [], conversas[:triagem].id => [])
    end

    it 'card que não é da conta da conversa não conta' do
      intruso = card(conversas[:triagem], vendas)
      intruso.update_columns(account_id: create(:account).id) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.for([conversas[:triagem]])).to eq(conversas[:triagem].id => [])
    end

    it 'lista vazia não consulta' do
      expect(described_class.for([])).to eq({})
    end
  end
end
