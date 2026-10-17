# O que a avaliação de card pagou para a memória (#1601, A8): `memoria_ops` fica gravado no card
# (metadata.ai.memoria_pendente) ANTES de a avaliação ser aplicada; no fim dela, ou no retry do job que caiu no meio,
# é aplicado (Crm::Memoria::Escritor) sem chamar o modelo de novo. O id da avaliação nasce aqui, uma vez por chamada
# paga, e entra na chave estrutural de cada operação. A avaliação superada (outra agendada depois dela, relendo o card)
# não grava nada.
module Crm::Memoria::Pendente
  CHAVE = 'memoria_pendente'.freeze
  MAXIMO_DE_OPERACOES = 20

  module_function

  # A avaliação deste card leva a memória de carona: flag ligada e card com contato.
  def avaliar?(card)
    card.contact_id.present? && Crm::Memoria.ligada?(card.account)
  end

  # `memoria_token`: o agendamento que a avaliação atendia, lido ANTES da chamada (Crm::Memoria::ParaAvaliacao).
  def guardar!(card:, classificacao:)
    ops = Array(classificacao[:memoria_ops]).first(MAXIMO_DE_OPERACOES)
    return if ops.empty? || !avaliar?(card)

    pendente = { 'avaliacao_id' => SecureRandom.uuid, 'token' => classificacao[:memoria_token], 'modelo' => classificacao[:model_used],
                 'refs' => classificacao[:memoria_refs].to_h, 'ops' => ops.map { |op| op.to_h.stringify_keys } }
    mexer_no_ai(card) { |ai| ai.merge(CHAVE => pendente) }
  end

  # Falhou ao aplicar: vai ao rastreador e o pendente sai do card mesmo assim. Nunca trava a avaliação do card (o job
  # que relançasse aqui a cada retry pararia de avaliar).
  def aplicar!(card)
    pendente = Crm::Card.find_by(id: card.id)&.metadata.to_h.dig('ai', CHAVE)
    return if pendente.blank?

    begin
      Crm::Memoria::Escritor.new(card: Crm::Card.find(card.id), pendente: pendente).aplicar unless superada?(card, pendente)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: card.account).capture_exception
    end
    mexer_no_ai(card) { |ai| ai[CHAVE]&.dig('avaliacao_id') == pendente['avaliacao_id'] ? ai.except(CHAVE) : ai }
  end

  def descartar!(card)
    return if Crm::Card.find_by(id: card.id)&.metadata.to_h.dig('ai', CHAVE).blank?

    mexer_no_ai(card) { |ai| ai.except(CHAVE) }
  end

  # Relê o card: outra avaliação agendada depois desta (token mais novo) torna esta superada.
  def superada?(card, pendente)
    return false if pendente['token'].blank?

    Crm::Ai::Observer.new(card: Crm::Card.find(card.id)).agendada_desde?(pendente['token'])
  end

  def mexer_no_ai(card)
    Crm::Card.transaction do
      fresco = Crm::Card.lock.find(card.id)
      metadata = fresco.metadata.to_h.deep_dup
      metadata['ai'] = yield(metadata['ai'].to_h)
      fresco.update_columns(metadata: metadata) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
