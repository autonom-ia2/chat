require 'rails_helper'

# #284 (2b) — FAQ aprovada vira KnowledgeEntry pelo caminho das fontes (embedding + fonte sintética).
RSpec.describe Autonomia::Agents::Faq::KnowledgeWriter do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:suggestion) { agent.faq_suggestions.create!(account: account, question: 'Qual o prazo?', answer: 'Até 5 dias.') }
  let(:vector) { Array.new(1536, 0.01) }

  before do
    allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return(Autonomia::Agents::Config::EMBEDDING_MODEL_SMALL)
    embedding = instance_double(Autonomia::Agents::EmbeddingService, embed: vector)
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding)
  end

  it 'creates a ready entry with the embedding and the dedupe hash in the metadata' do
    entry = described_class.new(agent: agent).write!(suggestion)

    expect(entry).to have_attributes(status: 'ready', content: "Pergunta: Qual o prazo?\nResposta: Até 5 dias.", chunk_index: 0)
    expect(entry.metadata).to include('question_hash' => suggestion.question_hash, 'faq_suggestion_id' => suggestion.id)
    expect(entry.embedding).to be_present
  end

  it 'keeps every approved FAQ under a single accepted synthetic source per agent' do
    first = described_class.new(agent: agent).write!(suggestion)
    other = agent.faq_suggestions.create!(account: account, question: 'Frete?', answer: 'Grátis.')
    second = described_class.new(agent: agent).write!(other)

    expect(second.source_id).to eq(first.source_id)
    expect(second.chunk_index).to eq(1)
    expect(first.source).to have_attributes(review_status: 'accepted', status: 'ready', kind: 'knowledge')
    expect(described_class.faq_source?(first.source)).to be(true)
    expect(first.source.metadata['chunk_count']).to eq(2)
    expect(agent.sources.count).to eq(1)
  end

  it 'is retrievable through the agent knowledge scope used by the Retriever' do
    entry = described_class.new(agent: agent).write!(suggestion)

    expect(agent.knowledge_entries.ready.where.not(source_id: [-1]).pluck(:id)).to include(entry.id)
    expect(agent.accepted_sources.pluck(:id)).to include(entry.source_id)
  end

  it 'raises when the embedding cannot be produced and writes nothing' do
    allow(Autonomia::Agents::EmbeddingService).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::EmbeddingService, embed: []))

    expect { described_class.new(agent: agent).write!(suggestion) }
      .to raise_error(Autonomia::Agents::EmbeddingService::EmbeddingError)
    expect(agent.knowledge_entries.count).to eq(0)
    expect(agent.sources.count).to eq(0)
  end
end
