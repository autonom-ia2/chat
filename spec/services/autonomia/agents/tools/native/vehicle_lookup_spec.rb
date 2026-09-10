require 'rails_helper'

# A CONSULTA DE PLACA como ferramenta do especialista — entrega 2, termo 5.
RSpec.describe Autonomia::Agents::Tools::Native::VehicleLookup do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end

  before { enable_test_encryption! }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection(com_schema: true)
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    metadata = com_schema ? { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } } : {}
    record.update!(status: 'ready', metadata: metadata)
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def consultar(placa)
    described_class.new(agent: agent, params: { 'placa' => placa }).call
  end

  it 'e sincrona, reservada ao especialista de cotacao, e so aparece com conexao pronta' do
    expect(described_class.async?).to be(false)
    expect(Autonomia::Agents::Tools::Registry.find('consultar_placa')).to eq(described_class)
    expect(Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_ESPECIALISTA).to include('consultar_placa')
    expect(described_class.available_for?(agent)).to be(false)
    ready_connection
    expect(described_class.available_for?(agent)).to be(true)
  end

  it 'devolve modelo, ano e tipo com o rotulo do schema, e manda escrever o tipo na cotacao' do
    ready_connection

    texto = consultar('ncd-3080')

    expect(texto).to include('NCD3080', 'CG 150 Titan', 'moto', '2004')
    expect(texto).to include('`vehicle.vehicleType` = m')
  end

  it 'placa que o portal nao conhece volta sem tipo, e sem instrucao de tipo' do
    ready_connection

    texto = consultar('ZZZ9Z99')

    expect(texto).to include('ZZZ9Z99', 'modelo não informado')
    expect(texto).not_to include('vehicleType')
  end

  it 'placa fora do formato e placa vazia sao recusadas sem tocar o portal' do
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:vehicle_lookup).and_call_original

    expect(consultar('')).to eq(described_class::PLACA_INVALIDA)
    expect(consultar('ABC')).to eq(described_class::PLACA_INVALIDA)
    expect(connector).to have_received(:vehicle_lookup).once # só a fora do formato chega ao conector, que a recusa
  end

  it 'portal mudo nao derruba o turno: diz que a cotacao consulta de novo' do
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:vehicle_lookup).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'mudo'))

    expect(consultar('ABC1D23')).to eq(described_class::INDISPONIVEL)
  end
end
