require 'rails_helper'

# O texto das ações do consultor pela IA (#1110, F5, §1.5): marcadores no lugar dos números, uma nova tentativa
# na recusa, a regra nas ações que não passam e a falha do provedor sem estado final.
RSpec.describe Crm::MetaAds::Advisor::Writer do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) { example.run }
    end
  end

  let(:account) { create(:account) }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }
  let(:actions) do
    [{ 'kind' => 'stalled_quotes', 'subject_key' => 'account', 'variant' => nil, 'ad_id' => nil, 'position' => 1,
       'facts' => { 'count' => 2, 'value' => 3000.0, 'days' => 3, 'ad_name' => 'Promo', 'cards' => [{ 'id' => 9, 'value' => 1500.0 }] } },
     { 'kind' => 'refresh_creative', 'subject_key' => 'ad:A', 'variant' => 'ctr', 'ad_id' => 'A', 'position' => 2,
       'facts' => { 'ad_name' => 'Promo', 'ctr_drop_pct' => 0.33, 'frequency_7d' => 2.5, 'window_days' => 7 } }]
  end
  let(:run) do
    Crm::MetaAdvisorRun.create!(account: account, ad_account_id: '9001', local_date: Date.new(2026, 10, 7), locale: 'pt_BR', signature: 's',
                                rules_version: 'f5.1', trigger: 'panel', facts: { 'currency' => 'BRL' }, decision: actions)
  end
  let(:good) do
    [{ 'key' => 'a1', 'headline' => 'Retome as {{count}} propostas.', 'body' => 'Somam {{value}}.', 'why' => 'Paradas há {{days}} dias.' },
     { 'key' => 'a2', 'headline' => 'Troque a imagem de {{ad_name}}.', 'body' => 'O clique caiu {{ctr_drop_pct}}.',
       'why' => 'Nos últimos {{window_days}} dias.' }]
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'anuncios_meta', account: account, max_retries: described_class::MAX_RETRIES).and_return(client)
  end

  def reply(entries, applies: true)
    { text: { 'applies' => applies, 'numbers_in_words' => false, 'actions' => entries }.to_json }
  end

  def perform
    described_class.new(run: run, actions: actions, facts: run.facts, language: 'pt_BR').perform
  end

  it 'manda só os fatos de cada ação, com o tipo e a variante, e guarda o texto com marcadores' do
    expect(client).to receive(:create) do |request|
      expect(request).to include(model: Crm::Ai::Config::MODEL_SUMMARY, schema: described_class::SCHEMA, timeout: described_class::REQUEST_TIMEOUT,
                                 instructions: Crm::MetaAds::Advisor::Prompt.instructions)
      input = JSON.parse(request[:input])
      expect(input.slice('language', 'currency')).to eq('language' => 'pt_BR', 'currency' => 'BRL')
      expect(input['actions'].first).to eq('key' => 'a1', 'kind' => 'stalled_quotes', 'variant' => nil,
                                           'facts' => { 'count' => 2, 'value' => 3000.0, 'days' => 3, 'ad_name' => 'Promo' })
      reply(good)
    end

    expect(perform).to eq(writer_status: 'written', writer_reason: nil, writer_attempts: 1, model: Crm::Ai::Config::MODEL_SUMMARY,
                          retry_after: nil,
                          texts: { 'stalled_quotes|account' => good.first.except('key'), 'refresh_creative|ad:A' => good.last.except('key') })
  end

  it 'recusa e acerta: chama de novo uma vez, só com os códigos, e vale o texto da IA' do
    bad = [good.first.merge('body' => 'Somam R$ 3000.'), good.last]
    allow(client).to receive(:create).and_return(reply(bad), reply(good))

    result = perform

    expect(result).to include(writer_status: 'written', writer_reason: nil, writer_attempts: 2)
    expect(client).to have_received(:create).twice
    expect(client).to have_received(:create).with(hash_including(input: include('"previous_rejection":["digit_outside_fact"]'),
                                                                 reasoning_effort: described_class::RETRY_REASONING_EFFORT))
    expect(client).not_to have_received(:create).with(hash_including(input: include('R$ 3000')))
  end

  it 'texto longo demais: a nova tentativa recebe o tamanho de cada texto da ação recusada, nunca o texto' do
    long_body = "#{'Retome cada proposta com calma. ' * 14}São {{count}}."
    bad = [good.first.merge('body' => long_body), good.last]
    allow(client).to receive(:create).and_return(reply(bad), reply(good))

    perform

    expect(client).to have_received(:create).with(hash_including(input: include('"previous_rejection":["too_long"]')))
    lengths = %("previous_lengths":{"a1":{"headline":"#{good.first['headline'].length}/120","body":"#{long_body.length}/400")
    expect(client).to have_received(:create).with(hash_including(input: include(lengths)))
    expect(client).not_to have_received(:create).with(hash_including(input: include('Retome cada proposta com calma. Retome')))
  end

  it 'recusa duas vezes: a aprovada fica com a IA, a recusada volta à regra, e o motivo é check_failed' do
    bad = [good.first.merge('why' => 'Paradas.'), good.last]
    allow(client).to receive(:create).and_return(reply(bad))

    result = perform

    expect(result).to include(writer_status: 'written', writer_reason: 'check_failed', writer_attempts: 2)
    expect(result[:texts].keys).to eq(['refresh_creative|ad:A'])
  end

  it 'nenhuma aprovada nas duas: tudo pela regra' do
    allow(client).to receive(:create).and_return(reply([], applies: true))

    expect(perform).to include(writer_status: 'rule', writer_reason: 'check_failed', writer_attempts: 2, texts: {}, model: nil)
  end

  it '"não se aplica" deixa todas pela regra' do
    allow(client).to receive(:create).and_return(reply([], applies: false))

    expect(perform).to include(writer_status: 'rule', writer_reason: 'not_applicable', writer_attempts: 1, texts: {})
  end

  # O modelo gera as chaves na ordem do schema: a autodeclaração vem depois dos textos, não antes de escrevê-los.
  it 'numbers_in_words vem depois de actions no schema' do
    schema = described_class::SCHEMA[:schema]

    expect(schema[:properties].keys).to eq(%i[applies actions numbers_in_words])
    expect(schema[:required]).to eq(%w[applies actions numbers_in_words])
  end

  # Senão outra aba reivindica o run com o primeiro job ainda vivo: outra vaga do teto e o texto pago jogado fora.
  it 'o pior caso da escrita (2 pedidos, com as novas tentativas e as esperas) cabe antes de o run contar como abandonado' do
    calls = 1 + described_class::MAX_RETRIES
    worst = 2 * ((calls * described_class::REQUEST_TIMEOUT) + (1..described_class::MAX_RETRIES).sum)

    expect(worst.seconds).to be < Crm::MetaAds::Advisor::Analysis::STALE_WRITING
  end

  it 'falha do provedor não é estado final: volta a pending por 15 min' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect(perform).to include(writer_status: 'pending', writer_reason: 'ai_error', retry_after: 15.minutes.from_now, texts: {})
  end

  it 'as duas tentativas contam uma geração no teto do dia' do
    allow(client).to receive(:create).and_return(reply([]))
    key = Crm::MetaAds::Advisor::Analysis.counter_key(account.id, run.local_date)
    Redis::Alfred.delete(key)

    Crm::MetaAds::Advisor::Analysis.write!(run)

    expect(client).to have_received(:create).twice
    expect(Redis::Alfred.get(key).to_i).to eq(1)
    expect(run.reload).to have_attributes(writer_status: 'rule', writer_reason: 'check_failed', writer_attempts: 2)
  ensure
    Redis::Alfred.delete(key)
  end
end
