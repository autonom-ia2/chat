require 'rails_helper'

# #1385. A lista de nomes que o modelo recebe para "o cliente pediu fulano" vinha da conversa PRIMÁRIA do card, mas o
# executor passa a conversa em que o cliente está falando agora (#553). Com o cliente em outra caixa, o modelo só via a
# equipe da caixa antiga, e o nome que ele sugeria era descartado pelo seletor.
RSpec.describe Crm::Ai::Evaluator do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:ana) { create_crm_agent(account: account, name: 'Ana do site').first }
  let(:leo) { create_crm_agent(account: account, name: 'Léo do WhatsApp').first }
  let(:caixa_site) { create_crm_inbox(account: account, name: 'Site', members: [ana]) }
  let(:caixa_whatsapp) { create_crm_inbox(account: account, name: 'WhatsApp', members: [leo]) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: caixa_site, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: caixa_whatsapp, contact: contact) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  def card_com(primaria:, tambem: [])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: primaria.inbox, contact: contact,
                                     primary_conversation: primaria, title: 'Lead')
    ([primaria] + tambem).each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  def nomes_para_o_modelo(card, selector_mode: 'round_robin')
    evaluator = described_class.new(card: card)
    allow(evaluator).to receive(:handoff_config).and_return({ enabled: true, selector_mode: selector_mode })
    evaluator.send(:eligible_agent_names)
  end

  # #1593: com "pedido pelo nome", os agentes de IA que podem receber a conversa entram com o rótulo; o modelo decide.
  describe 'agentes de IA' do
    let(:lia) { criar_agente_ia(account, 'Lia') }

    before do
      ligar_agentes_ia!(account)
      agente_na_caixa!(lia, caixa_whatsapp)
    end

    it 'pedido pelo nome ligado: a Lia entra com o rótulo de agente' do
      nomes = nomes_para_o_modelo(card_com(primaria: conversa_viva), selector_mode: 'direct')

      expect(nomes).to contain_exactly('Léo do WhatsApp', 'Lia (agente de IA)')
    end

    it 'rodízio: só pessoas (a IA não entra na vez)' do
      nomes = nomes_para_o_modelo(card_com(primaria: conversa_viva))

      expect(nomes).to contain_exactly('Léo do WhatsApp')
    end
  end

  it 'oferece a equipe da caixa em que o cliente está falando, e não a da conversa primária' do
    # Arrange — a conversa do site foi resolvida; o cliente voltou pelo WhatsApp
    conversa_antiga.update!(status: :resolved)
    card = card_com(primaria: conversa_antiga, tambem: [conversa_viva])

    # Act
    nomes = nomes_para_o_modelo(card)

    # Assert
    expect(nomes).to contain_exactly('Léo do WhatsApp')
  end

  it 'card sem conversa nenhuma: lista vazia, sem quebrar a avaliação' do
    # Arrange
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Lead sem conversa')

    # Act
    nomes = nomes_para_o_modelo(card)

    # Assert
    expect(nomes).to eq([])
  end

  it 'com uma conversa só, continua sendo a equipe dela' do
    # Arrange
    card = card_com(primaria: conversa_antiga)

    # Act
    nomes = nomes_para_o_modelo(card)

    # Assert
    expect(nomes).to contain_exactly('Ana do site')
  end
end
