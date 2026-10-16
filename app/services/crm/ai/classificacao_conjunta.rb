# Uma chamada da IA do CRM para todos os cards que a mensagem tocou (#1693). A conversa vai uma vez só; cada card vai
# com o pacote do funil dele (StageClassifier#pacote); a resposta é uma por card, no mesmo formato da avaliação de um
# card (StageClassifier::CLASSIFICATION_SCHEMA) mais o card_id.
#
#   Crm::Ai::ClassificacaoConjunta.new(client:, classificadores:, model:).perform
#   # => { card_id => classificação (como StageClassifier#perform) }, só dos cards que a IA respondeu
#
# classificadores: um StageClassifier por card, o principal primeiro (a conversa e os outros pedidos saem dele).
#
# Card tocado ligado a outras conversas (outro canal, #1664): as mensagens delas vão no pacote dele, em
# `other_conversations_messages` (Crm::Ai::OutrasConversas, com os limites por card e por chamada).
class Crm::Ai::ClassificacaoConjunta
  ITEM = Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA[:schema].then do |schema|
    schema.merge(properties: { card_id: { type: 'integer' } }.merge(schema[:properties]),
                 required: ['card_id', *schema[:required]])
  end.freeze
  SCHEMA = {
    name: 'stage_classification_cards',
    schema: {
      type: 'object',
      properties: { cards: { type: 'array', items: ITEM } },
      required: %w[cards],
      additionalProperties: false
    }
  }.freeze

  def initialize(client:, classificadores:, model:, reasoning_effort: Crm::Ai::Config::CLASSIFY_REASONING_EFFORT)
    @client = client
    @classificadores = classificadores
    @model = model
    @reasoning_effort = reasoning_effort
  end

  def perform
    response = @client.create(model: @model, instructions: instructions, input: entrada.to_json, schema: SCHEMA,
                              reasoning_effort: @reasoning_effort)
    por_card(JSON.parse(response[:text]), response)
  end

  private

  def instructions
    Crm::Ai::ClassifierPrompt.para_varios(@classificadores.flat_map { |classificador| classificador.pacote[:eligible_agents] })
  end

  def entrada
    outras = Crm::Ai::OutrasConversas.por_card(@classificadores)
    pacotes = @classificadores.map do |classificador|
      mensagens = outras[classificador.pacote.dig(:card, :id)]
      mensagens ? classificador.pacote.merge(other_conversations_messages: mensagens) : classificador.pacote
    end
    @classificadores.first.conversa.merge(cards: pacotes)
  end

  # Resposta sem um card, ou com card que não foi perguntado: aquele card fica sem avaliação nesta rodada.
  def por_card(resposta, response)
    ids = @classificadores.map { |classificador| classificador.pacote.dig(:card, :id) }
    Array(resposta['cards']).each_with_object({}) do |item, classificacoes|
      next unless item.is_a?(Hash) && ids.include?(item['card_id']) && !classificacoes.key?(item['card_id'])

      classificacoes[item['card_id']] = item.with_indifferent_access.merge(
        model_used: @model, usage: response[:usage], response_id: response[:response_id]
      )
    end
  end
end
