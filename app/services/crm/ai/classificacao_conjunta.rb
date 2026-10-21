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
  # Memória das IAs (#1601): o mesmo, com `memoria_ops` em cada card (Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA_MEMORIA).
  ITEM_MEMORIA = Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA_MEMORIA[:schema].then do |schema|
    schema.merge(properties: { card_id: { type: 'integer' } }.merge(schema[:properties]), required: ['card_id', *schema[:required]])
  end.freeze
  SCHEMA_MEMORIA = SCHEMA.merge(schema: SCHEMA[:schema].merge(properties: { cards: { type: 'array', items: ITEM_MEMORIA } })).freeze

  # O schema da avaliação conjunta a partir do schema de um card: o mesmo item, com o card_id na frente.
  def self.com_cards(esquema_do_card)
    corpo = esquema_do_card[:schema]
    item = corpo.merge(properties: { card_id: { type: 'integer' } }.merge(corpo[:properties]), required: ['card_id', *corpo[:required]])
    SCHEMA.merge(schema: SCHEMA[:schema].merge(properties: { cards: { type: 'array', items: item } })).freeze
  end

  # principal_id: o card principal da mensagem; o pacote dele vai com "principal": true (onde fica o pedido de
  # atendente que o cliente não ligou a nenhum assunto).
  def initialize(client:, classificadores:, model:, principal_id: nil, reasoning_effort: Crm::Ai::Config::CLASSIFY_REASONING_EFFORT)
    @client = client
    @principal_id = principal_id
    @classificadores = classificadores
    @model = model
    @reasoning_effort = reasoning_effort
  end

  def perform
    response = @client.create(model: @model, instructions: instructions, input: entrada.to_json, schema: esquema,
                              reasoning_effort: @reasoning_effort)
    por_card(JSON.parse(response[:text]), response)
  end

  private

  def instructions
    Crm::Ai::ClassifierPrompt.para_varios(@classificadores.flat_map { |classificador| classificador.pacote[:eligible_agents] },
                                          memoria: memoria?, email_autoria: @classificadores.first.email_autoria?,
                                          nao_e_negocio: nao_e_negocio?,
                                          pedido_anterior: @classificadores.any? { |classificador| classificador.pacote.key?(:previous_card) },
                                          fatos: @classificadores.first.fatos?, fecha_card: @classificadores.first.fecha_card?)
  end

  # #1828: com a flag `email_autoria`, `saida_da_copia` no topo (é da conversa, não de um card); sem ela, o de sempre.
  def esquema
    base = memoria? ? SCHEMA_MEMORIA : SCHEMA
    # #1922 e IA entende a conversa F1 e F3: o item sai do schema de um card quando ele muda com a flag da conta.
    primeiro = @classificadores.first
    base = self.class.com_cards(primeiro.esquema_do_card) if nao_e_negocio? || primeiro.fatos? || primeiro.fecha_card?
    email_autoria? ? Crm::Email::SaidaDaCopia.com_saida(base) : base
  end

  # #1922: com a flag `crm_ia_arquiva_lixo`, cada card ganha o campo `nao_e_negocio` (StageClassifier#esquema_do_card).
  def nao_e_negocio? = @classificadores.first.nao_e_negocio?

  def email_autoria? = @classificadores.first.email_autoria?

  # A conversa e os ids locais (m1..mN) saem do primeiro classificador: são os dele que vão ao modelo. O agendamento é
  # o de cada card.
  def memoria?
    @classificadores.first.memoria?
  end

  def memoria_de(card_id)
    return {} unless memoria?

    proprio = @classificadores.find { |classificador| classificador.pacote.dig(:card, :id) == card_id }
    { memoria_refs: @classificadores.first.memoria_interna[:memoria_refs], memoria_token: proprio&.memoria_interna&.dig(:memoria_token) }
  end

  def entrada
    outras = Crm::Ai::OutrasConversas.por_card(@classificadores)
    pacotes = @classificadores.map do |classificador|
      id = classificador.pacote.dig(:card, :id)
      pacote = classificador.pacote.merge(principal: id == @principal_id)
      outras[id] ? pacote.merge(other_conversations_messages: outras[id]) : pacote
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
      ).merge(memoria_de(item['card_id'])).merge(resposta.slice(Crm::Email::SaidaDaCopia::CAMPO))
    end
  end
end
