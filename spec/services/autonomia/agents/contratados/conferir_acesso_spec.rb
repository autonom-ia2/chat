require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::ConferirAcesso do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:contratado) { Autonomia::Agents::Agent.create!(account: account, name: 'Contratado', agent_type: 'custom') }

  before do
    enable_test_encryption!
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: file_fixture('../universal/setup.json').read)
  end

  # #3211 (rodada 1): dois pedidos no primeiro cadastro. O outro grava a linha entre a nossa leitura e o nosso INSERT.
  it 'outro pedido gravou o primeiro acesso no meio: relê a linha e grava por cima, sem erro e sem chamar de novo' do
    primeiro = true
    allow(Autonomia::Agents::AcessoDaSeguradora).to receive(:find_or_initialize_by).and_wrap_original do |original, *args, **opcoes|
      registro = original.call(*args, **opcoes)
      next registro unless primeiro

      primeiro = false
      allow(registro).to receive(:save!) do
        Autonomia::Agents::AcessoDaSeguradora.create!(agent: contratado, account: account, login: 'outro.login', senha: 'outra')
        raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint'
      end
      registro
    end

    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call

    expect(Autonomia::Agents::AcessoDaSeguradora.where(autonomia_agent_id: contratado.id).count).to eq(1)
    expect(acesso.reload).to have_attributes(login: 'corretor.teste', estado: 'ok')
    expect(a_request(:get, "#{base}/v1/Emissor/Setup")).to have_been_made.once
  end

  it 'Setup ok grava ok e as capacidades nas nossas chaves, só booleanos' do
    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    expect(acesso.estado).to eq('ok')
    expect(acesso.conferido_em).to be_present
    expect(acesso.capacidades).to eq('tarifa_acordo' => true)
  end

  it 'não lê o soCotacao: todo login faz proposta' do
    setup = JSON.parse(file_fixture('../universal/setup.json').read).merge('soCotacao' => true)
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: setup.to_json)
    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    expect(acesso.capacidades.keys).to eq(['tarifa_acordo'])
  end

  it 'campo que não é booleano vira false' do
    setup = JSON.parse(file_fixture('../universal/setup.json').read).merge('tarifaAcordo' => 'true')
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: setup.to_json)
    acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    expect(acesso.capacidades['tarifa_acordo']).to be(false)
  end

  # A conferência que não deu certo não grava nada ("Nada foi guardado", na tela): sem acesso anterior, nenhuma linha.
  it '401 devolve recusado com o código e não grava nada' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    acesso = described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call

    expect(acesso).to have_attributes(estado: 'recusado', motivo: 'acesso_recusado', login: nil, senha: nil)
    expect(acesso).not_to be_persisted
    expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
  end

  it '400 no Setup não levanta, devolve pedido_invalido (R10) e não grava nada' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 400, body: '{"status":400,"message":"x"}')
    acesso = nil
    expect { acesso = described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call }.not_to raise_error
    expect(acesso).to have_attributes(estado: 'nao_conferido', motivo: 'pedido_invalido')
    expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
  end

  it 'Universal fora devolve nao_conferido com indisponivel e não grava nada' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_timeout
    expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call)
      .to have_attributes(estado: 'nao_conferido', motivo: 'indisponivel')
    expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
  end

  it 'conferir de novo depois de recusado grava o aceito, sem motivo' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
    described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 200, body: file_fixture('../universal/setup.json').read)
    expect(described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call)
      .to have_attributes(estado: 'ok', motivo: nil)
  end

  it 'trocar por outro login aceito grava por cima, sem segunda linha' do
    described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
    acesso = described_class.new(agent: contratado, login: 'outro.corretor', senha: 'outra-s3nha').call

    expect(Autonomia::Agents::AcessoDaSeguradora.where(autonomia_agent_id: contratado.id).count).to eq(1)
    expect(acesso.reload).to have_attributes(login: 'outro.corretor', senha: 'outra-s3nha', login_dica: 'ou•••or', estado: 'ok')
  end

  # O acesso que funciona não cai por uma tentativa errada: login, senha, estado, capacidades e data ficam.
  [['recusado (401)', ->(pedido) { pedido.to_return(status: 401) }, 'recusado', 'acesso_recusado'],
   ['sem resposta', ->(pedido) { pedido.to_timeout }, 'nao_conferido', 'indisponivel'],
   ['pedido que a Universal não aceitou (400)', ->(pedido) { pedido.to_return(status: 400, body: '{"status":400}') },
    'nao_conferido', 'pedido_invalido']].each do |caso, resposta, estado, motivo|
    it "#{caso} depois de ok mantém o acesso que funciona e devolve só o resultado da tentativa" do
      gravado = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
      antes = gravado.reload.attributes.except('updated_at')
      resposta.call(stub_request(:get, "#{base}/v1/Emissor/Setup"))

      tentativa = described_class.new(agent: contratado, login: 'outro.corretor', senha: 'y').call

      expect(tentativa).to have_attributes(estado: estado, motivo: motivo, login: nil, senha: nil)
      expect(tentativa).not_to be_persisted
      expect(gravado.reload.attributes.except('updated_at')).to eq(antes)
      expect(gravado).to have_attributes(login: 'corretor.teste', senha: 's3nha-teste', estado: 'ok',
                                         tarifa_acordo?: true)
    end
  end

  it 'queda de conexão no meio não levanta nem grava' do
    stub_request(:get, "#{base}/v1/Emissor/Setup").to_raise(Errno::ECONNRESET)
    expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call)
      .to have_attributes(estado: 'nao_conferido', motivo: 'indisponivel')
    expect(Autonomia::Agents::AcessoDaSeguradora.count).to eq(0)
  end
end
