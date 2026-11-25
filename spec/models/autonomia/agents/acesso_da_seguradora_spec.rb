require 'rails_helper'

RSpec.describe Autonomia::Agents::AcessoDaSeguradora do
  let(:account) { create(:account) }
  let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom') }

  before { enable_test_encryption! }

  it 'guarda login e senha cifrados' do
    acesso = described_class.create!(account: account, agent: agente, login: 'corretor.teste', senha: 's3nha-teste')
    cru = ActiveRecord::Base.connection.select_one("SELECT login, senha FROM autonomia_acessos_da_seguradora WHERE id = #{acesso.id}")
    expect(cru['login']).not_to include('corretor.teste')
    expect(cru['senha']).not_to include('s3nha-teste')
  end

  it 'dica do login: dois primeiros, três pontos, dois últimos' do
    expect(described_class.new(login: 'corretor.teste').tap(&:valid?).login_dica).to eq('co•••te')
    expect(described_class.new(login: 'abcd').tap(&:valid?).login_dica).to eq('•••')
  end

  it 'payload público nunca tem login nem senha' do
    acesso = described_class.create!(account: account, agent: agente, login: 'corretor.teste', senha: 's3nha-teste')
    payload = acesso.payload_publico
    expect(payload.keys).to contain_exactly(:seguradora, :login_dica, :estado, :motivo, :conferido_em)
    expect(payload.to_json).not_to include('s3nha-teste', 'corretor.teste')
  end

  it 'recusa gravar sem cofre configurado' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    expect { described_class.create!(account: account, agent: agente, login: 'x1', senha: 'y1') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'um por agente' do
    described_class.create!(account: account, agent: agente, login: 'a1b2c3', senha: 'x')
    expect { described_class.create!(account: account, agent: agente, login: 'd4e5f6', senha: 'y') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'motivo só com os códigos da Universal' do
    expect(described_class.new(account: account, agent: agente, motivo: 'qualquer')).not_to be_valid
    expect(described_class.new(account: account, agent: agente, motivo: 'pedido_invalido')).to be_valid
  end

  it 'tarifa de acordo pela nossa chave' do
    expect(described_class.new(capacidades: { 'tarifa_acordo' => true }).tarifa_acordo?).to be(true)
    expect(described_class.new(capacidades: {}).tarifa_acordo?).to be(false)
  end
end
