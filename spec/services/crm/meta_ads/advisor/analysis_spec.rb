require 'rails_helper'

# O consultor de ponta a ponta (#1110, F5, §1.6): run por assinatura, ações gravadas só na criação, escrita com
# reivindicação atômica e teto reservado depois dela, e o Advice com os valores atuais.
RSpec.describe Crm::MetaAds::Advisor::Analysis do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) { example.run }
    end
  end

  let!(:setup) { advisor_setup }
  let(:account) { setup.first }
  let(:connection) { setup.last }
  let(:today) { Date.new(2026, 10, 7) }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }
  let(:texts) do
    { 'headline' => 'Arrume a origem de {{unknown}} conversas.', 'body' => 'Abra a ligação com a Meta.',
      'why' => 'Só {{identified_pct}} têm anúncio.' }
  end
  let(:answer) { { applies: true, numbers_in_words: false, actions: [texts.merge('key' => 'a1')] }.to_json }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    # 6 conversas de anúncio sem anúncio identificado: a única ação do dia é arrumar o rastreio.
    advisor_conversations(ad_id: nil, count: 6, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 6))
  end

  after do
    Redis::Alfred.scan_each(match: 'crm:meta_ads:advisor:*') { |key| Redis::Alfred.delete(key) }
  end

  def current(trigger: 'panel')
    described_class.current(connection, locale: 'pt_BR', trigger: trigger)
  end

  def run_record
    Crm::MetaAdvisorRun.find(current[:run_id])
  end

  def counter
    Redis::Alfred.get(described_class.counter_key(account.id, today))
  end

  it 'devolve o Advice pela regra enquanto a IA não escreveu e marca a ação como mostrada' do
    advice = current

    expect(advice).to include(local_date: '2026-10-07', rules_version: 'f5.2', writer: { status: 'pending', reason: nil })
    action = advice[:actions].sole
    expect(action).to include(position: 1, kind: 'fix_tracking', variant: nil, status: 'open', opened: false, source: 'rule', headline: nil,
                              button: { target: 'connection_step', step: 3, url: nil }, cards: [])
    expect(action[:facts]).to eq('conversations' => 6, 'unknown' => 6, 'identified_pct' => 0.0)
    expect(Crm::MetaAdvisorAction.find(action[:id])).to have_attributes(shown_at: Time.current, run_id: advice[:run_id], position: 1)
  end

  it 'reivindicação: dois write! seguidos, só um chama o Writer' do
    run = run_record
    allow(client).to receive(:create).and_return(text: answer)

    expect(described_class.write!(run)).to be(true)
    expect(described_class.write!(run)).to be(false)

    expect(client).to have_received(:create).once
    expect(run.reload).to have_attributes(writer_status: 'written', writer_attempts: 1, model: Crm::Ai::Config::MODEL_SUMMARY)
    expect(counter.to_i).to eq(1)
  end

  it '`writing` há menos de 5 min é de outro; há 6 min foi abandonado e é reivindicado de novo' do
    run = run_record
    allow(client).to receive(:create).and_return(text: answer)
    run.update!(writer_status: 'writing', writing_started_at: 1.minute.ago)

    expect(described_class.write!(run)).to be(false)
    expect(counter).to be_nil
    expect(current[:writer]).to eq(status: 'writing', reason: nil)

    run.update!(writing_started_at: 6.minutes.ago)
    expect(current[:writer]).to eq(status: 'pending', reason: nil)
    expect(described_class.write!(run)).to be(true)
    expect(run.reload.writer_status).to eq('written')
  end

  it 'teto: sem vaga, o run reivindicado fecha pela regra sem chamar a IA' do
    run = run_record
    Redis::Alfred.set(described_class.counter_key(account.id, today), described_class::DAILY_LIMIT)

    described_class.write!(run)

    expect(run.reload).to have_attributes(writer_status: 'rule', writer_reason: 'daily_limit')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(described_class.limit_reached?(account, today)).to be(true)
  end

  it 'falha do provedor: o Advice mostra a regra até a nova tentativa e depois pede de novo' do
    run = run_record
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')
    described_class.write!(run)

    expect(current[:writer]).to eq(status: 'rule', reason: 'ai_error')
    expect(described_class.write!(run)).to be(false)

    travel 16.minutes
    expect(current[:writer]).to eq(status: 'pending', reason: 'ai_error')
    expect(described_class.write!(run)).to be(true)
    expect(counter.to_i).to eq(2)
  end

  it 'aceitar não muda a assinatura nem cria run, e a ação fica na lista como aceita' do
    first = current
    Crm::MetaAdvisorAction.find(first[:actions].sole[:id]).accept!(create(:user, account: account), via: 'panel')

    second = current

    expect(second[:run_id]).to eq(first[:run_id])
    expect(Crm::MetaAdvisorRun.where(account_id: account.id).count).to eq(1)
    expect(second[:actions].sole).to include(kind: 'fix_tracking', status: 'accepted')
  end

  it 'duas abas ao mesmo tempo: create_or_find_by! usa o run da outra e não grava as ações de novo' do
    other = run_record
    Crm::MetaAdvisorAction.where(account_id: account.id).delete_all
    calls = 0
    allow(Crm::MetaAdvisorRun).to receive(:find_by).and_wrap_original do |original, *args, **options|
      (calls += 1) == 1 ? nil : original.call(*args, **options)
    end

    expect(current[:run_id]).to eq(other.id)
    expect(Crm::MetaAdvisorAction.where(account_id: account.id)).to be_empty
  end

  it 'o run só fica gravado com as ações: se o upsert falha, nada fica e a leitura seguinte cria tudo com id' do
    calls = 0
    allow(Crm::MetaAdvisorAction).to receive(:upsert_all).and_wrap_original do |original, *args, **options|
      (calls += 1) == 1 ? raise(ActiveRecord::StatementInvalid, 'canceling statement due to statement timeout') : original.call(*args, **options)
    end

    expect { current }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Crm::MetaAdvisorRun.where(account_id: account.id)).to be_empty

    action = current[:actions].sole
    expect(action[:id]).to be_present
    expect(Crm::MetaAdvisorAction.find(action[:id]).shown_at).to eq(Time.current)
  end

  it 'outra aba criou o run depois da leitura de hoje: relê as ações e devolve os ids' do
    run_record
    calls = 0
    allow(Crm::MetaAds::Advisor::History).to receive(:today).and_wrap_original do |original, *args|
      (calls += 1) == 1 ? {} : original.call(*args)
    end

    expect(current[:actions].sole[:id]).to eq(Crm::MetaAdvisorAction.find_by!(account_id: account.id, kind: 'fix_tracking').id)
  end

  it 'trocar a conta de anúncios no mesmo dia cria outro run, com a conta nova, mesmo com a mesma decisão' do
    first = run_record
    connection.update_columns(ad_account_id: 'act_9002') # rubocop:disable Rails/SkipsModelValidations

    second = run_record

    expect(second.decision.pluck('kind')).to eq(first.decision.pluck('kind'))
    expect(second.id).not_to eq(first.id)
    expect(second.ad_account_id).to eq('act_9002')
  end

  # O texto guardado tem marcadores: "{{unknown}} conversas" escrito com 4 viraria "1 conversas" com o valor atual.
  it 'mesma decisão: contagem que cruza 1 cria run novo; 4 → 3 mantém o run' do
    decision = lambda do |unknown|
      [{ kind: 'fix_tracking', subject_key: 'account', variant: nil, ad_id: nil, position: 1, status: 'open',
         facts: { 'conversations' => 6, 'unknown' => unknown, 'identified_pct' => 0.5 } }]
    end
    allow(Crm::MetaAds::Advisor::Decision).to receive(:for).and_return(decision.call(4))
    four = current[:run_id]

    allow(Crm::MetaAds::Advisor::Decision).to receive(:for).and_return(decision.call(1))
    one = current[:run_id]

    allow(Crm::MetaAds::Advisor::Decision).to receive(:for).and_return(decision.call(3))
    three = current[:run_id]

    expect(one).not_to eq(four)
    expect(three).to eq(four)
  end

  it 'com shown: false (pedido pelo token de API, o Guia) não marca a ação como mostrada' do
    advice = described_class.current(connection, locale: 'pt_BR', shown: false)

    expect(Crm::MetaAdvisorAction.find(advice[:actions].sole[:id]).shown_at).to be_nil
  end

  it 'expira as abertas dos dias anteriores e grava as ações só quando cria o run' do
    stale = advisor_resolved(account, kind: 'slow_response', subject_key: 'account', status: :open, local_date: today - 1)
    current
    expect(stale.reload.status).to eq('expired')

    later = advisor_resolved(account, kind: 'scale_ad', subject_key: 'ad:Z', status: :open, local_date: today - 1)
    stored = Crm::MetaAdvisorAction.find_by(account_id: account.id, local_date: today)
    stored.update!(facts: { 'unknown' => 99 })
    current

    expect(later.reload.status).to eq('open')
    expect(stored.reload.facts).to eq('unknown' => 99)
  end

  it 'render: põe os valores atuais; marcador sem valor atual volta ao texto da regra' do
    run = run_record
    run.update!(writer_status: 'written', texts: { 'fix_tracking|account' => texts })

    expect(current[:actions].sole).to include(source: 'ai', headline: 'Arrume a origem de 6 conversas.', why: 'Só 0% têm anúncio.')

    run.update!(texts: { 'fix_tracking|account' => texts.merge('body' => 'Gastou {{cost_per_sale}}.') })
    expect(current[:actions].sole).to include(source: 'rule', headline: nil, body: nil, why: nil)
  end

  it 'daily: o resumo das 8h escreve na hora quando o run está livre e há vaga' do
    allow(client).to receive(:create).and_return(text: answer)

    advice = described_class.daily(connection, language: 'pt_BR')

    expect(advice[:writer]).to eq(status: 'written', reason: nil)
    expect(advice[:actions].sole).to include(source: 'ai', body: 'Abra a ligação com a Meta.')
    expect(Crm::MetaAdvisorRun.find(advice[:run_id]).trigger).to eq('digest')
    expect(Crm::MetaAdvisorAction.find(advice[:actions].sole[:id]).shown_at).to be_nil
  end

  it 'serialize: o Advice de um run já existente, com as ações e o estado de agora' do
    run = run_record
    described_class.rule!(run, 'ai_unavailable')

    advice = described_class.serialize(run.reload, 'pt_BR')

    expect(advice).to include(run_id: run.id, writer: { status: 'rule', reason: 'ai_unavailable' })
    expect(advice[:actions].sole).to include(kind: 'fix_tracking', source: 'rule')
  end

  it 'dispensada não vem na lista' do
    advice = current
    Crm::MetaAdvisorAction.find(advice[:actions].sole[:id]).dismiss!(create(:user, account: account), via: 'panel')

    expect(current[:actions].map { |action| action[:kind] }).to eq(['no_data'])
  end
end
