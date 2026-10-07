require 'rails_helper'

# Texto do resumo e do alerta (#1100, F4b): idioma da conta, linhas que somem sem dado e modelo sempre em pt_BR.
RSpec.describe Crm::MetaAds::WhatsappReport::MessageBuilder do
  let(:digest) do
    { date: Date.new(2026, 10, 6), currency: 'BRL', spend: 1234.5, conversations: 1, cost_per_conversation: 1234.5, quotes: 0, sales: 0,
      sales_value: 0.0, best_ad: nil, action: { kind: 'stalled_quotes', count: 1, days: 3, value: 450.0 } }
  end

  it 'sem venda mostra "Vendas: 0", sem melhor anúncio a linha sai e o que fazer hoje é a regra' do
    account = create(:account, locale: 'pt_BR')
    text = described_class.new(account).summary_text(digest)

    expect(text.lines.map(&:chomp)).to eq([
                                            'Anúncios da Meta — ontem, 06/10',
                                            'Investido: R$ 1.234,50',
                                            'Conversas: 1 (R$ 1.234,50 por conversa)',
                                            'Propostas: 0 · Vendas: 0',
                                            'O que fazer hoje: Retome a proposta parada há mais de 3 dias (R$ 450,00).',
                                            "Ver o painel: /app/accounts/#{account.id}/campaigns/meta-ads?aba=resultado"
                                          ])
  end

  it 'conta em inglês recebe o texto em inglês; o modelo do Oficial continua em pt_BR' do
    builder = described_class.new(create(:account, locale: 'en'))
    rule = digest.merge(currency: 'USD', action: { kind: 'fix_tracking', conversations: 5, unknown: 4 })

    expect(builder.summary_text(rule).lines.first(2).map(&:chomp)).to eq(['Meta ads — yesterday, 10/06', 'Spent: US$ 1,234.50'])
    expect(builder.summary_parameters(rule, test: true).sole[:parameters].pluck(:text))
      .to eq(['06/10 [Teste]', 'US$ 1.234,50', '1 conversa, 0 propostas e 0 vendas',
              'Confira de qual anúncio vieram 4 conversas sem anúncio identificado.'])
  end

  it 'com o texto da IA, o que fazer hoje é o título e o como fazer, numa linha no modelo' do
    builder = described_class.new(create(:account, locale: 'pt_BR'))
    ai = digest.merge(ai_action: { source: 'ai', headline: 'Retome a proposta de R$ 450,00.', body: "Comece hoje.\nUma mensagem curta basta." })

    expect(builder.summary_text(ai)).to include('O que fazer hoje: Retome a proposta de R$ 450,00. Comece hoje.')
    expect(builder.summary_parameters(ai).sole[:parameters].last[:text])
      .to eq('Retome a proposta de R$ 450,00. Comece hoje. Uma mensagem curta basta.')
  end

  it 'conta em inglês: o modelo pt_BR fica com a regra, não com o texto da IA em inglês' do
    builder = described_class.new(create(:account, locale: 'en'))
    ai = digest.merge(ai_action: { source: 'ai', headline: 'Follow up the quote.', body: nil })

    expect(builder.summary_text(ai)).to include('Follow up the quote.')
    expect(builder.summary_parameters(ai).sole[:parameters].last[:text]).to eq('Retome a proposta parada há mais de 3 dias (R$ 450,00).')
  end

  it 'no pior caso (texto da IA no limite, valores grandes) o corpo do modelo cabe nos 1.024 caracteres da Meta' do
    builder = described_class.new(create(:account, locale: 'pt_BR'))
    big = digest.merge(spend: 9_999_999.99, conversations: 99_999, quotes: 99_999, sales: 99_999,
                       ai_action: { source: 'ai', headline: 'a' * 120, body: 'b' * 400 })
    values = builder.summary_parameters(big, test: true).sole[:parameters].pluck(:text)
    body = I18n.t('meta_ads_whatsapp_report.templates.summary', locale: :pt_BR)
    values.each_with_index { |value, index| body = body.sub("{{#{index + 1}}}", value) }

    expect(body.length).to be <= 1024
  end

  it 'variável do modelo sai numa linha só: nome de anúncio com quebra de linha, tab ou espaços seguidos' do
    builder = described_class.new(create(:account, locale: 'pt_BR'))
    alert = { name: "Promo\noutubro\t\t  2026     final", spend: 35.0, currency: 'BRL' }

    expect(builder.alert_parameters(alert).sole[:parameters].pluck(:text)).to eq(['Promo outubro 2026 final', 'R$ 35,00'])
  end

  it 'o texto do modelo do resumo não começa nem termina com variável e tem 4 variáveis' do
    body = I18n.t('meta_ads_whatsapp_report.templates.summary', locale: :pt_BR)

    expect(body).not_to start_with('{{')
    expect(body).not_to end_with('}}')
    expect((1..4).map { |index| body.include?("{{#{index}}}") }).to all(be(true))
    expect(body).not_to include('{{5}}')
  end
end
