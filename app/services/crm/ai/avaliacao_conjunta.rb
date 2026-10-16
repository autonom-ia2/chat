# A IA do CRM avalia, numa chamada só, os cards que a mensagem do cliente tocou (#1693, flag `crm_avaliar_toda_mensagem`).
#
#   Crm::Ai::AvaliacaoConjunta.new(cards:, principal:).perform
#   # => { card_id => Crm::Ai::Evaluator::Result }
#
# Cada card passa pelas guardas de sempre (Evaluator#motivo_para_pular: IA do funil ligada, debounce, card aberto); o
# card tocado é avaliado mesmo fora do foco, porque a IA de assunto disse que a mensagem é sobre ele. Sobrando um card
# só, é a avaliação de sempre, com a mesma entrada. Sobrando dois ou mais, uma chamada (Crm::Ai::ClassificacaoConjunta)
# e cada resposta aplicada no seu card (Evaluator#aplicar).
#
# O pedido de atendente segue a regra do card principal: só ele pode passar a conversa (Evaluator `passar:`), e o
# HandoffExecutor mantém as guardas dele (assunto em foco, pessoa no nome, agente nosso como dono, intervalo).
#
# Custo: uma chamada por mensagem, registrada pelo ResponsesClient como sempre (feature avaliacao_card, no funil do
# primeiro card). Uma segunda só quando o principal muda de etapa e a etapa nova tem outra regra de pedido de atendente.
class Crm::Ai::AvaliacaoConjunta
  def initialize(cards:, principal:, trigger: 'message')
    @cards = cards
    @principal = principal
    @trigger = trigger
  end

  def perform
    resultados = {}
    prontos = []
    @cards.each do |card|
      avaliador = Crm::Ai::Evaluator.new(card: card, trigger: @trigger, tocado: true, passar: card.id == @principal&.id)
      motivo = avaliador.motivo_para_pular
      motivo ? resultados[card.id] = pulado(motivo) : prontos << [card, avaliador]
    end
    return resultados if prontos.empty?
    return resultados.merge(prontos[0][0].id => prontos[0][1].perform) if prontos.one?

    resultados.merge(avaliar_juntos(prontos))
  end

  private

  def avaliar_juntos(prontos)
    ids = prontos.map { |card, _avaliador| card.id }
    Crm::Ai::MediaEnricher.new(card: prontos[0][0]).perform if Crm::Ai::Config.media_enabled?
    classificacoes = classificar(prontos, ids)
    Rails.logger.info("[crm][avaliacao_conjunta] cards=#{ids.join(',')} sem_resposta=#{(ids - classificacoes.keys).join(',')}")
    prontos.to_h { |card, avaliador| [card.id, aplicar(card, avaliador, classificacoes[card.id])] }
  rescue Crm::Ai::ResponsesClient::Error => e
    ids.index_with { Crm::Ai::Evaluator::Result.new(status: :failed, error: e.message) }
  rescue JSON::ParserError
    ids.index_with { Crm::Ai::Evaluator::Result.new(status: :failed, error: 'invalid_llm_json') }
  end

  def classificar(prontos, ids)
    client = prontos[0][1].classify_client
    classificadores = prontos.map { |card, avaliador| avaliador.stage_classifier(client: client, fora: ids - [card.id]) }
    Crm::Ai::ClassificacaoConjunta.new(client: client, classificadores: classificadores, model: modelo(prontos)).perform
  end

  # Um card com movimento automático liberado pede o modelo dele, como na avaliação de um card.
  def modelo(prontos)
    modelos = prontos.map { |_card, avaliador| avaliador.modelo }
    modelos.include?(Crm::Ai::Config::MODEL_AUTO_MOVE) ? Crm::Ai::Config::MODEL_AUTO_MOVE : Crm::Ai::Config::MODEL_CLASSIFY
  end

  # A falha de um card (a segunda leitura do pedido de atendente, depois de mover) não derruba os outros.
  def aplicar(card, avaliador, classificacao)
    return pulado('sem_resposta') if classificacao.nil?

    pedido_fora_do_principal(card, classificacao)
    avaliador.aplicar(classificacao, conjunta: true)
  rescue Crm::Ai::ResponsesClient::Error => e
    Crm::Ai::Evaluator::Result.new(status: :failed, error: e.message)
  rescue JSON::ParserError
    Crm::Ai::Evaluator::Result.new(status: :failed, error: 'invalid_llm_json')
  end

  # O pedido de atendente segue a regra do principal: o de outro card não passa a conversa, e fica no log.
  def pedido_fora_do_principal(card, classificacao)
    return if card.id == @principal&.id || !Crm::Ai::HandoffIntent.requested?(classificacao[:handoff])

    Rails.logger.info("[crm][avaliacao_conjunta] pedido de atendente fora do principal card=#{card.id}")
  end

  def pulado(motivo)
    Crm::Ai::Evaluator::Result.new(status: :skipped, error: motivo)
  end
end
