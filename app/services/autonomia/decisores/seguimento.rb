# O Decisor (#858) respondeu a chave que segue: grava os campos e retoma a automação no passo seguinte.
#
# Os campos vêm antes dos passos, para "criar card" já nascer com o contato certo. Os de card que não
# tinham card ainda são gravados de novo depois dos passos — é quando o card criado por eles existe.
# Falha na extração não para a automação: a decisão foi tomada, e o motivo fica na decisão.
#
# A regra é marcada como seguida ANTES dos passos: a retomada pode chegar duas vezes (Guia e pessoa,
# retry do job) e a mensagem ao cliente não pode sair duas vezes. Uma falha no meio deixa a regra
# marcada e não repete — a mesma escolha do ProcessPendingExecutionJob.
class Autonomia::Decisores::Seguimento
  def initialize(decisao:, rule:, conversation:, message:, indice:)
    @decisao = decisao
    @decisor = decisao.decisor
    @rule = rule
    @conversation = conversation
    @message = message
    @indice = indice
  end

  def perform
    return unless @decisao.seguir!(@rule.id, @indice)

    sem_card = aplicar_campos
    AutomationRules::ActionService.new(@rule, @rule.account, @conversation).perform(desde: @indice + 1, message: @message)
    aplicar(sem_card, card_novo: true) if sem_card.present?
  end

  private

  # Já extraído para esta mensagem (outra regra com o mesmo Decisor seguiu antes): não paga de novo.
  def aplicar_campos
    return {} if Array(@decisor.campos).empty? || @decisao.campos_extraidos.present?

    estado = Autonomia::Decisores::Estado.new(conversation: @conversation, message: @message)
    aplicar(Autonomia::Decisores::Extrator.new(decisor: @decisor).extrair(estado))
  rescue Autonomia::Decisores::Extrator::Error => e
    Rails.logger.warn("[autonomia][decisor] decisao=#{@decisao.id} extração falhou: #{e.message}")
    @decisao.update!(motivo: "extração não respondeu: #{e.message}")
    {}
  end

  # `card_novo`: o card não existia quando o Decisor respondeu, foram os passos desta regra que o criaram.
  def aplicar(valores, card_novo: false)
    resultado = Autonomia::Decisores::Aplicador.new(decisor: @decisor, conversation: @conversation.reload)
                                               .aplicar(valores, card_novo: card_novo)
    @decisao.update!(campos_extraidos: @decisao.campos_extraidos.to_h.merge(resultado.aplicados)) if resultado.aplicados.present?
    resultado.sem_card
  end
end
