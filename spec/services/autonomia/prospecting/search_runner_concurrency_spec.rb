require 'rails_helper'
require 'timeout'

# Duas buscas de verdade, em duas conexões, sem a transação do teste por fora (#683). Os testes de corrida do
# search_runner_spec rodam numa conexão só e não pegam deadlock: aqui cada busca trava linhas do Postgres de verdade.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:user) { create(:user, :administrator, account: account) }
  let(:mock_provider_class) { Autonomia::Prospecting::Providers::MockProvider }
  let(:place_a) { { provider: 'mock', provider_place_id: 'places/a', name: 'Alfa Pizza', phone: '+5541999990001', raw_payload: {} } }
  let(:place_b) { { provider: 'mock', provider_place_id: 'places/b', name: 'Beta Cantina', phone: '+5541999990002', raw_payload: {} } }
  let(:workers) { [] }

  before do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock', cache_ttl_seconds: 0)
    # Os dois lugares já existem: as duas buscas fazem UPDATE nas mesmas linhas.
    [place_a, place_b].each do |place|
      Autonomia::Prospecting::Lead.create!(place.merge(account: account, dedupe_key: "mock:#{place[:provider_place_id]}"))
    end
    allow(mock_provider_class).to receive(:new) do |**kwargs|
      instance_double(mock_provider_class, search: kwargs[:query] == 'pizzaria' ? [place_a, place_b] : [place_b, place_a])
    end
  end

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    Autonomia::Prospecting::Lead.where(account_id: account.id).delete_all
    Autonomia::Prospecting::Search.where(account_id: account.id).delete_all
    Autonomia::Prospecting::Setting.where(account_id: account.id).delete_all
    AccountUser.where(account_id: account.id).delete_all
    user.destroy!
    account.destroy!
  end

  # Segura cada busca depois do primeiro lead gravado até a outra chegar no mesmo ponto, ou até o prazo. Com a ordem
  # invertida e sem ordenação, as duas chegam e cada uma pede a linha que a outra travou: deadlock.
  def barrier(parties, wait_seconds)
    mutex = Mutex.new
    arrived = ConditionVariable.new
    count = 0
    lambda do
      mutex.synchronize do
        count += 1
        arrived.broadcast
        deadline = Time.current + wait_seconds
        arrived.wait(mutex, deadline - Time.current) while count < parties && Time.current < deadline
      end
    end
  end

  it 'duas buscas simultâneas com os mesmos lugares em ordem invertida terminam as duas' do
    wait = barrier(2, 3)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:save_lead!).and_wrap_original do |original, *args|
      lead = original.call(*args)
      unless Thread.current[:prospecting_first_lead_saved]
        Thread.current[:prospecting_first_lead_saved] = true
        wait.call
      end
      lead
    end
    # rubocop:enable RSpec/AnyInstance

    errors = Queue.new
    %w[pizzaria restaurante].each do |query|
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.new(account: account, user: user, params: { query: query, location: 'Curitiba, PR', requested_limit: 2 }).perform
        rescue StandardError => e
          errors << "#{query}: #{e.class}: #{e.message.lines.first}"
        end
      end
    end
    workers.each { |worker| expect(worker.join(20)).to eq(worker) }

    expect(Array.new(errors.size) { errors.pop }).to eq([])
    statuses = Autonomia::Prospecting::Search.where(account_id: account.id).order(:query).pluck(:query, :status)
    expect(statuses).to eq([%w[pizzaria completed], %w[restaurante completed]])
    expect(Autonomia::Prospecting::Lead.where(account_id: account.id).count).to eq(2)
  end
end
