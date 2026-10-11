require 'rails_helper'

# negocio.* lê o card só pelo escopo do CRM quando há uma pessoa (acesso por funil, #1148).
RSpec.describe TemplateFields::DealResolver do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:owner) { create(:user, account: account, role: :agent, name: 'Juliana Melo').tap { |user| user.update!(display_name: nil) } }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Seguro auto — Ana', inbox: inbox, contact: contact,
                              owner: owner, value_cents: 125_000)
  end
  let(:card_sinistro) do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', inbox: inbox, contact: contact, owner: owner)
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  it 'reads the deal fields of the card' do
    resolver = described_class.new(card)

    expect(resolver.keys.index_with { |key| resolver.value(key) }).to eq(
      'negocio.titulo' => 'Seguro auto — Ana', 'negocio.funil' => 'Vendas', 'negocio.etapa' => vendas.last.name,
      'negocio.valor' => 'R$ 1.250,00', 'negocio.responsavel' => 'Juliana Melo'
    )
  end

  it 'leaves a card without value or owner without them' do
    card.update!(value_cents: 0, owner: nil)

    expect(described_class.new(card).value('negocio.valor')).to be_nil
    expect(described_class.new(card).value('negocio.responsavel')).to be_nil
  end

  describe '.visible_card' do
    it 'finds the card the person sees' do
      expect(described_class.visible_card(account: account, user: agent, card_id: card.id)).to eq(card)
      expect(described_class.visible_card(account: account, user: admin, card_id: card_sinistro.id)).to eq(card_sinistro)
    end

    it 'does not read a card of a funnel the person does not have' do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)

      expect(described_class.visible_card(account: account, user: agent, card_id: card_sinistro.id)).to be_nil
      expect(described_class.visible_card(account: account, user: agent, card_id: card.id)).to eq(card)
    end

    it 'does not read a card of another account' do
      expect(described_class.visible_card(account: create(:account), user: admin, card_id: card.id)).to be_nil
    end
  end
end
