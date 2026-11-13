require 'rails_helper'

# #2881 — a marca do modelo pronto de ramo contra o save comum do agente. O painel e a API gravam o `config` inteiro
# que leram; se o dono mudou uma lista no meio (`ModelosDeRamo::Edicao`), a lista velha voltaria em silêncio. O save
# que não mexe na marca mantém o que está salvo; o que a muda de propósito segue mudando.
RSpec.describe Autonomia::Agents::MarcaDoModeloPronto do
  include ModelosDeRamoHelper

  let(:account) { create(:account) }
  let(:conversa) { conversa_com_modelo(account) }
  let(:chave_da_marca) { Autonomia::Agents::ModelosDeRamo::Marca::CHAVE }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr',
                                     config: conversa.state.slice(*described_class::CHAVES).merge('guardrails' => ['regra']))
  end

  around { |example| com_pacotes_ligados { example.run } }

  before do
    liberar_modelos(account)
    ligar_prontas_do_construtor(account)
  end

  def editar(mudancas)
    Autonomia::Agents::ModelosDeRamo::Edicao.new(agent: Autonomia::Agents::Agent.find(agente.id), mudancas: mudancas).call
  end

  it 'mantém a lista e as ferramentas que o dono mudou quando um save com a cópia velha grava o config inteiro' do
    copia_velha = Autonomia::Agents::Agent.find(agente.id)
    editar(documentos: [{ texto: 'Contrato social.' }], ferramentas: [{ fonte: 'cnpj' }])

    copia_velha.update!(config: copia_velha.config.merge('guardrails' => ['regra nova']))
    config = agente.reload.config

    expect(config[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
    expect(config[chave_da_marca]['ferramentas'].pluck('fonte')).to eq(%w[cnpj compras_governo])
    expect(config['ferramentas_sugeridas']).to eq(%w[cnpj])
    expect(config['guardrails']).to eq(['regra nova'])
  end

  it 'mantém a marca salva também quando o save muda outro campo junto com o config' do
    copia_velha = Autonomia::Agents::Agent.find(agente.id)
    editar(perguntas: [{ texto: 'A obra já começou?' }])

    copia_velha.update!(name: 'Assistente', config: copia_velha.config.merge('guardrails' => []))

    expect(agente.reload.name).to eq('Assistente')
    expect(agente.config[chave_da_marca]['perguntas'].pluck('texto')).to eq(['A obra já começou?'])
  end

  it 'deixa passar o save que muda a marca de propósito' do
    nova = agente.config[chave_da_marca].merge('documentos' => [])

    agente.update!(config: agente.config.merge(chave_da_marca => nova))

    expect(agente.reload.config[chave_da_marca]['documentos']).to eq([])
  end

  it 'deixa o agente ganhar a marca que ainda não tinha' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'sdr')

    comum.update!(config: comum.config.to_h.merge(conversa.state.slice(*described_class::CHAVES)))

    expect(comum.reload.config[chave_da_marca]['chave']).to eq('seguro_garantia')
  end

  it 'não muda o save do agente que não nasceu de um modelo' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'sdr')
    copia = Autonomia::Agents::Agent.find(comum.id)
    comum.update!(config: comum.config.to_h.merge('ferramentas_sugeridas' => %w[cep]))

    copia.update!(config: copia.config.to_h.merge('guardrails' => ['regra']))

    expect(comum.reload.config).not_to have_key('ferramentas_sugeridas')
    expect(comum.config['guardrails']).to eq(['regra'])
  end
end
