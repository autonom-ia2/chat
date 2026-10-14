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
                              owner: owner, value_cents: 125_000, expected_close_at: Time.utc(2026, 10, 20, 15))
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  it 'reads the deal fields of the card' do
    resolver = described_class.new(card)

    expect(resolver.keys.index_with { |key| resolver.value(key) }).to eq(
      'negocio.titulo' => 'Seguro auto — Ana', 'negocio.funil' => 'Vendas', 'negocio.etapa' => vendas.last.name,
      'negocio.valor' => 'R$ 1.250,00', 'negocio.responsavel' => 'Juliana Melo', 'negocio.prazo' => '20/10/2026'
    )
  end

  it 'leaves a card without value, owner or deadline without them' do
    card.update!(value_cents: 0, owner: nil, expected_close_at: nil)

    expect(described_class.new(card).value('negocio.valor')).to be_nil
    expect(described_class.new(card).value('negocio.responsavel')).to be_nil
    expect(described_class.new(card).value('negocio.prazo')).to be_nil
  end

  it 'reads the deadline as the calendar day the CRM saved, even in a negative account time zone' do
    card.update!(expected_close_at: Time.utc(2026, 10, 20)) # a tela grava "2026-10-20" como 00:00 UTC

    with_modified_env(CRM_DEFAULT_TIMEZONE: 'America/Sao_Paulo') do
      expect(described_class.new(card).value('negocio.prazo')).to eq('20/10/2026')
    end
  end

  it 'formats the value by its cents and currency, never as a float' do
    card.update!(value_cents: 1_999_999_999, currency: 'USD')

    expect(described_class.new(card).value('negocio.valor')).to eq('USD 19.999.999,99')
  end
end
