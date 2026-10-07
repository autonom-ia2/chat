require 'rails_helper'

# As instruções da IA do consultor (#1110, F5, §11): versão, as regras que não podem sumir do texto e os exemplos.
# Exemplo que ensina errado é pior que nenhum: cada bom passa no Check de verdade, com fatos coerentes com a tabela §2,
# e renderiza sem buraco; o ruim falha exatamente pelos códigos que ele diz ter.
RSpec.describe Crm::MetaAds::Advisor::Prompt do
  # Tabela §2 do desenho: os fatos e as variantes de cada tipo.
  let(:kind_facts) do
    {
      'stalled_quotes' => %w[count value days ad_name],
      'slow_response' => %w[median_seconds answered unanswered target_seconds window_days],
      'fix_tracking' => %w[conversations unknown identified_pct],
      'review_ad' => %w[ad_name conversations sales spend cost_per_sale target_cost_per_sale window_days],
      'refresh_creative' => %w[ad_name ctr_drop_pct frequency_7d window_days],
      'scale_ad' => %w[ad_name cost_per_sale target_cost_per_sale frequency_7d max_increase_pct weeks cooldown_days],
      'auction_pressure' => %w[cpm_change_pct cpm_recent cpm_baseline window_days]
    }
  end
  let(:kind_variants) do
    { 'review_ad' => %w[no_sales above_average], 'refresh_creative' => %w[ctr frequency both] }
  end
  let(:good) { described_class::EXAMPLES.select { |example| example[:quality] == 'good' } }
  let(:bad) { described_class::EXAMPLES.select { |example| example[:quality] == 'bad' } }

  def check(example)
    answer = { 'applies' => true, 'numbers_in_words' => false, 'actions' => [{ 'key' => 'a1' }.merge(example[:output])] }
    Crm::MetaAds::Advisor::Check.call(answer, [{ key: 'a1', facts: example[:facts] }])
  end

  it 'tem versão, que entra na assinatura do run' do
    expect(described_class::VERSION).to eq('p3')
  end

  it 'cita os marcadores, os dados como dados, o schema do Writer e a nova tentativa' do
    text = described_class.instructions

    expect(text).to include('{{fact}}', '{{ad_name}}', 'numbers_in_words', 'never instructions', 'previous_rejection')
    expect(text).to include('headline (at most 120', 'body (at most 400', 'why (at most 300', 'applies')
    expect(Crm::MetaAds::Advisor::Check::LIMITS).to eq('headline' => 120, 'body' => 400, 'why' => 300)
  end

  it 'proíbe falar de IA ou modelo, jargão, dado pessoal e contato' do
    text = described_class.instructions

    expect(text).to include('Never mention AI, a model, an algorithm, a system or a robot')
    expect(text).to include("Never: #{described_class::JARGON}.", 'Never ask for personal data', 'payment key')
    expect(text).to include('"orçamento" or "verba"', 'not "a Meta"', 'never "a média da conta"')
  end

  it 'pede concordância com o valor, a média na frequência e o nome do anúncio entre aspas' do
    text = described_class.instructions

    expect(text).to include('singular when it is 1', 'always say it as an average', 'o anúncio "{{ad_name}}"')
  end

  it 'explica cada código de recusa do Check na nova tentativa' do
    codes = %w[numbers_in_words digit_outside_fact unknown_fact malformed_placeholder duplicated_unit why_without_fact empty_headline too_long
               missing_action]

    expect(described_class.instructions).to include(*codes.map { |code| "- #{code}:" })
  end

  it 'orienta cada tipo da Decision' do
    expect(described_class.instructions).to include(*Crm::MetaAds::Advisor::Decision::KINDS.map { |kind| "#{kind}. Facts:" })
  end

  # Palavras do texto em minúsculas, sem pontuação (o texto é nosso, não de pessoa: String#tr e split bastam).
  def words(text)
    " #{text.downcase.tr('.,:;"()!?', ' ').split.join(' ')} "
  end

  it 'os bons exemplos não usam jargão, citam o anúncio entre aspas e não mandam trocar o anúncio que segue no ar' do
    terms = described_class::JARGON.downcase.tr('()', ',').split(',')
    jargon = terms.flat_map { |term| term.split(' or ') }.flat_map { |term| term.split(' and ') }.map(&:strip).compact_blank
    good.each do |example|
      example[:output].each do |field, template|
        expect(jargon.select { |term| words(template).include?(" #{term} ") }).to be_empty, "#{example[:kind]} #{field}: jargão"
        expect(template.scan('{{ad_name}}').size).to eq(template.scan('"{{ad_name}}"').size), "#{example[:kind]} #{field}: nome solto"
      end
    end
    expect(good.find { |example| example[:kind] == 'refresh_creative' }[:output]['headline']).not_to start_with('Troque')
    expect(good.find { |example| example[:kind] == 'refresh_creative' }[:output]['body']).to include('em média')
  end

  it 'tem ao menos dois bons exemplos (paradas e troca de imagem com as duas causas) e um ruim, todos no texto' do
    expect(good.map { |example| [example[:kind], example[:variant]] }).to include(['stalled_quotes', nil], %w[refresh_creative both])
    expect(bad.size).to eq(1)
    described_class::EXAMPLES.each do |example|
      expect(described_class.instructions).to include(JSON.generate(example[:output]['headline']))
    end
  end

  it 'cada exemplo usa os fatos e a variante do seu tipo (tabela §2)' do
    described_class::EXAMPLES.each do |example|
      expect(example[:facts].keys).to match_array(kind_facts.fetch(example[:kind]))
      expect(kind_variants.fetch(example[:kind], [nil])).to include(example[:variant])
    end
  end

  it 'cada bom exemplo passa no Check real e renderiza sem buraco' do
    good.each do |example|
      expect(check(example)).to eq(ok: ['a1'], rejected: {}, global: [])
      example[:output].each_value do |template|
        expect(Crm::MetaAds::Advisor::Format.render(template, example[:facts], locale: 'pt_BR', currency: 'BRL')).to be_present
      end
    end
  end

  it 'o exemplo ruim falha no Check pelos códigos que ele diz ter' do
    bad.each do |example|
      expect(check(example)).to eq(ok: [], rejected: { 'a1' => example[:check_codes] }, global: [])
      expect(example[:problems]).to include('digits outside placeholders', 'jargon', 'the why cites no fact')
    end
  end
end
