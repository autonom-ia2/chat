require 'rails_helper'

# Texto do resumo e do alerta (#1100, F4b): idioma da conta, linhas que somem sem dado e modelo sempre em pt_BR.
RSpec.describe Crm::MetaAds::WhatsappReport::MessageBuilder do
  let(:digest) do
    { date: Date.new(2026, 10, 6), currency: 'BRL', spend: 1234.5, conversations: 1, cost_per_conversation: 1234.5, quotes: 0, sales: 0,
      sales_value: 0.0, best_ad: nil,
      action: { id: 7, kind: 'stalled_quotes', variant: nil, source: 'rule', facts: { count: 1, days: 3, value: 450.0, ad_name: nil } } }
  end

  it 'sem venda mostra "Vendas: 0", sem melhor anúncio a linha sai e o que fazer hoje é a regra' do
    account = create(:account, locale: 'pt_BR')
    text = described_class.new(account).summary_text(digest)

    expect(text.lines.map(&:chomp)).to eq([
                                            'Anúncios da Meta — ontem, 06/10',
                                            'Investido: R$ 1.234,50',
                                            'Conversas: 1 (R$ 1.234,50 por conversa)',
                                            'Propostas: 0 · Vendas: 0',
                                            'O que fazer hoje: Retome a proposta parada há mais de 3 dias (R$ 450).',
                                            "Ver o painel: /app/accounts/#{account.id}/campaigns/meta-ads?aba=resultado"
                                          ])
  end

  it 'conta em inglês recebe o texto em inglês; o modelo do Oficial continua em pt_BR' do
    builder = described_class.new(create(:account, locale: 'en'))
    tracking = { kind: 'fix_tracking', source: 'rule', facts: { conversations: 5, unknown: 4, identified_pct: 0.2 } }
    rule = digest.merge(currency: 'USD', action: tracking)

    expect(builder.summary_text(rule).lines.first(2).map(&:chomp)).to eq(['Meta ads — yesterday, 10/06', 'Spent: US$ 1,234.50'])
    expect(builder.summary_parameters(rule, test: true).sole[:parameters].pluck(:text))
      .to eq(['06/10 [Teste]', 'US$ 1.234,50', '1 conversa, 0 propostas e 0 vendas',
              'Confira de qual anúncio vieram 4 conversas sem anúncio identificado.'])
  end

  it 'com o texto da IA, o que fazer hoje é o título e o como fazer, numa linha no modelo' do
    builder = described_class.new(create(:account, locale: 'pt_BR'))
    text = { source: 'ai', headline: 'Retome a proposta de R$ 450,00.', body: "Comece hoje.\nUma mensagem curta basta." }
    ai = digest.merge(action: digest[:action].merge(text))

    expect(builder.summary_text(ai)).to include('O que fazer hoje: Retome a proposta de R$ 450,00. Comece hoje.')
    expect(builder.summary_parameters(ai).sole[:parameters].last[:text])
      .to eq('Retome a proposta de R$ 450,00. Comece hoje. Uma mensagem curta basta.')
  end

  it 'conta em inglês: o modelo pt_BR fica com a regra, não com o texto da IA em inglês' do
    builder = described_class.new(create(:account, locale: 'en'))
    ai = digest.merge(action: digest[:action].merge(source: 'ai', headline: 'Follow up the quote.', body: nil))

    expect(builder.summary_text(ai)).to include('Follow up the quote.')
    expect(builder.summary_parameters(ai).sole[:parameters].last[:text]).to eq('Retome a proposta parada há mais de 3 dias (R$ 450).')
  end

  it 'no pior caso (texto da IA no limite, valores grandes) o corpo do modelo cabe nos 1.024 caracteres da Meta' do
    builder = described_class.new(create(:account, locale: 'pt_BR'))
    big = digest.merge(spend: 9_999_999.99, conversations: 99_999, quotes: 99_999, sales: 99_999,
                       action: { source: 'ai', headline: 'a' * 120, body: 'b' * 400 })
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

  describe 'os tipos do consultor pela regra (F5), com os valores formatados como na tela' do
    def rule_line(kind, facts, locale: 'pt_BR', variant: nil, currency: 'BRL')
      action = { id: 1, kind: kind, variant: variant, source: 'rule', facts: facts }
      text = described_class.new(create(:account, locale: locale)).summary_text(digest.merge(currency: currency, action: action))
      text.lines.map(&:chomp).find { |line| line.start_with?('O que fazer hoje:', 'What to do today:') }
    end

    it 'atendimento lento: mediana em duração, sem resposta e o alvo; sem mediana, só a falta de resposta' do
      facts = { 'median_seconds' => 1500, 'answered' => 12, 'unanswered' => 2, 'target_seconds' => 300, 'window_days' => 30 }

      expect(rule_line('slow_response', facts)).to eq(
        'O que fazer hoje: Responda mais rápido às conversas de anúncio: nos últimos 30 dias, metade esperou mais de 25 min ' \
        'pela primeira resposta. Sem resposta: 2. Responder em até 5 min ajuda a vender.'
      )
      expect(rule_line('slow_response', facts.merge('median_seconds' => nil, 'answered' => 0), locale: 'en')).to eq(
        'What to do today: Reply to ad conversations: in the last 30 days, none got a reply. No reply: 2. ' \
        'Replying within 5 min helps you sell.'
      )
    end

    # A regra também falha com a mediana dentro da meta quando 20% ou mais ficaram sem resposta: o texto não pode
    # acusar demora que não há.
    it 'atendimento dentro da meta mas com muitas sem resposta: fala só das sem resposta' do
      facts = { 'median_seconds' => 120, 'answered' => 12, 'unanswered' => 4, 'target_seconds' => 300, 'window_days' => 30 }

      expect(rule_line('slow_response', facts)).to eq(
        'O que fazer hoje: Responda as conversas de anúncio: nos últimos 30 dias, parte delas ficou sem resposta. Sem resposta: 4. ' \
        'Responder em até 5 min ajuda a vender.'
      )
    end

    it 'revisar anúncio, pela variante' do
      facts = { ad_name: 'Promo 10/10', conversations: 25, sales: 0, spend: 1234.5, cost_per_sale: nil, target_cost_per_sale: 170 }

      expect(rule_line('review_ad', facts, variant: 'no_sales')).to eq(
        'O que fazer hoje: Revise o anúncio Promo 10/10: trouxe 25 conversas e nenhuma venda, com R$ 1.234,50 investidos. ' \
        'Olhe a imagem, o texto e o que as pessoas perguntam antes de desligar.'
      )
      expect(rule_line('review_ad', facts.merge(sales: 3, cost_per_sale: 260), variant: 'above_average', locale: 'en', currency: 'USD'))
        .to eq('What to do today: Review the ad Promo 10/10: each sale cost US$ 260, above the US$ 170 average of the ads that sell.')
    end

    it 'trocar a imagem ou o texto, pela variante' do
      facts = { ad_name: 'Promo', ctr_drop_pct: 0.33, frequency_7d: 4.6, window_days: 7 }

      expect(rule_line('refresh_creative', facts.merge(frequency_7d: nil), variant: 'ctr'))
        .to eq('O que fazer hoje: Troque a imagem ou o texto de Promo: as pessoas clicam 33% menos do que nas semanas anteriores.')
      expect(rule_line('refresh_creative', facts.merge(ctr_drop_pct: nil), variant: 'frequency')).to eq(
        'O que fazer hoje: Troque a imagem ou o texto de Promo: cada pessoa já viu o anúncio 4,6 vezes nos últimos 7 dias.'
      )
      expect(rule_line('refresh_creative', facts, variant: 'both', locale: 'en')).to eq(
        'What to do today: Change the image or text of Promo: people click 33% less than in the previous weeks, and each person ' \
        'has already seen the ad 4.6 times in the last 7 days.'
      )
    end

    it 'aumentar o orçamento e a pressão do leilão' do
      scale = { ad_name: 'Promo', cost_per_sale: 120, target_cost_per_sale: 150, frequency_7d: 2.1, max_increase_pct: 0.2, weeks: 2,
                cooldown_days: 3 }
      auction = { cpm_change_pct: 0.4, cpm_recent: 28, cpm_baseline: 20, window_days: 7 }

      expect(rule_line('scale_ad', scale)).to eq(
        'O que fazer hoje: Promo vende abaixo da média de R$ 150 há 2 semanas. Aumente o valor por dia do anúncio em até 20% ' \
        'no Gerenciador da Meta, e só de novo daqui a 3 dias.'
      )
      expect(rule_line('auction_pressure', auction)).to eq(
        'O que fazer hoje: Aparecer para mil pessoas ficou 40% mais caro nos últimos 7 dias, e os cliques continuam iguais: ' \
        'é a concorrência, não o seu anúncio. Não troque o anúncio por isso.'
      )
    end

    it 'os fillers continuam com o texto fixo' do
      expect(rule_line('wait', { ad_name: 'Promo', missing_conversations: 12 }))
        .to eq('O que fazer hoje: Nada a corrigir. Siga com os anúncios como estão.')
      expect(rule_line('no_data', {}, locale: 'en')).to eq('What to do today: No ad spend or conversation in the last 30 days yet.')
    end

    it 'o modelo do Oficial recebe a regra em pt_BR numa linha só' do
      action = { id: 1, kind: 'auction_pressure', source: 'rule', facts: { cpm_change_pct: 0.4, window_days: 7 } }
      builder = described_class.new(create(:account, locale: 'en'))

      expect(builder.summary_parameters(digest.merge(action: action)).sole[:parameters].last[:text])
        .to start_with('Aparecer para mil pessoas ficou 40% mais caro nos últimos 7 dias')
    end
  end
end
