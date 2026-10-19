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

  # #1802: a base do Guia segue o pacote de tradução da conta.
  describe 'base por pacote' do
    let(:nicho) { Autonomia::Agents::Nicho }
    let(:geral) { conta }
    let(:corretora) do
      conta_corretora = create(:account)
      conta_corretora.update!(internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'corretora' })
      conta_corretora
    end
    let(:base_da_corretora) { Autonomia::Guide::BaseDoPacote::PASTA.join('seguros/corretora/guia-produto.md') }

    it 'keeps the general account on the same file and version as before, with the switch on' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(described_class.kb_path_for(geral)).to eq(described_class::KB_PATH)
        expect(described_class.kb_version(geral)).to eq(described_class.kb_version)
      end
    end

    it 'gives the brokerage its own base, with the words of the screen' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(described_class.kb_path_for(corretora)).to eq(base_da_corretora)
        expect(described_class.kb_version(corretora)).not_to eq(described_class.kb_version)

        guia = described_class.ensure_for(corretora)
        conteudo = guia.knowledge_entries.pluck(:content).join("\n")
        expect(conteudo).to include('**Fechou o seguro**', '**Nova cotação**')
        expect(conteudo).not_to include('**Marcar como ganho**')
      end
    end

    it 'keeps the brokerage on the general base with the switch off' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
        expect(described_class.kb_path_for(corretora)).to eq(described_class::KB_PATH)
        expect(described_class.versao_da_instalacao).to eq(described_class.kb_version)
      end
    end

    it 'falls back to the general base, without error, when the pack has no file' do
      Dir.mktmpdir do |vazia|
        stub_const('Autonomia::Guide::BaseDoPacote::PASTA', Pathname(vazia))

        with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
          expect(described_class.kb_path_for(corretora)).to eq(described_class::KB_PATH)
          expect(described_class.kb_version(corretora)).to eq(described_class.kb_version)
        end
        expect(described_class.versao_da_instalacao).to eq(described_class.kb_version)
      end
    end

    it 'reseeds the brokerage once when the switch turns on, and the general account not at all' do
      guia_geral = described_class.ensure_for(geral)
      guia_corretora = described_class.ensure_for(corretora)

      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(described_class.ready_agent_for(geral)).to eq(guia_geral)
        expect(described_class.ready_agent_for(corretora)).to be_nil

        described_class.ensure_for(corretora)

        expect(described_class.ready_agent_for(corretora)).to eq(guia_corretora)
      end
    end
  end
end
