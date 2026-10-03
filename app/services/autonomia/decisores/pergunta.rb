# A decisão do Decisor (#858) sobre um alvo: a já guardada, ou uma nova perguntada ao Jev.
#
# O alvo é uma mensagem de conversa (regra de automação) ou um card num gatilho de etapa (automação de
# etapa do CRM, `gatilho` = a marca daquela entrada ou saída). A decisão é única por alvo: duas
# automações que perguntam a mesma coisa sobre o mesmo alvo pagam UMA pergunta. Na corrida entre duas,
# o índice único decide e a segunda lê a primeira. Sem nada para ler no que o Decisor declara (só áudio
# ou imagem, card vazio), não vai ao Jev: a decisão fica `sem_conteudo`, sem seguir.
class Autonomia::Decisores::Pergunta
  # `espera`: a automação que vai seguir depois, {regra, indice} ou {etapa, execucao}.
  def initialize(decisor:, conversation: nil, message: nil, card: nil, gatilho: nil, rule: nil, espera: nil) # rubocop:disable Metrics/ParameterLists
    @decisor = decisor
    @conversation = conversation
    @message = message
    @card = card
    @gatilho = gatilho
    @rule = rule
    @espera = espera
  end

  def decisao
    existente || nova
  end

  def self.cota_esgotada?(account)
    Autonomia::DecisorDecisao.where(account_id: account.id, created_at: Time.current.all_month)
                             .where.not(status: %w[sem_cota sem_conteudo]).count >= Autonomia::Decisores::LIMITE_MENSAL
  end

  private

  def existente
    alvo = @message ? { conversation_id: @conversation.id, message_id: @message.id } : { crm_card_id: @card.id, gatilho: @gatilho }
    Autonomia::DecisorDecisao.find_by(decisor_id: @decisor.id, **alvo)
  end

  def nova
    estado = Autonomia::Decisores::Estado.new(conversation: @conversation, message: @message, card: @card,
                                              leituras: @decisor.leituras_efetivas)
    return criar!(status: 'sem_conteudo', motivo: 'não há o que ler no que o Decisor lê') if estado.vazio?
    return criar!(status: 'sem_cota', motivo: 'limite mensal de perguntas da conta atingido') if self.class.cota_esgotada?(@decisor.account)

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
      decisor: @decisor, account_id: @decisor.account_id, conversation: @conversation, message: @message, card: @card,
      gatilho: @gatilho, automation_rule: @rule, esperas: Array.wrap(@espera), **atributos
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
