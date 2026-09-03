# Grava uma FAQ aprovada como conhecimento do agente (#284 · 2b) pelo MESMO caminho das fontes
# (Ingestor#create_entry): KnowledgeEntry `ready` + embedding no modelo/coluna ativos. As FAQs
# aprovadas vivem numa fonte SINTÉTICA única por agente ("FAQ aprovadas", kind knowledge, aceita pela
# revisão) — o Retriever exclui entries de fontes reprovadas via `NOT IN`, que descartaria entries
# SEM fonte (NULL); a fonte própria mantém as FAQs recuperáveis e visíveis na aba Conhecimento.
class Autonomia::Agents::Faq::KnowledgeWriter
  FAQ_SOURCE_REFERENCE = 'FAQ aprovadas'.freeze
  FAQ_SOURCE_SUMMARY = 'Perguntas e respostas aprovadas pela equipe a partir de conversas resolvidas.'.freeze

  def initialize(agent:)
    @agent = agent
    @account = agent.account
  end

  # -> KnowledgeEntry. Levanta EmbeddingService::EmbeddingError quando a IA não está configurada/falha
  # (o chamador decide; a aprovação não deve gravar conhecimento sem vetor).
  def write!(suggestion)
    model = Autonomia::Agents::Config.active_embedding_model
    text = content_for(suggestion)
    vector = Autonomia::Agents::EmbeddingService.new(account: @account, model: model).embed(text)
    raise Autonomia::Agents::EmbeddingService::EmbeddingError, 'empty_embedding' if vector.blank?

    source = faq_source!
    entry = Autonomia::Agents::KnowledgeEntry.transaction do
      created = create_entry(source, suggestion, text, vector, model)
      bump_chunk_count!(source)
      created
    end
    write_large_embedding!(entry, vector) if Autonomia::Agents::Config.embedding_large?(model)
    entry
  end

  def self.faq_source?(source)
    source.metadata.to_h['faq_suggestions'] == true
  end

  private

  def content_for(suggestion)
    "Pergunta: #{suggestion.question}\nResposta: #{suggestion.answer}"
  end

  def faq_source!
    existing = @agent.sources.kind_knowledge.find { |source| self.class.faq_source?(source) }
    return existing if existing

    @agent.sources.create!(
      account: @account, kind: :knowledge, source_type: 'txt', reference: FAQ_SOURCE_REFERENCE,
      status: :ready, review_status: 'accepted', review_label: 'boa', confidence: 'alta', quality_score: 80,
      review_summary: FAQ_SOURCE_SUMMARY, reviewed_at: Time.current, synced_at: Time.current,
      metadata: { 'faq_suggestions' => true, 'chunk_count' => 0 }
    )
  end

  def create_entry(source, suggestion, text, vector, model)
    Autonomia::Agents::KnowledgeEntry.create!(
      autonomia_agent_id: @agent.id, account_id: @account.id, source_id: source.id,
      content: text, chunk_index: source.metadata.to_h['chunk_count'].to_i, status: :ready,
      metadata: { source_type: 'faq', material_type: 'faq', question_hash: suggestion.question_hash,
                  faq_suggestion_id: suggestion.id, conversation_id: suggestion.conversation_id },
      **(Autonomia::Agents::Config.embedding_large?(model) ? {} : { embedding: vector })
    )
  end

  def bump_chunk_count!(source)
    count = Autonomia::Agents::KnowledgeEntry.where(source_id: source.id).count
    # update_columns: só o contador de exibição; sem callbacks/validações (mesmo estilo de mark_ready!).
    source.update_columns(metadata: source.metadata.to_h.merge('chunk_count' => count), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # halfvec (3-large) por SQL cru sanitizado — a gem neighbor não conhece halfvec (mesmo do Ingestor).
  def write_large_embedding!(entry, vector)
    Autonomia::Agents::KnowledgeEntry.where(id: entry.id)
                                     .update_all(['embedding_large = ?::halfvec', "[#{vector.join(',')}]"]) # rubocop:disable Rails/SkipsModelValidations
  end
end
