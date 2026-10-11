require 'rails_helper'

# negocio.* lê o card já resolvido por quem chama.
RSpec.describe TemplateFields::DealResolver do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:owner) { create(:user, account: account, role: :agent, name: 'Juliana Melo').tap { |user| user.update!(display_name: nil) } }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Seguro auto — Ana', inbox: inbox, contact: contact,
                              owner: owner, value_cents: 125_000)
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
end
