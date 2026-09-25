require 'rails_helper'
require 'timeout'

# Dois leads da mesma empresa ao mesmo tempo, em duas conexões de verdade, sem a transação do teste por fora (#680).
# As duas procuras erram juntas (a barreira segura cada uma depois da busca), as duas tentam criar, e o índice único
# por conta e CNPJ faz a segunda cair no RecordNotUnique e reaproveitar a primeira.
RSpec.describe Autonomia::Prospecting::CompanyUpserter do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let(:workers) { [] }
  let(:leads) do
    %w[a b].map do |suffix|
      Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{suffix}",
                                           name: "Alpha #{suffix}", enriched_cnpj: cnpj, website: website)
    end
  end
  let(:cnpj) { '11222333000181' }
  let(:website) { nil }

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    Autonomia::Prospecting::Lead.where(account_id: account.id).delete_all
    Company.where(account_id: account.id).delete_all
    account.destroy!
  end

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

  # Cada procura espera a outra chegar: as duas erram juntas e as duas tentam criar.
  def hold_after_find(parties)
    wait = barrier(parties, 3)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:find_existing).and_wrap_original do |original, *args|
      found = original.call(*args)
      unless Thread.current[:prospecting_company_waited]
        Thread.current[:prospecting_company_waited] = true
        wait.call
      end
      found
    end
    # rubocop:enable RSpec/AnyInstance
  end

  def race(targets)
    hold_after_find(targets.size)
    results = Queue.new
    targets.each do |lead|
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { results << described_class.new(lead: lead).perform }
      rescue StandardError => e
        results << e
      end
    end
    Timeout.timeout(10) { workers.each(&:join) }
    Array.new(targets.size) { results.pop }
  end

  it 'dois leads com o mesmo CNPJ ao mesmo tempo criam uma empresa só' do
    outcomes = race(leads)

    expect(outcomes).to all(be_a(described_class::Result))
    expect(outcomes.map(&:company).map(&:id).uniq.size).to eq(1)
    expect(outcomes.map(&:created)).to contain_exactly(true, false)
    expect(Company.where(account_id: account.id).count).to eq(1)
  end

  context 'without CNPJ (pelo domínio do site)' do
    let(:cnpj) { nil }
    let(:website) { 'https://alpha.com.br' }

    it 'dois leads com o mesmo site ao mesmo tempo criam uma empresa só' do
      outcomes = race(leads)

      expect(outcomes).to all(be_a(described_class::Result))
      expect(outcomes.map(&:company).map(&:id).uniq.size).to eq(1)
      expect(Company.where(account_id: account.id).count).to eq(1)
    end
  end
end
