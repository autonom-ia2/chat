require 'rails_helper'

# A checagem do texto da IA (#1110, F5, CA-4.2): um caso por código, sem regex.
RSpec.describe Crm::MetaAds::Advisor::Check do
  let(:facts) { { 'ad_name' => 'Promo 10/10', 'window_days' => 7, 'ctr_drop_pct' => 0.33, 'frequency_7d' => nil } }
  let(:actions) { [{ key: 'a1', facts: facts }] }
  let(:valid) do
    { 'key' => 'a1', 'headline' => 'Troque a imagem de {{ad_name}}.',
      'body' => 'Nos últimos {{window_days}} dias, as pessoas clicaram {{ ctr_drop_pct }} menos.',
      'why' => 'O clique caiu {{ctr_drop_pct}}.' }
  end

  def check(entry = {}, **answer)
    described_class.call({ 'applies' => true, 'numbers_in_words' => false, 'actions' => [valid.merge(entry)] }.merge(answer.stringify_keys),
                         actions)
  end

  def codes(entry)
    check(entry)[:rejected].fetch('a1', [])
  end

  it 'aceita o texto com marcadores, inclusive nome de anúncio com dígito e prazo como fato' do
    expect(check).to eq(ok: ['a1'], rejected: {}, global: [])
  end

  it 'numbers_in_words: a autodeclaração do modelo recusa todas as ações' do
    expect(check({}, numbers_in_words: true)).to eq(ok: [], rejected: {}, global: ['numbers_in_words'])
  end

  it 'missing_action: ação enviada que não voltou, ou voltou duas vezes' do
    expect(described_class.call({ 'actions' => [] }, actions)[:rejected]).to eq('a1' => ['missing_action'])
    expect(described_class.call({ 'actions' => [valid, valid] }, actions)[:rejected]).to eq('a1' => ['missing_action'])
    expect(described_class.call('não é JSON', actions)[:rejected]).to eq('a1' => ['missing_action'])
  end

  it 'malformed_placeholder: {{ sem }}, }} solto e chave vazia' do
    expect(codes('headline' => 'Troque {{ad_name a imagem.')).to eq(['malformed_placeholder'])
    expect(codes('headline' => 'Troque ad_name}} a imagem.')).to eq(['malformed_placeholder'])
    expect(codes('headline' => 'Troque {{}} a imagem.')).to eq(['malformed_placeholder'])
  end

  it 'unknown_fact: chave fora dos fatos daquela ação, ou fato sem valor' do
    expect(codes('body' => 'Gastou {{spend}}.')).to eq(['unknown_fact'])
    expect(codes('body' => 'Cada pessoa viu {{frequency_7d}} vezes.')).to eq(['unknown_fact'])
  end

  it 'digit_outside_fact: dígito fora do marcador, inclusive o dígito largo que o NFKC converte' do
    expect(codes('body' => 'O clique caiu 33% em {{ad_name}}.')).to eq(['digit_outside_fact'])
    expect(codes('body' => 'O clique caiu ３３% em {{ad_name}}.')).to eq(['digit_outside_fact'])
  end

  it 'why_without_fact: o porquê precisa citar um fato' do
    expect(codes('why' => 'As pessoas cansaram do anúncio.')).to eq(['why_without_fact'])
  end

  it 'empty_headline: título vazio' do
    expect(codes('headline' => '  ')).to eq(['empty_headline'])
  end

  it 'too_long: acima do limite, medido com os marcadores, e recusa em vez de cortar' do
    expect(codes('headline' => "#{'a' * 110} {{ad_name}}")).to eq(['too_long'])
    expect(codes('body' => 'a' * 401)).to eq(['too_long'])
    expect(codes('why' => "#{'a' * 300}{{ad_name}}")).to eq(['too_long'])
  end

  it 'cada ação é conferida com os próprios fatos' do
    other = { key: 'a2', facts: { 'count' => 2 } }
    answer = { 'actions' => [valid, { 'key' => 'a2', 'headline' => 'Retome {{count}} propostas.', 'body' => '', 'why' => 'De {{ad_name}}.' }] }

    expect(described_class.call(answer, actions + [other])).to eq(ok: ['a1'], rejected: { 'a2' => ['unknown_fact'] }, global: [])
  end
end
