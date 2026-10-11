require 'rails_helper'

# Matriz do acesso por funil (#1148): agente × funil × todas/só as suas × triagem × atribuído/participante, e o que a
# pessoa NÃO pode ver. A mesma regra serve a lista (#apply) e o link (#allows?).
RSpec.describe Crm::Access::ConversationScope do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:other) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, other]) }
  let(:outra_caixa) { create_crm_inbox(account: account, name: 'Outra', members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }

  let!(:conversa_vendas) { conversation_with_card(vendas) }
  let!(:conversa_sinistro) { conversation_with_card(sinistro) }
  let!(:conversa_triagem) { conversation(inbox) }
  let!(:conversa_outra_caixa) { conversation(outra_caixa) }

  def conversation(target_inbox, assignee: nil)
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: target_inbox, contact: contact, assignee: assignee)
  end

  def conversation_with_card((pipeline, stage), linked: false)
    conversa = conversation(inbox)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversa.contact, title: pipeline.name,
                                     primary_conversation: (linked ? nil : conversa))
    Crm::CardConversation.create!(account: account, card: card, conversation: conversa) if linked
    conversa
  end

  def access(user = agent, target_inbox = inbox, pipelines: nil, triage: true, only_own: false)
    record = Crm::InboxAgentAccess.create!(account: account, inbox: target_inbox, user: user, all_pipelines: pipelines.nil?,
                                           triage: triage, only_own: only_own)
    Array(pipelines).each { |(pipeline, _stage)| record.agent_pipelines.create!(account: account, pipeline: pipeline) }
    record
  end

  def visible(user = agent)
    described_class.new(user: user, account: account).apply(account.conversations).to_a
  end

  def allows?(conversa, user = agent)
    described_class.new(user: user, account: account).allows?(conversa)
  end

  it 'sem acesso configurado nada muda (R5)' do
    expect(visible).to contain_exactly(conversa_vendas, conversa_sinistro, conversa_triagem, conversa_outra_caixa)
    expect(allows?(conversa_sinistro)).to be(true)
  end

  it 'linha que libera tudo é igual a não ter linha' do
    access

    expect(visible).to contain_exactly(conversa_vendas, conversa_sinistro, conversa_triagem, conversa_outra_caixa)
  end

  it 'só o funil Vendas e sem triagem: não vê Sinistro nem triagem; outra caixa segue livre' do
    access(pipelines: [vendas], triage: false)

    expect(visible).to contain_exactly(conversa_vendas, conversa_outra_caixa)
    expect(allows?(conversa_sinistro)).to be(false)
    expect(allows?(conversa_triagem)).to be(false)
    expect(allows?(conversa_vendas)).to be(true)
  end

  it 'funil Vendas com triagem: vê Vendas e a conversa sem card (R3)' do
    access(pipelines: [vendas], triage: true)

    expect(visible).to contain_exactly(conversa_vendas, conversa_triagem, conversa_outra_caixa)
  end

  it 'todos os funis sem triagem: vê toda conversa com card, nenhuma sem card' do
    access(triage: false)

    expect(visible).to contain_exactly(conversa_vendas, conversa_sinistro, conversa_outra_caixa)
  end

  it 'nenhum funil e sem triagem: só o que é dela' do
    access(pipelines: [], triage: false)

    expect(visible).to contain_exactly(conversa_outra_caixa)
  end

  it 'conversa com cards de dois funis: um funil dela já libera' do
    card_sinistro = account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, contact: conversa_vendas.contact,
                                              title: 'Sinistro também')
    Crm::CardConversation.create!(account: account, card: card_sinistro, conversation: conversa_vendas)
    access(pipelines: [sinistro], triage: false)

    expect(allows?(conversa_vendas)).to be(true)
  end

  it 'vínculo em crm_card_conversations também conta como card do funil' do
    vinculada = conversation_with_card(sinistro, linked: true)
    access(pipelines: [sinistro], triage: false)

    expect(allows?(vinculada)).to be(true)
    expect(visible).to include(vinculada)
  end

  it 'card arquivado não conta: a conversa volta para a triagem' do
    conversa = conversation_with_card(sinistro)
    account.crm_cards.find_by(conversation_id: conversa.id).update!(status: :archived)
    access(pipelines: [vendas], triage: true)

    expect(allows?(conversa)).to be(true)
  end

  it 'card encerrado (ganho) continua liberando pelo funil (R2)' do
    account.crm_cards.find_by(conversation_id: conversa_sinistro.id).update!(status: :won)
    access(pipelines: [sinistro], triage: false)

    expect(allows?(conversa_sinistro)).to be(true)
    expect(allows?(conversa_vendas)).to be(false)
  end

  describe 'atribuído e participante sempre veem (decisão de 11/10)' do
    before { access(pipelines: [vendas], triage: false) }

    it 'conversa de outro funil atribuída a ela' do
      conversa_sinistro.update!(assignee: agent)

      expect(allows?(conversa_sinistro)).to be(true)
      expect(visible).to include(conversa_sinistro)
    end

    it 'conversa de outro funil em que ela participa' do
      ConversationParticipant.create!(account: account, conversation: conversa_triagem, user: agent)

      expect(allows?(conversa_triagem)).to be(true)
      expect(visible).to include(conversa_triagem)
    end
  end

  describe 'Só as suas (R4)' do
    before { access(only_own: true) }

    it 'não vê nada da caixa que não seja dela' do
      expect(visible).to contain_exactly(conversa_outra_caixa)
      expect(allows?(conversa_vendas)).to be(false)
    end

    it 'vê a atribuída e a em que participa' do
      conversa_vendas.update!(assignee: agent)
      ConversationParticipant.create!(account: account, conversation: conversa_sinistro, user: agent)

      expect(visible).to contain_exactly(conversa_vendas, conversa_sinistro, conversa_outra_caixa)
    end
  end

  it 'a restrição de uma pessoa não muda o que a outra vê' do
    access(agent, pipelines: [vendas], triage: false)

    expect(visible(other)).to include(conversa_sinistro, conversa_triagem)
  end

  it 'administrador vê tudo, mesmo com linha de acesso' do
    access(admin, pipelines: [], triage: false)

    expect(visible(admin)).to include(conversa_vendas, conversa_sinistro, conversa_triagem)
    expect(allows?(conversa_sinistro, admin)).to be(true)
  end

  it 'linha de outra conta não vaza para esta' do
    outra_conta = create(:account)
    AccountUser.create!(account: outra_conta, user: agent, role: :agent)
    outra_inbox = create_crm_inbox(account: outra_conta, members: [agent])
    Crm::InboxAgentAccess.create!(account: outra_conta, inbox: outra_inbox, user: agent, all_pipelines: false, triage: false)

    expect(visible).to contain_exactly(conversa_vendas, conversa_sinistro, conversa_triagem, conversa_outra_caixa)
  end

  describe 'card encerrado (decisão de 11/10)' do
    it 'perdido continua prendendo a conversa ao funil dele' do
      account.crm_cards.find_by(conversation_id: conversa_sinistro.id).update!(status: :lost)
      access(pipelines: [vendas], triage: true)

      expect(allows?(conversa_sinistro)).to be(false)
    end

    %i[resolved cancelled].each do |status|
      it "#{status} solta a conversa para a triagem" do
        atendimento = create_crm_pipeline(account: account, user: admin, name: 'Suporte')
        atendimento.first.update!(counts_as_sale: false)
        conversa = conversation_with_card(atendimento)
        account.crm_cards.find_by(conversation_id: conversa.id).update!(status: status)
        access(pipelines: [vendas], triage: true)

        expect(allows?(conversa)).to be(true)
        expect(visible).to include(conversa)
      end
    end
  end
end
