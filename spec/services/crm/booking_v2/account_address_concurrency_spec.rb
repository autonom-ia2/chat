require 'rails_helper'

# Concorrência real do endereço da conta (#1299), com duas conexões de banco. As duas chamadas param DEPOIS de
# escolher o nome e ANTES de gravar, então as duas tentam gravar a mesma coisa: quem decide é o índice único.
# - mesma conta: uma linha só, e as duas chamadas devolvem o mesmo endereço;
# - duas contas com o mesmo nome: cada uma fica com um endereço diferente, sem exceção.
RSpec.describe Crm::BookingV2::AccountAddress, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: apaga, no fim, tudo o que o teste criou.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account, name: 'Corrida Endereço') }
  let!(:other_account) { create(:account, name: 'Corrida Endereço') }
  let(:barrier) { Concurrent::CyclicBarrier.new(2) }
  # O que cada tentativa de gravar devolveu: o endereço, ou nil para quem perdeu a disputa e tentou de novo.
  let(:attempts) { Concurrent::Array.new }

  before do
    gate = barrier
    waited = Concurrent::Map.new
    allow(described_class).to receive(:suggest).and_wrap_original do |original, *args|
      name = original.call(*args)
      # Só a primeira sugestão de cada thread espera a outra; a nova tentativa segue direto.
      gate.wait(5) if waited.put_if_absent(Thread.current, true).nil?
      name
    end
    log = attempts
    allow(described_class).to receive(:create).and_wrap_original do |original, *args|
      original.call(*args).tap { |name| log << name }
    end
  end

  after do
    Crm::BookingAccountAddress.where(account_id: [account.id, other_account.id]).delete_all
    [account, other_account].each { |item| item.reload.destroy! }
    Audited::Audit.where('id > ?', audit_floor).delete_all
  end

  def addresses
    Crm::BookingAccountAddress.where(account_id: [account.id, other_account.id]).order(:account_id).pluck(:account_id, :name)
  end

  # Roda as chamadas ao mesmo tempo, cada uma na própria conexão; devolve o resultado (ou a exceção) de cada uma.
  def together(*accounts)
    threads = accounts.map do |item|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { described_class.ensure!(item) }
      rescue StandardError => e
        e
      end
    end
    threads.map { |thread| thread.join(15)&.value }
  end

  it 'duas chamadas ao mesmo tempo para a mesma conta: uma linha só e a mesma resposta' do
    expect(together(account, account)).to eq(%w[corrida-endereco corrida-endereco])
    expect(addresses).to eq([[account.id, 'corrida-endereco']])
    expect(barrier).not_to be_broken
    # As duas tentaram gravar; uma perdeu e releu o endereço da outra.
    expect(attempts).to contain_exactly('corrida-endereco', nil)
  end

  it 'duas contas com o mesmo nome ao mesmo tempo: endereços diferentes, sem exceção' do
    results = together(account, other_account)

    expect(results).to contain_exactly('corrida-endereco', 'corrida-endereco-2')
    expect(addresses.map(&:last)).to match_array(results)
    expect(addresses.map(&:first)).to eq([account.id, other_account.id])
    expect(barrier).not_to be_broken
    # As duas tentaram o mesmo nome; quem perdeu tentou de novo com o próximo número.
    expect(attempts).to contain_exactly('corrida-endereco', nil, 'corrida-endereco-2')
  end

  it 'dentro de uma transação de quem chamou, a disputa perdida não envenena a transação' do
    Crm::BookingAccountAddress.create!(account_id: other_account.id, name: 'corrida-endereco')
    # Sem esperar outra thread aqui. Na primeira volta a sugestão e a validação ainda não veem o nome que a outra
    # conta pegou: a gravação bate no índice único. Na segunda volta já veem, e sai o próximo número.
    allow(described_class).to receive(:suggest).and_call_original
    allow(described_class).to receive(:taken?).and_return(false, false, true, false, false)

    name = Account.transaction do
      found = described_class.ensure!(account)
      expect(Account.where(id: account.id).pick(:name)).to eq('Corrida Endereço')
      found
    end

    expect(name).to eq('corrida-endereco-2')
    # A primeira tentativa bateu no índice único dentro da transação de quem chamou; a segunda gravou.
    expect(attempts).to eq([nil, 'corrida-endereco-2'])
    expect(addresses).to eq([[account.id, 'corrida-endereco-2'], [other_account.id, 'corrida-endereco']])
  end
end
