require 'rails_helper'

# #3211 — as três ferramentas do Seguro Viagem Universal só chegam ao contratado com o acesso à seguradora conferido.
# O nome do arquivo é o da Tarefa 19; o assunto é o Registry.
RSpec.describe Autonomia::Agents::Tools::Registry do # rubocop:disable RSpec/SpecFilePathFormat
  let(:slugs) { %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem] }
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end

  before { enable_test_encryption! }

  def acesso_ok!(capacidades: {})
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok', capacidades: capacidades)
  end

  it 'agente comum com os slugs gravados não recebe nenhuma' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr',
                                             config: { 'native_tool_slugs' => slugs })
    expect(described_class.for_agent(comum).map(&:slug)).to eq([])
  end

  it 'contratado sem acesso ok não recebe nenhuma' do
    expect(described_class.for_agent(contratado).map(&:slug)).to eq([])
  end

  it 'contratado com acesso ainda não conferido não recebe nenhuma' do
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'nao_conferido')
    expect(described_class.for_agent(contratado).map(&:slug)).to eq([])
  end

  it 'contratado com acesso ok recebe as três' do
    acesso_ok!
    expect(described_class.for_agent(contratado).map(&:slug)).to eq(slugs)
  end

  it 'login que só cota: sem proposta' do
    acesso_ok!(capacidades: { 'so_cotacao' => true })
    expect(described_class.for_agent(contratado).map(&:slug)).to eq(slugs.first(2))
  end

  it 'não aparecem no catálogo que a API aceita para agente comum' do
    comum = Autonomia::Agents::Agent.new(account: account, agent_type: 'sdr', config: {})
    expect(described_class.permitidas_para(comum).map(&:slug) & slugs).to eq([])
  end

  it 'a porta é segura para agente sem acesso e para objeto que não é agente' do
    ferramenta = Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem
    expect(ferramenta.available_for?(contratado)).to be(false)
    expect(ferramenta.available_for?(nil)).to be(false)
    expect(ferramenta.available_for?(Object.new)).to be(false)
  end

  it 'schema strict aceito: required lista todas as chaves' do
    schema = Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem.openai_schema(contratado)
    expect(schema[:parameters][:required]).to eq(%w[codigo_do_plano titular demais_viajantes contato_de_emergencia])
  end
end
