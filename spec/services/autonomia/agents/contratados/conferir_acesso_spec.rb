require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::ConferirAcesso do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:contratado) { Autonomia::Agents::Agent.create!(account: account, name: 'Contratado', agent_type: 'custom') }

  before do
    enable_test_encryption!
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: file_fixture('../universal/setup.json').read)
  end

  it 'Setup ok grava ok e as capacidades nas nossas chaves, só booleanos' do
    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    expect(acesso.estado).to eq('ok')
    expect(acesso.conferido_em).to be_present
    expect(acesso.capacidades).to eq('so_cotacao' => false, 'emite_faturado' => false, 'emite_boleto' => false,
                                     'tarifa_acordo' => true)
  end

  it 'login que só cota' do
    setup = JSON.parse(file_fixture('../universal/setup.json').read).merge('soCotacao' => true)
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: setup.to_json)
    expect(described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call.so_cotacao?).to be(true)
  end

  it 'campo que não é booleano vira false' do
    setup = JSON.parse(file_fixture('../universal/setup.json').read).merge('tarifaAcordo' => 'true')
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: setup.to_json)
    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    expect(acesso.capacidades['tarifa_acordo']).to be(false)
  end

  it '401 grava recusado com o código' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call)
      .to have_attributes(estado: 'recusado', motivo: 'acesso_recusado')
  end

  it '400 no Setup não levanta e grava pedido_invalido (R10)' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 400, body: '{"status":400,"message":"x"}')
    acesso = nil
    expect { acesso = described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call }.not_to raise_error
    expect(acesso).to have_attributes(estado: 'nao_conferido', motivo: 'pedido_invalido')
  end

  it 'Universal fora grava nao_conferido com indisponivel' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_timeout
    expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call)
      .to have_attributes(estado: 'nao_conferido', motivo: 'indisponivel')
  end

  it 'conferir de novo depois de recusado limpa o motivo' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: file_fixture('../universal/setup.json').read)
    expect(described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call)
      .to have_attributes(estado: 'ok', motivo: nil)
  end

  it 'trocar o login refaz a conferência e não cria segunda linha' do
    described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    acesso = described_class.new(agent: contratado, login: 'outro.corretor', senha: 'outra-senha').call
    expect(Autonomia::Agents::AcessoDaSeguradora.where(autonomia_agent_id: contratado.id).count).to eq(1)
    expect(acesso).to have_attributes(login: 'outro.corretor', login_dica: 'ou•••or', estado: 'recusado')
  end

  it 'recusado depois de ok zera as capacidades' do
    described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    acesso = described_class.new(agent: contratado, login: 'outro.corretor', senha: 'y').call
    expect(acesso.capacidades).to eq({})
    expect(acesso.so_cotacao?).to be(false)
    expect(acesso.tarifa_acordo?).to be(false)
  end

  it 'queda de conexão no meio não levanta' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_raise(Errno::ECONNRESET)
    expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call)
      .to have_attributes(estado: 'nao_conferido', motivo: 'indisponivel')
  end
end
