require 'rails_helper'

# Ferramenta nova do Guia chega aos Guias já semeados (#900).
#
# O `kb_version` faz hash só da base e da instrução. Antes, o estado canônico
# não conferia as ferramentas, e um Guia semeado antes de `formato_da_acao`
# continuava "fresco" sem ela — a ferramenta existia no código e nenhum Guia
# em produção a recebia.
RSpec.describe Autonomia::Guide::Seed do
  let(:conta) { create_account_and_user.first }
  let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService) }

  before do
    allow(described_class).to receive(:eligible?).and_return(true)
    coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
    dimensao = coluna == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN ? 3072 : 1536
    allow(embedder).to receive(:embed_batch) { |textos| textos.map { Array.new(dimensao, 0.01) } }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
  end

  it 'semeia o Guia com todas as ferramentas, inclusive formato_da_acao' do
    expect(described_class.ensure_for(conta).native_tool_slugs).to eq(described_class::FERRAMENTAS)
  end

  it 'não considera pronto o Guia semeado sem uma ferramenta, e a devolve na cura', :aggregate_failures do
    guia = described_class.ensure_for(conta)
    antigas = described_class::FERRAMENTAS - ['formato_da_acao']
    guia.update!(config: guia.config.merge('native_tool_slugs' => antigas))

    expect(described_class.ready_agent_for(conta)).to be_nil

    described_class.ensure_for(conta)

    expect(guia.reload.native_tool_slugs).to eq(described_class::FERRAMENTAS)
    expect(described_class.ready_agent_for(conta)).to eq(guia)
  end
end
