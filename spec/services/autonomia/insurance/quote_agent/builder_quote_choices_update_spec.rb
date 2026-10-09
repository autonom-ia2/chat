require 'rails_helper'

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder, type: :service do
  let(:account) { create(:account) }
  let(:agent) do
    described_class.new(
      account: account, nome_agente: 'Lia', nome_corretora: 'Sena', horario: 'dias úteis', comportamento: 'consultivo'
    ).call
  end

  it 'updates the three public choices while preserving the broker name and all four stored fields' do
    described_class.atualizar_escolhas!(agent, name: 'Bia', behavior: 'objetivo', horario: 'das 8h às 18h')

    expect(agent.reload.config.fetch(described_class::ESCOLHAS_DA_CORRETORA)).to include(
      'nome_agente' => 'Bia', 'nome_corretora' => 'Sena', 'comportamento' => 'objetivo', 'horario' => 'das 8h às 18h'
    )
    expect(agent.instrucao_do_sistema).to include('Bia', 'objetivo', 'das 8h às 18h')
  end

  it 'rejects an incomplete legacy choice set without inventing the broker name' do
    key = described_class::ESCOLHAS_DA_CORRETORA
    agent.update!(config: agent.config.except(key).merge(key => { 'nome_agente' => 'Lia' }))

    expect do
      described_class.atualizar_escolhas!(agent, name: 'Bia')
    end.to raise_error(Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas, 'nome_corretora')
  end
end
