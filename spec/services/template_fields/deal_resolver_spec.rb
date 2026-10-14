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
      'negocio.valor' => 'R$ 1.250,00', 'negocio.responsavel' => 'Juliana Melo', 'negocio.vencimento' => nil
    )
  end

  # #1518: 02:00 UTC on the 21st is still the 20th in São Paulo (the default) and already the 21st in Tokyo.
  it 'reads the due date in the account time zone' do
    card.update!(expected_close_at: Time.utc(2026, 10, 21, 2, 0))
    expect(described_class.new(card).value('negocio.vencimento')).to eq('20/10/2026')

    account.update!(reporting_timezone: 'Asia/Tokyo')
    expect(described_class.new(card.reload).value('negocio.vencimento')).to eq('21/10/2026')
  end

  it 'leaves a card without value or owner without them' do
    card.update!(value_cents: 0, owner: nil)

    expect(described_class.new(card).value('negocio.valor')).to be_nil
    expect(described_class.new(card).value('negocio.responsavel')).to be_nil
  end
end
