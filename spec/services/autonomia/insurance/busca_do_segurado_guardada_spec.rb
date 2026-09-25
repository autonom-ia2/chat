require 'rails_helper'

# A BUSCA PAGA DO SEGURADO NÃO SE REPETE NA CONFERÊNCIA (decisão 4 do Rodrigo, 25/09/2026, chat#718).
#
# Pela conferência de verdade (`InsuranceQuote#precheck`, no turno de uma conversa): só o portal é dublado, e o que se
# conta é quantas vezes `quote_enrich`, a chamada paga, saiu. Auto, residencial e empresarial, cada um com o documento
# e sem o que a busca resolve.
RSpec.describe Autonomia::Insurance::BuscaDoSeguradoGuardada do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:connector) { Autonomia::Insurance::Connector.client }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:documento) { '04297912678' }
  let(:auto) { { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => documento, 'cep' => '31110-210' } }
  let(:residencial) do
    { 'produto' => 'residencial', 'cpf' => documento, 'cep' => '01310-100',
      'dados' => { 'configuracoes' => { 'imovelNumero' => '742', 'imovelTipoResidencia' => 3,
                                        'isDanosIncendioRaioExplosao' => 400_000 } }.to_json }
  end
  let(:empresarial) do
    { 'produto' => 'empresarial', 'cpf' => '11222333000181', 'cep' => '01310-100',
      'dados' => { 'configuracoes' => { 'imovelNumero' => '10' } }.to_json }
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_validate).and_return('valido' => true, 'problemas' => [])
    Redis::Alfred.scan_each(match: 'autonomia:busca_do_segurado:*') { |chave| Redis::Alfred.delete(chave) }
  end

  def turno(conversa = conversation)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil, origin_message_id: 1)
  end

  def conferir(params, delivery: turno)
    cotacao.new(agent: agent, params: { 'item' => 'Bem de teste' }.merge(params), delivery: delivery).precheck
  end

  { 'auto' => ['insured.birthDate', :auto], 'residencial' => ['segurado.nome', :residencial],
    'empresarial' => ['segurado.nome', :empresarial] }.each do |ramo, (campo, dados)|
    it "#{ramo}: a conferência repetida com os mesmos dados não paga a busca de novo, e recusa igual" do
      allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => [campo])

      primeira = conferir(public_send(dados))
      segunda = conferir(public_send(dados))

      expect(connector).to have_received(:quote_enrich).once
      expect([primeira.faltando, segunda.faltando]).to eq([[campo], [campo]])
      expect(segunda.to_s).to eq(primeira.to_s)
    end
  end

  it 'achou tudo: a segunda conferência também passa, sem pagar de novo' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => [])

    expect([conferir(auto), conferir(auto)]).to eq([nil, nil])
    expect(connector).to have_received(:quote_enrich).once
  end

  it 'outro documento é outra busca' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => ['insured.name'])

    conferir(auto)
    conferir(auto.merge('cpf' => '11144477735'))

    expect(connector).to have_received(:quote_enrich).twice
  end

  it 'um campo que o modelo passou a trazer é outra busca' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => ['insured.gender'])

    conferir(auto)
    conferir(auto.merge('insured' => { 'name' => 'A' }))

    expect(connector).to have_received(:quote_enrich).twice
  end

  it 'outra conversa é outra busca' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => ['insured.name'])

    conferir(auto)
    conferir(auto, delivery: turno(create(:conversation, account: account)))

    expect(connector).to have_received(:quote_enrich).twice
  end

  it 'a busca que falhou não fica guardada: a próxima conferência tenta de novo' do
    chamadas = 0
    allow(connector).to receive(:quote_enrich) do
      chamadas += 1
      raise Autonomia::Insurance::Connector::Error.new(:unavailable, 'fora') if chamadas == 1

      { 'input' => {}, 'not_found' => ['insured.name'] }
    end

    expect(conferir(auto)).to be_nil
    expect(conferir(auto).faltando).to eq(['insured.name'])
    expect(chamadas).to eq(2)
  end

  it 'sem conversa (Testar, playground), nada é guardado, como antes' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => ['insured.name'])

    2.times { conferir(auto, delivery: nil) }

    expect(connector).to have_received(:quote_enrich).twice
  end

  # LGPD: o que fica guardado são nomes de campo, e a chave não leva o documento.
  it 'guarda só nomes de campo, e a chave não leva o documento' do
    allow(connector).to receive(:quote_enrich)
      .and_return('input' => { 'insured' => { 'name' => 'FULANA DE TAL' } }, 'not_found' => ['insured.gender'])

    conferir(auto)

    chaves = []
    Redis::Alfred.scan_each(match: 'autonomia:busca_do_segurado:*') { |chave| chaves << chave }
    expect(chaves.size).to eq(1)
    expect(chaves.first).not_to include(documento)
    expect(chaves.first).to start_with("autonomia:busca_do_segurado:#{conversation.id}:")
    expect(JSON.parse(Redis::Alfred.get(chaves.first))).to eq(['insured.gender'])
  end
end
