require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep do
  let(:fonte) { Autonomia::FerramentasProntas::Fontes::Cep::FONTE }
  let(:account) { create(:account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato') }
  let(:consulta) { fonte.consulta('endereco') }
  let(:completo) do
    { 'cep' => '01310-100', 'logradouro' => 'Avenida Paulista', 'bairro' => 'Bela Vista', 'cidade' => 'São Paulo', 'uf' => 'SP' }
  end

  around do |exemplo|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      exemplo.run
    ensure
      Rails.cache = original
    end
  end

  def guardar(dados)
    params, = consulta.conferir({ 'cep' => '01310100' })
    cache = Autonomia::FerramentasProntas::Cache.new(fonte, consulta, params)
    dados.nil? ? cache.nao_encontrado : cache.encontrado(dados)
  end

  it 'cache cheio: devolve o endereço sem chamar provedor nem a pronta' do
    guardar(completo)
    expect(Autonomia::FerramentasProntas::Execucao).not_to receive(:new)
    expect(described_class.buscar(agent: agent, cep: '01310-100')).to eq(completo)
  end

  it 'cache vazio: roda a pronta do agente uma vez e lê o cache de novo' do
    pronta = instance_double(Autonomia::Agents::Tool)
    relacao = double('tools') # rubocop:disable RSpec/VerifiedDoubles
    allow(agent).to receive(:tools).and_return(relacao)
    allow(relacao).to receive(:find_by).with(fonte_pronta: 'cep').and_return(pronta)
    execucao = instance_double(Autonomia::FerramentasProntas::Execucao)
    expect(Autonomia::FerramentasProntas::Execucao).to receive(:new)
      .with(tool: pronta, params: hash_including('consulta' => 'endereco', 'cep' => anything)).once.and_return(execucao)
    expect(execucao).to receive(:call).once.and_invoke(-> { guardar(completo) })
    expect(described_class.buscar(agent: agent, cep: '01310100')).to eq(completo)
  end

  it 'CEP de cidade com CEP único vem sem logradouro e sem bairro' do
    guardar(completo.merge('logradouro' => nil, 'bairro' => nil))
    expect(described_class.buscar(agent: agent, cep: '01310100'))
      .to eq('cep' => '01310-100', 'cidade' => 'São Paulo', 'uf' => 'SP')
  end

  it 'sem cidade ou sem UF: nil, como CEP não achado (a compra nunca vai com Cidade/UF nulas)' do
    guardar(completo.merge('cidade' => nil))
    expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil
    guardar(completo.merge('uf' => ''))
    expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil
  end

  it 'CEP com 7 dígitos: nil, sem consultar' do
    expect(Autonomia::FerramentasProntas::Execucao).not_to receive(:new)
    expect(described_class.buscar(agent: agent, cep: '0131010')).to be_nil
  end

  it 'nao_encontrado: nil' do
    guardar(nil)
    expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil
  end

  it 'sem a pronta de CEP no agente e cache vazio: nil' do
    expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil
  end
end
