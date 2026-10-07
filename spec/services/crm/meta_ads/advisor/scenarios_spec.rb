require 'rails_helper'

# Bateria de cenários-gabarito do consultor de tráfego (#1110, F5, PRD CA-4.5; desenho em docs/crm/anuncios-meta-f5.md §6).
# É o GABARITO: cada cenário confere, inteiros, o mapa de status de todas as regras (as 4 de conta e as 4 de cada
# anúncio) e a lista exata de ações [kind, ad_id, status]. Quem implementa Facts/Rules/Decision faz a bateria passar e
# não muda este arquivo. Mudar o gabarito exige subir Advisor::Rules::RULES_VERSION, com o motivo no PR e o OK do
# orquestrador.
#
# Sem IA e sem rede: Facts → History → Rules → today → Decision, pelo ajudante advisor_evaluate (§6.1). As janelas
# (§6.2), com hoje = 07/10: recent7 30/09–06/10, baseline 09/09–29/09, weekA 23/09–29/09, weekB 16/09–22/09,
# cohort30 08/09–agora. A hora de cada exemplo vem do metadado `now:` (só a S20 muda).
RSpec.describe 'Consultor de tráfego: cenários-gabarito (CA-4.5)' do # rubocop:disable RSpec/DescribeClass -- a bateria cobre Facts, Rules e Decision juntos
  around do |example|
    travel_to(Time.zone.parse(example.metadata.fetch(:now, '2026-10-07T15:00:00-03:00'))) { example.run }
  end

  # let!: os ajudantes de insights/conversas leem o cenário de advisor_setup (@advisor), então ele vem antes de tudo.
  let!(:setup) { advisor_setup }
  let(:account) { setup.first }
  let(:connection) { setup.last }

  def sep(day)
    Date.new(2026, 9, day)
  end

  def oct(day)
    Date.new(2026, 10, day)
  end

  # Insights "neutros" (§6.2): CTR 1,5% e CPM 20 nas duas janelas.
  def neutral_baseline
    [12_000, 180, 240]
  end

  def neutral_recent
    [5_000, 75, 100]
  end

  # baseline: [impressões, cliques, R$] espalhados em 09/09–29/09.
  def baseline_insights(ad_id, adset_id, (impressions, link_clicks, spend))
    advisor_insights(ad_id: ad_id, adset_id: adset_id, from: sep(9), to: sep(29), spend: spend, impressions: impressions,
                     link_clicks: link_clicks)
  end

  # recent: [impressões, cliques, R$] em 30/09–06/10; meta7 = conversations_started do conjunto nesse período.
  def recent_insights(ad_id, adset_id, (impressions, link_clicks, spend), meta7:)
    advisor_insights(ad_id: ad_id, adset_id: adset_id, from: sep(30), to: oct(6), spend: spend, impressions: impressions,
                     link_clicks: link_clicks, conversations_started: meta7)
  end

  # Linha de base com o gasto por semana: 09–15/09, weekB e weekA. Impressões e cliques se dividem por igual.
  def weekly_baseline(ad_id, adset_id, impressions:, link_clicks:, spends:)
    [[sep(9), sep(15)], [sep(16), sep(22)], [sep(23), sep(29)]].zip(spends).each do |(from, to), spend|
      advisor_insights(ad_id: ad_id, adset_id: adset_id, from: from, to: to, spend: spend, impressions: impressions / 3,
                       link_clicks: link_clicks / 3)
    end
  end

  def conversations(ad_id, count, from: sep(9), to: oct(6), reply_after: 120)
    advisor_conversations(ad_id: ad_id, count: count, from: from, to: to, reply_after: reply_after)
  end

  # "N; k vendas": k das N conversas viram card ganho.
  def with_sales(list, count)
    list.first(count).each { |conversation| advisor_sale(conversation) }
    list
  end

  # Uma conversa num dia exato, com venda (para a venda cair na semana certa).
  def sold_on(ad_id, day)
    advisor_sale(conversations(ad_id, 1, from: day, to: day).first)
  end

  # Gabarito §6.4: P = pass, F = fail, N = no_data, X = not_applicable. Conta: stalled_quotes, slow_response,
  # tracking, auction. Por anúncio: data_gate, learning, fatigue, scale (nessa ordem).
  def gabarito_rules(account_codes, ads)
    statuses = { 'P' => 'pass', 'F' => 'fail', 'N' => 'no_data', 'X' => 'not_applicable' }
    ad_rule_names = %w[data_gate learning fatigue scale]
    account_rules = %w[stalled_quotes slow_response tracking auction].zip(account_codes.split)
    ad_rules = ads.flat_map { |ad_id, codes| ad_rule_names.map { |rule| "#{rule}:#{ad_id}" }.zip(codes.split) }
    (account_rules + ad_rules).to_h.transform_values { |code| statuses.fetch(code) }
  end

  def expect_gabarito(account_codes, ads, actions)
    result = advisor_evaluate(connection)
    expect(result[:rules]).to eq(gabarito_rules(account_codes, ads))
    expect(result[:actions]).to eq(actions)
  end

  # Conferências extras (variante e fatos da ação): a Decision real, sem ação aceita ou dispensada no cenário.
  def advisor_facts
    Crm::MetaAds::Advisor::Facts.new(connection, now: Time.current).payload
  end

  def advisor_decision
    facts = advisor_facts
    rules = Crm::MetaAds::Advisor::Rules.evaluate(facts, history: { scale_accepted_ad_ids: [] })
    Crm::MetaAds::Advisor::Decision.for(facts, rules, today: {}).map(&:deep_symbolize_keys)
  end

  # Cenários-base reaproveitados (§6.3, "como Sn").
  def s1_base
    baseline_insights('A', 'SA', [12_000, 180, 240])
    recent_insights('A', 'SA', [5_000, 50, 100], meta7: 10)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.5)
    with_sales(conversations('A', 25), 2)
  end

  def s2_base(frequency_date_end: oct(6))
    baseline_insights('A', 'SA', [12_000, 180, 240])
    recent_insights('A', 'SA', [5_000, 73, 100], meta7: 10)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 4.6, date_end: frequency_date_end)
    with_sales(conversations('A', 25), 2)
  end

  # 12 respondidas em 25 min + 2 sem resposta, entrada 2 dias atrás. Devolve as respondidas.
  def s7_base
    baseline_insights('A', 'SA', neutral_baseline)
    recent_insights('A', 'SA', neutral_recent, meta7: 6)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.0)
    conversations('A', 2, from: oct(5), to: oct(5), reply_after: nil)
    conversations('A', 12, reply_after: 1500)
  end

  # S7 + 2 propostas paradas. waiting_days: 5 (§6.3) ou o que o cenário pedir. Devolve as 2 conversas.
  def s8_base(waiting_days: 5)
    s7_base.first(2).each { |conversation| advisor_stalled_quote(conversation, waiting_days: waiting_days) }
  end

  # C vende abaixo da média nas duas semanas maduras; D ainda não tem base.
  def s10_base(meta7_c: 60)
    weekly_baseline('C', 'SC', impressions: 21_000, link_clicks: 315, spends: [70, 140, 140])
    recent_insights('C', 'SC', [7_000, 105, 130], meta7: meta7_c)
    advisor_frequency(ad_id: 'C', adset_id: 'SC', frequency: 2.1)
    [sep(10), sep(17), sep(24), oct(1)].each { |day| sold_on('C', day) }
    conversations('C', 20)

    baseline_insights('D', 'SD', [18_000, 270, 300])
    recent_insights('D', 'SD', [6_000, 90, 120], meta7: 20)
    advisor_frequency(ad_id: 'D', adset_id: 'SD', frequency: 2.0)
    with_sales(conversations('D', 20), 2)
  end

  it 'S1 — fadiga por CTR: o clique cai 33% e o consultor pede troca do criativo de A' do
    s1_base

    expect_gabarito('X P P P', { 'A' => 'F F F X' }, [%w[refresh_creative A open]])
  end

  it 'S2 — fadiga por frequência: cada pessoa viu A 4,6 vezes em 7 dias' do
    s2_base

    expect_gabarito('X P P P', { 'A' => 'F F F X' }, [%w[refresh_creative A open]])
  end

  it 'S3 — leilão: o CPM sobe 40% com o CTR estável, e a ação é não mexer no anúncio' do
    baseline_insights('A', 'SA', [12_000, 180, 240])
    recent_insights('A', 'SA', [5_000, 73, 140], meta7: 10)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.0)
    with_sales(conversations('A', 25), 2)

    expect_gabarito('X P P F', { 'A' => 'F F P X' }, [['auction_pressure', nil, 'open']])
  end

  it 'S4 — poucos dados: sem frequência nem CTR mensurável, aguardar 12 conversas de A' do
    baseline_insights('A', 'SA', [500, 5, 125])
    recent_insights('A', 'SA', [300, 3, 75], meta7: 3)
    conversations('A', 8)

    expect_gabarito('X N P N', { 'A' => 'N F N X' }, [['wait', 'A', nil]])
    expect(advisor_decision.sole.dig(:facts, :missing_conversations)).to eq(12)
  end

  it 'S5 — conta pequena: tudo pronto para escalar, mas o aprendizado do conjunto barra' do
    baseline_insights('A', 'SA', [21_000, 315, 315])
    recent_insights('A', 'SA', [7_000, 105, 105], meta7: 6)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 1.8)
    [sep(17), sep(24), oct(1)].each { |day| sold_on('A', day) }
    conversations('A', 19)

    expect_gabarito('X P P P', { 'A' => 'P F P F' }, [['on_track', nil, nil]])
  end

  it 'S6 — conta pequena sem venda: sem custo-alvo, o portão não barra e A vai para revisão' do
    baseline_insights('A', 'SA', [15_000, 225, 225])
    recent_insights('A', 'SA', [5_000, 75, 75], meta7: 8)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.0)
    conversations('A', 25)

    expect_gabarito('X P P P', { 'A' => 'N F P X' }, [%w[review_ad A open]])
    expect(advisor_decision.sole).to include(kind: 'review_ad', variant: 'no_sales')
  end

  it 'S7 — atendimento lento: mediana de 25 min nas conversas de anúncio' do
    s7_base

    expect_gabarito('X F P P', { 'A' => 'N F P X' }, [['slow_response', nil, 'open']])
  end

  it 'S8 — lento e com propostas paradas: as paradas vêm primeiro' do
    s8_base

    expect_gabarito('F F P P', { 'A' => 'N F P X' }, [['stalled_quotes', nil, 'open'], ['slow_response', nil, 'open']])
  end

  it 'S9 — rastreio ruim: 20 de 29 conversas identificadas (69%) e a revisão de B fica bloqueada' do
    baseline_insights('B', 'SB', neutral_baseline)
    recent_insights('B', 'SB', neutral_recent, meta7: 8)
    advisor_frequency(ad_id: 'B', adset_id: 'SB', frequency: 2.0)
    conversations('B', 20)
    conversations(nil, 9)

    expect_gabarito('X P F P', { 'B' => 'N F P X' }, [['fix_tracking', nil, 'open']])
  end

  it 'S10 — escala: C vende abaixo da média nas duas semanas maduras' do
    s10_base

    expect_gabarito('X P P P', { 'C' => 'P P P P', 'D' => 'F F P X' }, [%w[scale_ad C open]])
  end

  it 'S11 — escala em descanso: aumento de C aceito há 2 dias, nada de escalar de novo' do
    s10_base
    advisor_resolved(account, kind: 'scale_ad', subject_key: 'ad:C', ad_id: 'C', status: :accepted, local_date: oct(5))

    expect_gabarito('X P P P', { 'C' => 'P P P F', 'D' => 'F F P X' }, [['on_track', nil, nil]])
  end

  it 'S12 — teto de 3: paradas, lentidão e rastreio; a troca de criativo de E fica de fora' do
    baseline_insights('B', 'SB', neutral_baseline)
    recent_insights('B', 'SB', neutral_recent, meta7: 8)
    advisor_frequency(ad_id: 'B', adset_id: 'SB', frequency: 2.0)
    conversations('B', 20, reply_after: 1500).first(2).each { |conversation| advisor_stalled_quote(conversation) }

    baseline_insights('E', 'SE', [12_000, 180, 240])
    recent_insights('E', 'SE', [5_000, 50, 100], meta7: 4)
    advisor_frequency(ad_id: 'E', adset_id: 'SE', frequency: 2.5)
    conversations('E', 5, reply_after: 1500)
    conversations(nil, 12, reply_after: 1500)

    expect_gabarito('F F F P', { 'B' => 'N F P X', 'E' => 'N F F X' },
                    [['stalled_quotes', nil, 'open'], ['slow_response', nil, 'open'], ['fix_tracking', nil, 'open']])
  end

  it 'S13 — dispensada hoje: as paradas saem e não voltam no mesmo dia' do
    s8_base
    advisor_resolved(account, kind: 'stalled_quotes', subject_key: 'account', status: :dismissed, local_date: oct(7))

    expect_gabarito('F F P P', { 'A' => 'N F P X' }, [['slow_response', nil, 'open']])
  end

  it 'S14 — sem dado: nenhum anúncio, nenhuma conversa' do
    expect_gabarito('X X N X', {}, [['no_data', nil, nil]])
  end

  it 'S15 — o portão de dados barra a revisão de F, que gastou menos de 3 vendas-alvo' do
    baseline_insights('F', 'SF', [12_000, 180, 150])
    recent_insights('F', 'SF', [5_000, 75, 50], meta7: 8)
    advisor_frequency(ad_id: 'F', adset_id: 'SF', frequency: 2.0)
    conversations('F', 20)

    weekly_baseline('G', 'SG', impressions: 12_000, link_clicks: 180, spends: [30, 90, 90])
    recent_insights('G', 'SG', [4_000, 60, 90], meta7: 10)
    advisor_frequency(ad_id: 'G', adset_id: 'SG', frequency: 2.0)
    [sep(17), sep(24), oct(1)].each { |day| sold_on('G', day) }
    conversations('G', 19)

    expect_gabarito('X P P P', { 'F' => 'F F P X', 'G' => 'P F P F' }, [['on_track', nil, nil]])
  end

  it 'S16 — fadiga e leilão juntos: B compensa o CTR de A na conta, o CPM sobe 40%' do
    baseline_insights('A', 'SA', [12_000, 180, 240])
    recent_insights('A', 'SA', [5_000, 50, 140], meta7: 10)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.5)
    with_sales(conversations('A', 25), 2)

    baseline_insights('B', 'SB', [12_000, 180, 240])
    recent_insights('B', 'SB', [5_000, 100, 140], meta7: 10)
    advisor_frequency(ad_id: 'B', adset_id: 'SB', frequency: 2.0)
    with_sales(conversations('B', 25), 2)

    expect_gabarito('X P P F', { 'A' => 'F F F X', 'B' => 'F F P X' },
                    [%w[refresh_creative A open], ['auction_pressure', nil, 'open']])
  end

  it 'S17 — anúncio novo sem linha de base: fadiga sem dado, aguardar 12 conversas de N' do
    recent_insights('N', 'SN', [5_000, 50, 100], meta7: 5)
    advisor_frequency(ad_id: 'N', adset_id: 'SN', frequency: 2.0)
    conversations('N', 8, from: sep(30), to: oct(6))

    expect_gabarito('X N P N', { 'N' => 'N F N X' }, [['wait', 'N', nil]])
    expect(advisor_decision.sole.dig(:facts, :missing_conversations)).to eq(12)
  end

  it 'S18 — lento só por falta de resposta: mediana de 1 min, mas 4 de 15 sem resposta' do
    baseline_insights('A', 'SA', neutral_baseline)
    recent_insights('A', 'SA', neutral_recent, meta7: 6)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.0)
    conversations('A', 11, reply_after: 60)
    conversations('A', 4, from: oct(6), to: oct(6), reply_after: nil)

    expect_gabarito('X F P P', { 'A' => 'N F P X' }, [['slow_response', nil, 'open']])
  end

  it 'S19 — modelo e automação não contam como resposta: vale a da pessoa, aos 30 min' do
    baseline_insights('A', 'SA', neutral_baseline)
    recent_insights('A', 'SA', neutral_recent, meta7: 6)
    advisor_frequency(ad_id: 'A', adset_id: 'SA', frequency: 2.0)
    conversations('A', 12, reply_after: 1800).each do |conversation|
      advisor_template_reply(conversation, after: 5)
      advisor_automation_reply(conversation, after: 10)
    end

    expect_gabarito('X F P P', { 'A' => 'N F P X' }, [['slow_response', nil, 'open']])
    expect(advisor_facts.deep_symbolize_keys.dig(:account, :response, :median_seconds)).to eq(1800)
  end

  it 'S20 — fronteira de fuso: 23h30 em São Paulo (já 08/10 em UTC) ainda é 07/10', now: '2026-10-07T23:30:00-03:00' do
    s1_base

    expect_gabarito('X P P P', { 'A' => 'F F F X' }, [%w[refresh_creative A open]])
    expect(advisor_facts.deep_symbolize_keys[:local_date]).to eq('2026-10-07')
  end

  it 'S21a — frequência de anteontem (date_end 05/10) ainda vale' do
    s2_base(frequency_date_end: oct(5))

    expect_gabarito('X P P P', { 'A' => 'F F F X' }, [%w[refresh_creative A open]])
    expect(advisor_decision.sole).to include(kind: 'refresh_creative', variant: 'frequency')
  end

  it 'S21b — frequência velha (date_end 04/10) vira sem dado' do
    s2_base(frequency_date_end: oct(4))

    expect_gabarito('X P P P', { 'A' => 'F F N X' }, [['on_track', nil, nil]])
  end

  it 'S22a — ação aceita hoje fica na lista, marcada como aceita' do
    s8_base
    advisor_resolved(account, kind: 'stalled_quotes', subject_key: 'account', status: :accepted, local_date: oct(7))

    expect_gabarito('F F P P', { 'A' => 'N F P X' }, [['stalled_quotes', nil, 'accepted'], ['slow_response', nil, 'open']])
  end

  it 'S22b — aceita fica mesmo resolvida: as propostas já se mexeram há 1 hora' do
    s8_base(waiting_days: 1.hour.in_days)
    advisor_resolved(account, kind: 'stalled_quotes', subject_key: 'account', status: :accepted, local_date: oct(7))

    expect_gabarito('P F P P', { 'A' => 'N F P X' }, [['stalled_quotes', nil, 'accepted'], ['slow_response', nil, 'open']])
  end

  it 'S23 — conta só de site: sem conversa contada pela Meta, aprendizado e escala ficam sem dado' do
    s10_base(meta7_c: 0)

    expect_gabarito('X P P P', { 'C' => 'P N P N', 'D' => 'F F P X' }, [['on_track', nil, nil]])
  end
end
