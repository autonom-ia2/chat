require 'rails_helper'

# A COTAÇÃO CONSULTA A PLACA ANTES DE CONFERIR, e sem veículo não cota — entrega 2, termos 5 e 10.
#
# PROVA POR MUTAÇÃO: tirar o `merge` do tipo em `com_veiculo` reprova "o tipo vai para a
# conferência"; inverter o merge reprova "o que o portal diz vence"; trocar a sessão viva pela
# fresca no turno reprova "não abre login"; tirar a recusa `sem_veiculo` reprova "sem placa, chassi
# nem FIPE"; tirar a `formulario_indisponivel` reprova "auto sem formulário".
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end

  before { enable_test_encryption! }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  # Sem `delivery` é a instância do JOB (`AsyncRunJob#advance`); com `delivery` é a do TURNO
  # (`Bound#accept_async`). É por isso que a ferramenta sabe onde está.
  def tool(params)
    described_class.new(agent: agent, params: params)
  end

  def tool_no_turno(params)
    described_class.new(agent: agent, params: params, delivery: instance_double(Autonomia::Agents::Tools::Delivery))
  end

  def conector_real
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    connector
  end

  it 'o tipo que a consulta de placa devolveu vai para a conferência, sem o modelo pedir' do
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_validate).and_call_original

    tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210', 'vehicle' => { 'plate' => 'NCD3080' }).precheck

    expect(connector).to have_received(:quote_validate) do |**kwargs|
      expect(kwargs[:input]['vehicle']).to include('plate' => 'NCD3080', 'vehicleType' => 'm', 'modelYear' => 2004)
    end
  end

  it 'a placa é consultada mesmo com o tipo escrito pelo modelo, e o que o portal diz vence' do
    ready_connection
    connector = conector_real
    allow(connector).to receive(:vehicle_lookup).and_call_original

    entrada = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'NCD3080', 'vehicleType' => 'v', 'modelYear' => 2010 })
              .send(:entrada)

    expect(entrada['vehicle']).to include('plate' => 'NCD3080', 'vehicleType' => 'm', 'modelYear' => 2004)
    expect(connector).to have_received(:vehicle_lookup).once
  end

  it 'no turno só consulta com a sessão que já está viva: sem ela não abre login e segue sem o tipo' do
    ready_connection.forget_session!
    connector = conector_real
    allow(connector).to receive(:open_session).and_call_original
    allow(connector).to receive(:vehicle_lookup).and_call_original

    entrada = tool_no_turno('produto' => 'auto', 'vehicle' => { 'plate' => 'NCD3080' }).send(:entrada)

    expect(entrada['vehicle']).to eq('plate' => 'NCD3080')
    expect(connector).not_to have_received(:open_session)
    expect(connector).not_to have_received(:vehicle_lookup)
  end

  it 'no envio (job) abre a sessão se for preciso: a consulta acontece' do
    ready_connection.forget_session!
    connector = conector_real
    allow(connector).to receive(:open_session).and_call_original

    entrada = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'NCD3080' }).send(:entrada)

    expect(entrada['vehicle']).to include('vehicleType' => 'm')
    expect(connector).to have_received(:open_session).once
  end

  it 'consulta de placa fora do ar não barra: a entrada segue sem o tipo' do
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:vehicle_lookup).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'mudo'))

    entrada = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }).send(:entrada)

    expect(entrada['vehicle']).to eq('plate' => 'ABC1D23')
  end

  it 'sem placa, chassi nem FIPE recusa antes de conferir, no turno e no envio' do
    ready_connection

    conferencia = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210').precheck
    envio = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210').start

    expect(conferencia.motivo).to eq('sem_veiculo')
    expect(conferencia.to_s).to include('encaminhe para um atendente')
    expect(conferencia.faltando).to eq(['vehicle.plate'])
    expect(envio['motivo']).to eq('sem_veiculo')
    expect(envio['pedido']).to eq(described_class::SEM_VEICULO_CLIENTE)
  end

  it 'auto sem formulário na conexão e adapter mudo recusa por indisponibilidade, sem cobrar placa do cliente' do
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(conector_real).to receive(:quote_schema).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, 'mudo'))

    conferencia = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210').precheck
    envio = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210').start

    expect(conferencia.motivo).to eq('formulario_indisponivel')
    expect(conferencia.to_s).to include('encaminhe para um atendente')
    expect(conferencia.to_s).not_to include('placa')
    expect(conferencia.faltando).to eq([])
    expect(envio['motivo']).to eq('formulario_indisponivel')
    expect(envio['pedido']).to eq(described_class::FALHOU)
    expect(record.reload.quote_schema('auto')).to be_nil
  end

  it 'auto sem formulário guardado busca no adapter, guarda na conexão e segue' do
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)

    conferencia = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210').precheck

    expect(conferencia.motivo).to eq('sem_veiculo')
    expect(record.reload.quote_schema('auto')).to include('campos')
  end

  # ZERO-QUILÔMETRO AMBÍGUO (entrega 3): modelo do ano sem `isZeroKm` não cota — cotado assim sairia
  # como usado. Modelo de ano anterior é usado e ninguém pergunta; `isZeroKm` escrito (true ou false)
  # resolve.
  it 'modelo do ano sem dizer se é zero-quilômetro: pergunta antes de cotar, no turno e no envio' do
    ready_connection
    base = { 'produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210' }

    conferencia = tool(base.merge('vehicle' => { 'plate' => 'ZER0K26' })).precheck
    envio = tool(base.merge('vehicle' => { 'plate' => 'ZER0K26' })).start
    resolvido = tool(base.merge('vehicle' => { 'plate' => 'ZER0K26', 'isZeroKm' => false })).precheck
    usado = tool(base.merge('vehicle' => { 'plate' => 'HIK9383' })).precheck

    expect(conferencia.motivo).to eq('faltam_dados')
    expect(conferencia.to_s).to include(Date.current.year.to_s, 'zero-quilômetro', 'vehicle.isZeroKm —')
    expect(conferencia.faltando).to eq(['vehicle.isZeroKm'])
    expect(envio['motivo']).to eq('faltam_dados')
    expect(envio['pedido']).to include('se o veículo é zero-quilômetro')
    expect(resolvido).to be_nil
    expect(usado).to be_nil
  end

  it 'chassi ou FIPE identificam o veículo tanto quanto a placa' do
    ready_connection

    expect(tool('produto' => 'auto', 'vehicle' => { 'chassis' => '9BGAB69W08B286692' }).send(:sem_veiculo?)).to be(false)
    expect(tool('produto' => 'auto', 'vehicle' => { 'fipeCode' => '0043249' }).send(:sem_veiculo?)).to be(false)
    expect(tool('produto' => 'bike', 'dados' => '{}').send(:sem_veiculo?)).to be(false)
  end

  it 'a conferência fala ao modelo pelo nome do campo e pelo motivo do adapter' do
    ready_connection

    conferencia = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }).precheck

    expect(conferencia.motivo).to eq('faltam_dados')
    expect(conferencia.to_s).to include('Antes de cotar', 'insured.document —')
  end
end
