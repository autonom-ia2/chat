require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::CampaignDeliveryLock do
  self.use_transactional_tests = false

  # No rows needed. Assert distinct server sessions, not just Ruby connection objects.
  it 'excludes a competing worker and releases campaign ownership after an exception' do
    acquired = Queue.new
    release = Queue.new
    key = SecureRandom.random_number(2**50)
    worker = Thread.new do
      described_class.synchronize(key) do
        acquired << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
        release.pop
        raise 'synthetic worker failure'
      end
    rescue RuntimeError => e
      e.message
    end
    begin
      pid = Timeout.timeout(5) { acquired.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      entered = false
      expect(described_class.synchronize(key) { entered = true }).to be(false)
      expect(entered).to be(false)
    ensure
      release << true
      worker.join(5) || worker.kill.join
    end
    expect(worker.value).to eq('synthetic worker failure')
    expect(described_class.synchronize(key) { :released }).to eq(:released)
  end

  it 'rejects nested ownership of the same campaign without unlocking the outer owner' do
    key = SecureRandom.random_number(2**50)
    described_class.synchronize(key) do
      expect(described_class.synchronize(key) { raise 'duplicate worker' }).to be(false)
      expect(Thread.new { described_class.synchronize(key) { :duplicate } }.value).to be(false)
    end
    expect(described_class.synchronize(key) { :released }).to eq(:released)
  end
end
