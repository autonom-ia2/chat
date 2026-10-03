# A decisão do Decisor (#858) sobre uma mensagem: a já guardada, ou uma nova perguntada ao Jev.
#
# A decisão é única por (decisor, conversa, mensagem). Duas regras que perguntam a mesma coisa sobre a
# mesma mensagem pagam UMA pergunta. Na corrida entre duas, o índice único decide e a segunda lê a primeira.
class Autonomia::Decisores::Pergunta
  def initialize(decisor:, conversation:, message:, rule: nil, indice: nil)
    @decisor = decisor
    @conversation = conversation
    @message = message
    @rule = rule
    @indice = indice
  end

  def decisao
    existente || nova
  end

  def self.cota_esgotada?(account)
    Autonomia::DecisorDecisao.where(account_id: account.id, created_at: Time.current.all_month)
                             .where.not(status: 'sem_cota').count >= Autonomia::Decisores::LIMITE_MENSAL
  end

  private

  def existente
    Autonomia::DecisorDecisao.find_by(decisor_id: @decisor.id, conversation_id: @conversation.id, message_id: @message.id)
  end

  def nova
    return criar!(status: 'sem_cota', motivo: 'limite mensal de perguntas da conta atingido') if self.class.cota_esgotada?(@decisor.account)

    estado = Autonomia::Decisores::Estado.new(conversation: @conversation, message: @message)
    resultado = TypesafeAi::Decisor.new.decidir(decisor: @decisor, estado: estado)
    status = resultado.certeza >= @decisor.certeza_minima ? 'decidida' : 'duvida'
    decisao = criar!(status: status, resposta: resultado.resposta, certeza: resultado.certeza)
    contar!(status)
    Autonomia::Decisores::DuvidaJob.perform_later(decisao.id) if status == 'duvida'
    decisao
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    existente || raise
  end

  def criar!(atributos)
    Autonomia::DecisorDecisao.create!(
      decisor: @decisor, account_id: @decisor.account_id, conversation: @conversation, message: @message,
      automation_rule: @rule, proximo_passo: @indice&.+(1), **atributos
    )
  end

  # Contador em SQL atômico: dois jobs do mesmo Decisor ao mesmo tempo não perdem pergunta. Só soma
  # contadores e carimba a hora — não há validação a pular.
  def contar!(status)
    Autonomia::Decisor.update_counters( # rubocop:disable Rails/SkipsModelValidations
      @decisor.id, perguntas_count: 1, duvidas_count: status == 'duvida' ? 1 : 0, touch: :ultima_pergunta_em
    )
  end
end
