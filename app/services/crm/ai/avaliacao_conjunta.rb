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
# Pedido de atendente (decisão 1a do Rodrigo, 16/10): vale a regra do assunto a que o cliente ligou o pedido, ou seja,
# do card em que a IA o pôs; sem ligação, a IA o põe no principal. Só esse card passa a conversa (Evaluator#aplicar
# `passar:`); fora do principal, pela regra dele mesmo fora do foco (HandoffExecutor `pelo_card`), com as outras guardas
# de sempre (pessoa no nome, agente nosso como dono, intervalo). Sem pedido em nenhum card, o principal segue como
# antes. Com um card só (sem chamada conjunta), vale a regra de antes: a do assunto em foco.
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
      avaliador = Crm::Ai::Evaluator.new(card: card, trigger: @trigger, tocado: true)
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
    aplicar_todos(prontos, ids, classificar(prontos, ids))
  rescue Crm::Ai::ResponsesClient::Error => e
    ids.index_with { Crm::Ai::Evaluator::Result.new(status: :failed, error: e.message) }
  rescue JSON::ParserError
    ids.index_with { Crm::Ai::Evaluator::Result.new(status: :failed, error: 'invalid_llm_json') }
  end

  def aplicar_todos(prontos, ids, classificacoes)
    Rails.logger.info("[crm][avaliacao_conjunta] cards=#{ids.join(',')} sem_resposta=#{(ids - classificacoes.keys).join(',')}")
    passa = quem_passa(ids, classificacoes)
    prontos.to_h do |card, avaliador|
      [card.id, aplicar(avaliador, classificacoes[card.id], passar: card.id == passa, pelo_card: card.id == passa && passa != @principal&.id)]
    end
  end

  def classificar(prontos, ids)
    client = prontos[0][1].classify_client
    classificadores = prontos.map { |card, avaliador| avaliador.stage_classifier(client: client, fora: ids - [card.id]) }
    Crm::Ai::ClassificacaoConjunta.new(client: client, classificadores: classificadores, model: modelo(prontos),
                                       principal_id: @principal&.id).perform
  end

  # Um card com movimento automático liberado pede o modelo dele, como na avaliação de um card.
  def modelo(prontos)
    modelos = prontos.map { |_card, avaliador| avaliador.modelo }
    modelos.include?(Crm::Ai::Config::MODEL_AUTO_MOVE) ? Crm::Ai::Config::MODEL_AUTO_MOVE : Crm::Ai::Config::MODEL_CLASSIFY
  end

  # A falha de um card (a segunda leitura do pedido de atendente, depois de mover, ou um erro ao gravar) não derruba os
  # outros e não sobe: a chamada já foi paga, e o retry do job pagaria de novo. Vai para o rastreador. Aceito: o que já
  # foi gravado nele antes do erro (etapa, valor, campos) fica, sem transação que desfaça, e o card sai como failed;
  # nenhuma chamada se repete.
  def aplicar(avaliador, classificacao, passar:, pelo_card:)
    return pulado('sem_resposta') if classificacao.nil?

    avaliador.aplicar(classificacao, conjunta: true, passar: passar, pelo_card: pelo_card)
  rescue Crm::Ai::ResponsesClient::Error => e
    Crm::Ai::Evaluator::Result.new(status: :failed, error: e.message)
  rescue JSON::ParserError
    Crm::Ai::Evaluator::Result.new(status: :failed, error: 'invalid_llm_json')
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Crm::Ai::Evaluator::Result.new(status: :failed, error: e.class.name)
  end

  # O card em que está o pedido de atendente; sem pedido, o principal. A IA põe o pedido num card só; se puser em mais
  # de um, vale o principal, ou o primeiro da lista, e o resto fica no log.
  def quem_passa(ids, classificacoes)
    pedem = ids.select { |id| pede_pessoa?(classificacoes.dig(id, :handoff)) }
    return @principal&.id if pedem.empty? || pedem.include?(@principal&.id)

    Rails.logger.info("[crm][avaliacao_conjunta] pedido de atendente em mais de um card=#{pedem.join(',')}") if pedem.many?
    pedem.first
  end

  # IA entende a conversa F1: a promessa do nosso assistente (só existe no schema com a flag) também aponta o card.
  def pede_pessoa?(handoff)
    Crm::Ai::HandoffIntent.requested?(handoff) || Crm::Ai::FatosDaConversa.promessa?(handoff)
  end

  def pulado(motivo)
    Crm::Ai::Evaluator::Result.new(status: :skipped, error: motivo)
  end
end
