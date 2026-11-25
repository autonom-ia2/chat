require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados do
  let(:account) { create(:account) }

  before { enable_test_encryption! }

  it 'disponível só com a flag do modelo, as duas das prontas e o cofre' do
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    expect(described_class.disponiveis(account)).to eq(['seguro_viagem_universal'])
    account.disable_features!('agente_ferramentas_prontas_consultas')
    expect(described_class.disponiveis(account)).to eq([])
  end

  it 'os slugs do catálogo existem no Registry' do
    pending 'as ferramentas entram no Registry na Tarefa 19'
    slugs = described_class::MODELOS.values.flat_map { |m| m[:ferramentas_nativas] }
    expect(slugs - Autonomia::Agents::Tools::Registry.slugs).to eq([])
  end

  it 'grava as quatro chaves da conversa do PR 1 em texto' do
    expect(described_class::CONVERSA_DO_PR1.keys).to eq(
      %w[conversa_espera_a_fala conversa_em_fila conversa_entrega_inteira conversa_ritmo_do_canal]
    )
    expect(described_class::CONVERSA_DO_PR1.values.uniq).to eq([true])
  end

  it 'DadosIncompletos é tratada pelas portas da Lia' do
    expect(described_class::DadosIncompletos.ancestors)
      .to include(Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas)
  end

  it 'modelo e ferramentas: nil para quem não é contratado' do
    agente = Autonomia::Agents::Agent.new(account: account, config: {})
    expect(described_class.modelo(agente)).to be_nil
    expect(described_class.ferramentas(agente)).to be_nil
  end
end
