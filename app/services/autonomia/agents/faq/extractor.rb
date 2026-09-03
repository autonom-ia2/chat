# Extrai 0..N pares pergunta/resposta de uma conversa RESOLVIDA e grava como sugestões PENDENTES
# do agente (#284 · 2b). Desenho copiado do Captain::Llm::ConversationFaqService, sem Captain:
#   - LLM pelo MESMO caminho do agente (Crm::Ai::ResponsesClient + CredentialResolver + FAQ_MODEL);
#   - saída estruturada (schema estrito) — nunca parse de texto livre;
#   - dedupe por hash da pergunta normalizada (sugestões já vistas) + por similaridade contra o
#     conhecimento existente do agente (Retriever, match forte);
#   - NUNCA levanta: falha de IA/JSON/provedor devolve [] e loga (a resolução da conversa não depende disto).
class Autonomia::Agents::Faq::Extractor
  MAX_FAQS = 5
  MAX_TRANSCRIPT_CHARS = 24_000

  FAQ_SCHEMA = {
    name: 'autonomia_agent_faq',
    schema: {
      type: 'object',
      properties: {
        faqs: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              question: { type: 'string' },
              answer: { type: 'string' },
              source_message_ids: { type: 'array', items: { type: 'integer' } }
            },
            required: %w[question answer source_message_ids],
            additionalProperties: false
          }
        }
      },
      required: %w[faqs],
      additionalProperties: false
    }
  }.freeze

  INSTRUCTIONS = <<~PROMPT.freeze
    Você cria candidatas a FAQ de alta qualidade a partir de conversas de atendimento já resolvidas.
    Só gere uma FAQ quando a conversa contiver conhecimento durável e reutilizável que ajudaria muitos clientes futuros.

    ## Regras de origem
    - A transcrição contém só mensagens do cliente e respostas de um ATENDENTE HUMANO (prefixadas com [m<id>]).
    - Baseie cada FAQ ESTRITAMENTE em fatos afirmados pelo atendente humano. Não infira, não generalize, não use conhecimento externo.
    - Se o atendente só cumprimenta, pede dados, promete verificar, envia anexo ou transfere: devolva {"faqs":[]}.
    - Em `source_message_ids`, liste os ids numéricos das mensagens do atendente ([m<id>]) que sustentam a resposta.

    ## Portão de decisão — devolva {"faqs":[]} a menos que TODA FAQ passe em:
    1. A resposta está inteira nas mensagens do atendente, não nas do cliente.
    2. É uma regra/procedimento público e durável, não uma ação em conta específica, revisão manual, orçamento, arquivo, link ou follow-up.
    3. Pode ser escrita sem identificadores privados, dados do cliente, URLs diretas, anexos, faturas, prints ou passos de ticket.
    4. A pergunta faria sentido numa central de ajuda mesmo sem esta conversa, este cliente e este atendente.

    ## Não gere FAQ para
    - Spam, propaganda, conteúdo abusivo, assuntos alheios ao negócio.
    - Problemas específicos de conta, pedido, pagamento, assinatura, login, entrega ou suporte técnico individual.
    - Conversas que só transferem, pedem para aguardar, coletam dados/anexos ou mandam abrir chamado.
    - Soluções temporárias, exceções pontuais, respostas incertas, problemas não resolvidos, reclamações, saudações.
    - Detalhes internos de fluxo de atendimento, escalonamento ou "alguém vai retornar".
    - Preço, política, prazo, disponibilidade ou questão legal, salvo resposta clara e estável do atendente.

    ## Qualidade
    - Prefira nenhuma FAQ a uma FAQ fraca ou estreita. No máximo #{MAX_FAQS} por conversa; normalmente 0 ou 1.
    - Perguntas gerais (central de ajuda), sem personalização; remova nomes, números de pedido, ids, telefones, e-mails.
    - Respostas completas, autocontidas, sustentadas pelas mensagens do atendente. Sem duplicatas na mesma resposta.
    - Escreva no MESMO idioma da conversa.
  PROMPT

  def initialize(agent:, conversation:)
    @agent = agent
    @conversation = conversation
  end

  # -> Array<FaqSuggestion> criadas (pode ser []). Nunca levanta.
  def call
    transcript = Autonomia::Agents::Faq::Transcript.new(@conversation).build
    return [] if transcript.human_message_ids.empty?

    generate(transcript.text).first(MAX_FAQS).filter_map { |faq| persist(faq, transcript.human_message_ids) }
  rescue StandardError => e
    Rails.logger.warn("[autonomia][faq] extract_failed agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
    []
  end

  private

  # Lista de hashes { 'question', 'answer', 'source_message_ids' }. [] em qualquer falha de IA.
  def generate(text)
    credential = Crm::Ai::CredentialResolver.new(account: @agent.account).resolve
    return [] if credential.blank?

    raw = Crm::Ai::ResponsesClient.new(credential: credential, feature: Autonomia::Agents::Config::FAQ_FEATURE,
                                       account: @agent.account)
                                  .create(model: Autonomia::Agents::Config::FAQ_MODEL, instructions: INSTRUCTIONS,
                                          input: text.first(MAX_TRANSCRIPT_CHARS), schema: FAQ_SCHEMA,
                                          reasoning_effort: Autonomia::Agents::Config::FAQ_REASONING_EFFORT)
    parsed = JSON.parse(raw[:text].to_s)
    faqs = parsed.is_a?(Hash) ? parsed['faqs'] : nil
    faqs.is_a?(Array) ? faqs.select { |faq| faq.is_a?(Hash) } : []
  rescue Crm::Ai::ResponsesClient::Error, JSON::ParserError => e
    # Sem e.message no log (pode ecoar o prompt/transcrição).
    Rails.logger.warn("[autonomia][faq] llm_failed agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
    []
  end

  def persist(faq, human_message_ids)
    question = faq['question'].to_s.strip
    answer = faq['answer'].to_s.strip
    return if question.blank? || answer.blank?
    return if already_suggested?(question)
    return if known_in_knowledge?(question)

    @agent.faq_suggestions.create!(
      account_id: @agent.account_id, conversation_id: @conversation.id,
      question: question, answer: answer,
      source_message_ids: Array(faq['source_message_ids']).map(&:to_i) & human_message_ids
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Já sugerida (pendente, aprovada, editada OU ignorada — não insistir) com a mesma pergunta normalizada.
  def already_suggested?(question)
    @agent.faq_suggestions.exists?(question_hash: Autonomia::Agents::FaqSuggestion.question_hash_for(question))
  end

  # A base do agente já responde isto? Match FORTE do Retriever (custo: 1 embedding da pergunta).
  # O Retriever nunca levanta (degrada para []) — falha de embedding não bloqueia a sugestão.
  def known_in_knowledge?(question)
    return false if @agent.knowledge_disabled?

    hits = Autonomia::Agents::Retriever.new(agent: @agent).retrieve(question, top_k: 3)
    hits.any? { |entry| entry.neighbor_distance.to_f <= Autonomia::Agents::Config::RETRIEVAL_STRONG_MATCH }
  end
end
