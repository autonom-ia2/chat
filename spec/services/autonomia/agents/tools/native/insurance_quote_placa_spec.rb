require 'rails_helper'

# A COTAÇÃO CONSULTA A PLACA ANTES DE CONFERIR, e sem veículo não cota — entrega 2, termos 5 e 10.
#
# PROVA POR MUTAÇÃO: tirar o `merge` do tipo em `com_veiculo` reprova "o tipo vai para a
# conferência"; tirar a recusa `sem_veiculo` reprova "sem placa, chassi nem FIPE".
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

  def tool(params)
    described_class.new(agent: agent, params: params)
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

  it 'o tipo que o modelo já escreveu não é sobrescrito, e a placa não é consultada' do
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:vehicle_lookup).and_call_original

    entrada = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'NCD3080', 'vehicleType' => 'v' }).send(:entrada)

    expect(entrada['vehicle']['vehicleType']).to eq('v')
    expect(connector).not_to have_received(:vehicle_lookup)
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
