require 'rails_helper'

# Endereço da conta no link de agendamento (#1299): o `<conta>` de `/a/<conta>/<página>`. Um por conta, único na
# instalação, criado sozinho a partir do nome da conta, e nunca igual ao nome de página de outra conta (para não
# passar na frente do link antigo `/a/<página>` dela).
RSpec.describe Crm::BookingV2::AccountAddress do
  let(:account) { create(:account, name: 'Hub2You') }
  let(:other_account) { create(:account, name: 'Hub2You') }

  def addresses
    Crm::BookingAccountAddress.order(:id).pluck(:account_id, :name)
  end

  describe '.ensure!' do
    it 'cria o endereço a partir do nome da conta, uma vez só' do
      expect(described_class.name_for(account)).to be_nil

      expect(described_class.ensure!(account)).to eq('hub2you')
      expect(described_class.ensure!(account)).to eq('hub2you')
      expect(addresses).to eq([[account.id, 'hub2you']])
    end

    it 'não muda o endereço quando a conta troca de nome' do
      described_class.ensure!(account)
      account.update!(name: 'Outro Nome')

      expect(described_class.ensure!(account)).to eq('hub2you')
    end

    it 'soma número quando outra conta já tem o endereço' do
      described_class.ensure!(other_account)

      expect(described_class.ensure!(account)).to eq('hub2you-2')
    end

    it 'tira acento, espaço e pontuação do nome da conta' do
      account.update!(name: '  Clínica São João & Cia_Ltda  ')

      expect(described_class.ensure!(account)).to eq('clinica-sao-joao-cia-ltda')
    end

    it 'não usa nome do sistema, curto demais ou que some inteiro: ganha "agenda" na frente' do
      { 'Admin' => 'agenda-admin', 'Book' => 'agenda-book', 'Eu' => 'agenda-eu', '日本語' => 'agenda', '!!!' => 'agenda-2' }.each do |name, expected|
        expect(described_class.ensure!(create(:account, name: name))).to eq(expected), name.inspect
      end
    end

    it 'respeita os 40 caracteres, sem hífen na ponta' do
      account.update!(name: "#{'a' * 39} bcd")
      other_account.update!(name: "#{'a' * 39} bcd")

      expect(described_class.ensure!(account)).to eq('a' * 39)
      expect(described_class.ensure!(other_account)).to eq("#{'a' * 38}-2")
    end

    it 'não pega o nome de página de OUTRA conta, mas pode ser igual ao nome de uma página da própria conta' do
      build_booking_world(account: other_account).profile.update!(short_name: 'hub2you')
      expect(described_class.ensure!(account)).to eq('hub2you-2')

      expect(described_class.ensure!(other_account)).to eq('hub2you')
    end

    it 'quando duas criações se cruzam, a segunda encontra o endereço que a primeira gravou' do
      calls = 0
      allow(described_class).to receive(:name_for).and_wrap_original do |original, *args|
        calls += 1
        # A primeira consulta não vê nada; antes de gravar, "outra requisição" grava o endereço da mesma conta.
        Crm::BookingAccountAddress.create!(account_id: account.id, name: 'hub2you') if calls == 1
        calls == 1 ? nil : original.call(*args)
      end

      expect(described_class.ensure!(account)).to eq('hub2you')
      expect(addresses).to eq([[account.id, 'hub2you']])
    end
  end

  describe '.find_account' do
    it 'acha a conta pelo endereço, sem ligar para maiúsculas, e nada para o resto' do
      described_class.ensure!(account)

      expect(described_class.find_account('hub2you')).to eq(account)
      expect(described_class.find_account(' Hub2You ')).to eq(account)
      [nil, '', 'outra', 'ab', 'hub 2 you', 'admin'].each { |name| expect(described_class.find_account(name)).to be_nil, name.inspect }
    end
  end

  describe 'no banco e no modelo' do
    it 'recusa endereço mal formado, do sistema e o que já tem dono' do
      described_class.ensure!(other_account)

      { 'ab' => 'too_short', 'clínica' => 'invalid_chars', 'admin' => 'reserved', 'hub2you' => 'taken' }.each do |name, problem|
        address = Crm::BookingAccountAddress.new(account: account, name: name)
        expect(address).not_to be_valid, name
        expect(address.errors[:name]).to eq([problem])
      end
    end

    it 'tem índices únicos: um endereço por conta e um dono por endereço, mesmo pulando a validação' do
      described_class.ensure!(account)
      insert = lambda do |account_id, name|
        Crm::BookingAccountAddress.transaction(requires_new: true) do
          Crm::BookingAccountAddress.insert_all!([{ account_id: account_id, name: name }]) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      expect { insert.call(account.id, 'outro-nome') }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert.call(other_account.id, 'hub2you') }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(addresses).to eq([[account.id, 'hub2you']])
    end

    it 'some junto com a conta' do
      described_class.ensure!(account)

      account.delete

      expect(Crm::BookingAccountAddress.count).to eq(0)
    end
  end
end
