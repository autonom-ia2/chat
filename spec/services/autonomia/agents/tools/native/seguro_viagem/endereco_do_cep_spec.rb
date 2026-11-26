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

  describe 'cache vazio: a pronta de CEP do agente roda de verdade (ponta a ponta)' do
    before do
      resolver_hosts_das_prontas
      ligar_prontas(account)
      ligar_consultas(account)
    end

    it 'CEP achado: devolve cidade e UF, consulta o ViaCEP uma vez e guarda no cache' do
      incluir_pronta('cep', conta: account, agente: agent)
      viacep = fonte_responde('https://viacep.com.br/ws/01310100/json/',
                              { cep: '01310-100', logradouro: 'Avenida Paulista', bairro: 'Bela Vista',
                                localidade: 'São Paulo', uf: 'SP' })

      expect(described_class.buscar(agent: agent, cep: '01310-100')).to eq(completo)
      expect(described_class.buscar(agent: agent, cep: '01310100')).to eq(completo)
      expect(viacep).to have_been_requested.once
    end

    it 'CEP que nenhuma fonte conhece: nil, sem exceção' do
      incluir_pronta('cep', conta: account, agente: agent)
      fonte_responde('https://viacep.com.br/ws/01310100/json/', { erro: true })
      fonte_responde('https://cep.awesomeapi.com.br/json/01310100', { code: 'not_found' }, status: 404)
      fonte_responde('https://brasilapi.com.br/api/cep/v2/01310100', { name: 'CepPromiseError' }, status: 404)

      expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil
    end

    it 'todas as fontes fora (a pronta responde "não consegui"): nil, sem exceção e sem cache' do
      incluir_pronta('cep', conta: account, agente: agent)
      %w[https://viacep.com.br/ws/01310100/json/ https://cep.awesomeapi.com.br/json/01310100
         https://brasilapi.com.br/api/cep/v2/01310100].each { |url| fonte_fora(url) }

      expect { expect(described_class.buscar(agent: agent, cep: '01310100')).to be_nil }.not_to raise_error
    end
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
