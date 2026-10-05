require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::LimiteDaBusca do
  let(:conta) { create(:account) }
  let(:outra_conta) { create(:account) }
  let(:agente) { create(:user, account: conta, role: :agent) }
  let(:colega) { create(:user, account: conta, role: :agent) }

  around do |exemplo|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    exemplo.run
  ensure
    Rails.cache = original
  end

  def limite(usuario = agente, account: conta)
    described_class.new(account: account, account_user: account.account_users.find_by(user: usuario))
  end

  it 'deixa passar até o teto por pessoa no minuto e barra o seguinte' do
    stub_const("#{described_class}::POR_PESSOA_POR_MINUTO", 2)

    expect(Array.new(3) { limite.permitir? }).to eq([true, true, false])
    expect(limite(colega).permitir?).to be(true)
  end

  it 'libera de novo no minuto seguinte' do
    stub_const("#{described_class}::POR_PESSOA_POR_MINUTO", 1)
    limite.permitir?

    travel(1.minute) { expect(limite.permitir?).to be(true) }
  end

  it 'barra a conta inteira quando ela passa do teto do dia, sem tocar nas outras contas' do
    stub_const("#{described_class}::POR_CONTA_POR_DIA", 2)
    create(:account_user, account: outra_conta, user: agente)

    expect([limite.permitir?, limite(colega).permitir?, limite(colega).permitir?]).to eq([true, true, false])
    expect(limite(account: outra_conta).permitir?).to be(true)
  end

  it 'não bloqueia quando o cache não conta (cache desligado)' do
    Rails.cache = ActiveSupport::Cache::NullStore.new

    expect(limite.permitir?).to be(true)
  end
end
