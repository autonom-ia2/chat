require 'rails_helper'

# #3211 — as ferramentas do Seguro Viagem Universal só chegam ao contratado com o acesso à seguradora conferido.
# O nome do arquivo é o da Tarefa 19; o assunto é o Registry.
RSpec.describe Autonomia::Agents::Tools::Registry do # rubocop:disable RSpec/SpecFilePathFormat
  let(:slugs) do
    %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem situacao_do_pagamento segunda_via_do_voucher]
  end
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end

  before do
    enable_test_encryption!
    # As ferramentas chegam com o modelo disponível no turno: a flag, as prontas e a chave de IA da própria conta.
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
  end

  def acesso_ok!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
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

  it 'contratado com acesso ok recebe todas (#3246: com a situação do pagamento e a segunda via)' do
    acesso_ok!
    expect(described_class.for_agent(contratado).map(&:slug)).to eq(slugs)
  end

  it 'modelo desligado na conta: nenhuma, mesmo com o acesso ok' do
    acesso_ok!
    account.disable_features!('agente_seguro_viagem_universal')
    expect(described_class.for_agent(contratado.reload).map(&:slug)).to eq([])
  end

  it 'conta sem a própria chave de IA: nenhuma, mesmo com a da instalação' do
    acesso_ok!
    Integrations::Hook.where(account_id: account.id, app_id: 'crm_kanban_ai').delete_all
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')
    expect(described_class.for_agent(contratado.reload).map(&:slug)).to eq([])
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
